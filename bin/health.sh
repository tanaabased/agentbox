#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/var/db/tanaab/agentbox/health.env"
AGENTBOX_LOG_DIR="/var/log/tanaab/agentbox"
LOG_FILE="${AGENTBOX_LOG_DIR}/health.log"
HEALTH_LABEL="dev.tanaab.agentbox.health"
TAILSCALED_LABEL="dev.tanaab.agentbox.tailscaled"
TAILSCALED_STATE_FILE="/var/db/tanaab/agentbox/tailscale/tailscaled.state"
OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL="ai.openclaw.gateway"
OPENCLAW_FINALIZER_LABEL="dev.tanaab.agentbox.openclaw-finalize"
AGENTBOX_OPENCLAW_SERVICE_KIND="openclaw-gateway"
OPENCLAW_DISABLE_LAUNCH_AGENT_MARKER=".openclaw/disable-launchagent"
HOMEBREW_TAILSCALE_LABEL="homebrew.mxcl.tailscale"
OFFICIAL_TAILSCALE_LABEL="com.tailscale.tailscaled"
OFFICIAL_TAILSCALE_PLIST="/Library/LaunchDaemons/${OFFICIAL_TAILSCALE_LABEL}.plist"
SSHD_BIN="/usr/sbin/sshd"
SOCKETFILTERFW="/usr/libexec/ApplicationFirewall/socketfilterfw"
SSH_ACCESS_GROUP="com.apple.access_ssh"

AGENTBOX_HEALTH_EXPECTED_HOSTNAME=""
AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME=""
AGENTBOX_HEALTH_TAILSCALE_ENABLED="0"
AGENTBOX_HEALTH_BREWGROUP_ENABLED="0"
AGENTBOX_HEALTH_BREWGROUP="off"
AGENTBOX_HEALTH_TRUSTED_BREWGROUP_ENABLED="0"
AGENTBOX_HEALTH_TRUSTED_BREWGROUP="off"
AGENTBOX_HEALTH_BREW_PREFIX=""
AGENTBOX_HEALTH_HOMEBREW_PATHS_FILE="/etc/paths.d/00-agentbox-homebrew"
AGENTBOX_HEALTH_AGENTBOX_VERSION=""
AGENTBOX_HEALTH_ADMIN_USER=""
AGENTBOX_HEALTH_OPENCLAW_USER=""
AGENTBOX_HEALTH_OPENCLAW_FULL_NAME=""
AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED="0"
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_LABEL=""
AGENTBOX_HEALTH_OPENCLAW_FINALIZER_LABEL="${OPENCLAW_FINALIZER_LABEL}"
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_BIND=""
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE=""
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT=""
AGENTBOX_HEALTH_OPENCLAW_AUTH_CHOICE=""
AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED="0"
AGENTBOX_HEALTH_SSH_ALLOWED_USERS=""
AGENTBOX_HEALTH_MANAGED_MACOS_RUNNER="0"
STATE_LOADED="0"
SSH_HARDENING_DIAGNOSTIC=""

if [[ -r "${STATE_FILE}" ]]; then
  # shellcheck source=/dev/null
  . "${STATE_FILE}"
  STATE_LOADED="1"
fi

dotenv_double_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "${value}"
}

shell_single_quote() {
  local value="$1"

  printf "'"
  printf "%s" "${value}" | sed "s/'/'\\\\''/g"
  printf "'"
}

print_kv() {
  local key="$1"
  local value="${2:-}"

  value="${value//$'\n'/ }"
  printf '%s=%s\n' "${key}" "${value}"
}

pmset_setting_value() {
  local key="$1"

  pmset -g custom 2>/dev/null | awk -v key="${key}" '$1 == key { value = $2 } END { print value }'
}

systemsetup_toggle_value() {
  local getter="$1"

  systemsetup "${getter}" 2>/dev/null | awk -F': ' 'NF { value = $NF } END { print (tolower(value) == "on" ? "1" : "0") }'
}

firewall_global_value() {
  if "${SOCKETFILTERFW}" --getglobalstate 2>/dev/null | grep -qi "enabled"; then
    printf '1'
  else
    printf '0'
  fi
}

firewall_stealth_value() {
  if "${SOCKETFILTERFW}" --getstealthmode 2>/dev/null | grep -qi "enabled"; then
    printf '1'
  else
    printf '0'
  fi
}

remote_login_value() {
  if systemsetup -getremotelogin 2>/dev/null | grep -Fq "Remote Login: On"; then
    printf '1'
  else
    printf '0'
  fi
}

sshd_hardening_diagnostic() {
  local allowed_users="$1"
  local config
  local user
  local -a users=()

  if [[ -z "${allowed_users}" || ! -x "${SSHD_BIN}" ]]; then
    printf 'missing allowed users or sshd binary'
    return 1
  fi

  config="$("${SSHD_BIN}" -T 2>&1)" || {
    printf 'sshd -T failed: %s' "${config}"
    return 1
  }

  printf "%s\n" "${config}" | grep -Fxq "passwordauthentication no" || {
    printf 'missing effective config line: passwordauthentication no'
    return 1
  }
  printf "%s\n" "${config}" | grep -Fxq "kbdinteractiveauthentication no" || {
    printf 'missing effective config line: kbdinteractiveauthentication no'
    return 1
  }
  printf "%s\n" "${config}" | grep -Fxq "permitrootlogin no" || {
    printf 'missing effective config line: permitrootlogin no'
    return 1
  }
  printf "%s\n" "${config}" | grep -Fxq "pubkeyauthentication yes" || {
    printf 'missing effective config line: pubkeyauthentication yes'
    return 1
  }

  IFS=' ' read -r -a users <<< "${allowed_users}"
  for user in "${users[@]}"; do
    if [[ -z "${user}" ]]; then
      continue
    fi

    printf "%s\n" "${config}" | grep -Fxq "allowusers ${user}" || {
      printf 'missing effective config line: allowusers %s' "${user}"
      return 1
    }
  done

  return 0
}

sshd_hardened_value() {
  local allowed_users="$1"
  local attempt
  local diagnostic=""
  local max_attempts="3"

  SSH_HARDENING_DIAGNOSTIC=""

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if diagnostic="$(sshd_hardening_diagnostic "${allowed_users}")"; then
      printf '1'
      return 0
    fi

    SSH_HARDENING_DIAGNOSTIC="${diagnostic} (attempt ${attempt}/${max_attempts})"
    if [[ "${attempt}" -lt "${max_attempts}" ]]; then
      sleep 1
    fi
  done

  printf '0'
}

path_group_rwx_value() {
  local path="$1"
  local mode

  mode="$(stat -f "%Lp" "${path}" 2>/dev/null || true)"
  if [[ "${mode}" =~ ^[0-7]+$ ]] && (( (8#${mode} & 8#070) == 8#070 )); then
    printf '1'
  else
    printf '0'
  fi
}

path_owner_group_mode_value() {
  local expected_group="$3"
  local expected_mode="$4"
  local expected_owner="$2"
  local path="$1"
  local value=""

  value="$(stat -f "%Su:%Sg:%Lp" "${path}" 2>/dev/null || true)"
  if [[ "${value}" == "${expected_owner}:${expected_group}:${expected_mode}" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

path_owner_group_without_mode_bits_value() {
  local expected_group="$3"
  local expected_owner="$2"
  local forbidden_mode="$4"
  local mode
  local owner_group
  local path="$1"

  owner_group="$(stat -f "%Su:%Sg" "${path}" 2>/dev/null || true)"
  mode="$(stat -f "%Lp" "${path}" 2>/dev/null || true)"
  if [[ "${owner_group}" == "${expected_owner}:${expected_group}" && "${mode}" =~ ^[0-7]+$ ]] &&
    (( (8#${mode} & 8#${forbidden_mode}) == 0 )); then
    printf '1'
  else
    printf '0'
  fi
}

group_user_member_value() {
  local group="$1"
  local user="$2"

  if [[ -z "${group}" || -z "${user}" ]]; then
    printf '0'
    return 0
  fi

  if dscl . -read "/Groups/${group}" GroupMembership 2>/dev/null | awk -v expected="${user}" '
    $1 == "GroupMembership:" {
      for (i = 2; i <= NF; i++) {
        if ($i == expected) {
          found = 1
        }
      }
      next
    }
    $1 == expected {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  '; then
    printf '1'
  else
    printf '0'
  fi
}

group_exists_value() {
  if [[ -n "$1" ]] && dscl . -read "/Groups/$1" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

user_exists_value() {
  if [[ -n "$1" ]] && id -u "$1" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

user_home_dir_value() {
  local user="$1"

  dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | awk '/NFSHomeDirectory:/ {print $2; exit}'
}

launchd_job_loaded_value() {
  local domain="$1"
  local label="$2"

  if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

launchd_job_running_value() {
  local domain="$1"
  local label="$2"

  if launchctl print "${domain}/${label}" 2>/dev/null | grep -Eq '^[[:space:]]*state = running$'; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_finalizer_state_value() {
  local openclaw_home="$1"
  local state_file="${openclaw_home}/.agentbox/openclaw-gateway-finalizer-state"

  awk -F= '$1 == "status" {print $2; exit}' "${state_file}" 2>/dev/null || true
}

openclaw_gateway_dotenv_has_value() {
  local expected
  local key="$2"
  local path="$1"
  local value="$3"

  expected="${key}=$(dotenv_double_quote "${value}")"
  /usr/bin/grep -Fqx -- "${expected}" "${path}" 2>/dev/null
}

openclaw_gateway_service_env_has_value() {
  local expected
  local key="$2"
  local path="$1"
  local value="$3"

  expected="export ${key}=$(shell_single_quote "${value}")"
  /usr/bin/grep -Fqx -- "${expected}" "${path}" 2>/dev/null
}

openclaw_gateway_agentbox_managed_value() {
  local dotenv_path="$1/.openclaw/.env"
  local service_env_path="$1/.openclaw/service-env/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}.env"

  if openclaw_gateway_dotenv_has_value "${dotenv_path}" AGENTBOX_MANAGED 1 &&
    openclaw_gateway_dotenv_has_value "${dotenv_path}" AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}"; then
    printf '1'
    return 0
  fi
  if openclaw_gateway_service_env_has_value "${service_env_path}" AGENTBOX_MANAGED 1 &&
    openclaw_gateway_service_env_has_value "${service_env_path}" AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}"; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_gateway_mdns_hostname_ok_value() {
  local home="$1"
  local native_installed="$2"
  local path

  if [[ "${native_installed}" == "1" ]]; then
    path="${home}/.openclaw/service-env/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}.env"
    if openclaw_gateway_dotenv_has_value "${home}/.openclaw/.env" OPENCLAW_MDNS_HOSTNAME "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}" &&
      openclaw_gateway_service_env_has_value "${path}" OPENCLAW_MDNS_HOSTNAME "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}"; then
      printf '1'
    else
      printf '0'
    fi
    return 0
  fi

  path="${home}/.openclaw/.env"
  if openclaw_gateway_dotenv_has_value "${path}" OPENCLAW_MDNS_HOSTNAME "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}"; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_gateway_agent_environment_ok_value() {
  local home="$1"
  local native_installed="$2"
  local health_command="/opt/tanaab/agentbox/bin/health.sh --report"
  local path

  if [[ "${native_installed}" == "1" ]]; then
    path="${home}/.openclaw/service-env/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}.env"
    if openclaw_gateway_dotenv_has_value "${home}/.openclaw/.env" AGENTBOX_MANAGED 1 &&
      openclaw_gateway_dotenv_has_value "${home}/.openclaw/.env" AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}" &&
      openclaw_gateway_dotenv_has_value "${home}/.openclaw/.env" AGENTBOX_VERSION "${AGENTBOX_HEALTH_AGENTBOX_VERSION}" &&
      openclaw_gateway_dotenv_has_value "${home}/.openclaw/.env" AGENTBOX_HEALTH_COMMAND "${health_command}" &&
      openclaw_gateway_service_env_has_value "${path}" AGENTBOX_MANAGED 1 &&
      openclaw_gateway_service_env_has_value "${path}" AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}" &&
      openclaw_gateway_service_env_has_value "${path}" AGENTBOX_VERSION "${AGENTBOX_HEALTH_AGENTBOX_VERSION}" &&
      openclaw_gateway_service_env_has_value "${path}" AGENTBOX_HEALTH_COMMAND "${health_command}"; then
      printf '1'
    else
      printf '0'
    fi
    return 0
  fi

  path="${home}/.openclaw/.env"
  if openclaw_gateway_dotenv_has_value "${path}" AGENTBOX_MANAGED 1 &&
    openclaw_gateway_dotenv_has_value "${path}" AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}" &&
    openclaw_gateway_dotenv_has_value "${path}" AGENTBOX_VERSION "${AGENTBOX_HEALTH_AGENTBOX_VERSION}" &&
    openclaw_gateway_dotenv_has_value "${path}" AGENTBOX_HEALTH_COMMAND "${health_command}"; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_expected_port_ownership_ok_value() {
  local owner
  local pid
  local pids

  if [[ -z "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT}" ]]; then
    printf '0'
    return 0
  fi

  pids="$(/usr/sbin/lsof -nP -iTCP:"${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT}" -sTCP:LISTEN -t 2>/dev/null | sort -u || true)"
  if [[ -z "${pids}" ]]; then
    printf '0'
    return 0
  fi

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    owner="$(ps -o user= -p "${pid}" 2>/dev/null | awk '{$1=$1; print}')"
    if [[ "${owner}" != "${AGENTBOX_HEALTH_OPENCLAW_USER}" ]]; then
      printf '0'
      return 0
    fi
  done <<< "${pids}"
  printf '1'
}

filevault_enabled_value() {
  case "$(filevault_status)" in
    "FileVault is On."*) printf '1' ;;
    "FileVault is Off."*) printf '0' ;;
    *) printf 'unknown' ;;
  esac
}

openclaw_admin_app_attach_only_ok_value() {
  local admin_group=""
  local admin_home=""

  admin_home="$(user_home_dir_value "${AGENTBOX_HEALTH_ADMIN_USER}")"
  admin_group="$(id -gn "${AGENTBOX_HEALTH_ADMIN_USER}" 2>/dev/null || true)"
  if [[ -n "${admin_home}" && -n "${admin_group}" ]] &&
    [[ "$(path_owner_group_mode_value "${admin_home}/.openclaw" "${AGENTBOX_HEALTH_ADMIN_USER}" "${admin_group}" 700)" == "1" ]] &&
    [[ "$(path_owner_group_mode_value "${admin_home}/${OPENCLAW_DISABLE_LAUNCH_AGENT_MARKER}" "${AGENTBOX_HEALTH_ADMIN_USER}" "${admin_group}" 600)" == "1" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_admin_app_gateway_config_expected_value() {
  local jq_bin="${AGENTBOX_HEALTH_BREW_PREFIX}/bin/jq"
  local openclaw_home=""
  local runner_config=""

  openclaw_home="$(user_home_dir_value "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
  runner_config="${openclaw_home}/.openclaw/openclaw.json"
  if [[ ! -x "${jq_bin}" || ! -f "${runner_config}" ]]; then
    printf '1'
    return 0
  fi

  if "${jq_bin}" -e '.gateway.auth.token | select(type == "string" and length > 0 and (startswith("$") | not) and . != "__OPENCLAW_REDACTED__")' "${runner_config}" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_admin_app_gateway_config_ok_value() {
  local admin_config=""
  local admin_group=""
  local admin_home=""
  local admin_token_json=""
  local admin_token_hash=""
  local jq_bin="${AGENTBOX_HEALTH_BREW_PREFIX}/bin/jq"
  local openclaw_home=""
  local runner_config=""
  local runner_token_json=""
  local runner_token_hash=""

  admin_home="$(user_home_dir_value "${AGENTBOX_HEALTH_ADMIN_USER}")"
  admin_group="$(id -gn "${AGENTBOX_HEALTH_ADMIN_USER}" 2>/dev/null || true)"
  openclaw_home="$(user_home_dir_value "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
  admin_config="${admin_home}/.openclaw/openclaw.json"
  runner_config="${openclaw_home}/.openclaw/openclaw.json"

  # shellcheck disable=SC2016
  if [[ ! -x "${jq_bin}" || -z "${admin_home}" || -z "${admin_group}" || -z "${openclaw_home}" ]] ||
    [[ "$(path_owner_group_mode_value "${admin_config}" "${AGENTBOX_HEALTH_ADMIN_USER}" "${admin_group}" 600)" != "1" ]] ||
    ! "${jq_bin}" -e --argjson gateway_port "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT}" '
      .gateway.mode == "local"
      and .gateway.port == $gateway_port
      and .gateway.auth.mode == "token"
      and (.gateway.auth.token | type == "string" and length > 0)
    ' "${admin_config}" >/dev/null 2>&1; then
    printf '0'
    return 0
  fi

  runner_token_json="$("${jq_bin}" -ce '.gateway.auth.token' "${runner_config}" 2>/dev/null || true)"
  admin_token_json="$("${jq_bin}" -ce '.gateway.auth.token' "${admin_config}" 2>/dev/null || true)"
  if [[ -n "${runner_token_json}" && -n "${admin_token_json}" ]]; then
    runner_token_hash="$(printf '%s' "${runner_token_json}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
    admin_token_hash="$(printf '%s' "${admin_token_json}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  fi
  if [[ -n "${runner_token_hash}" && "${runner_token_hash}" == "${admin_token_hash}" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_gateway_tailscale_auth_ok_value() {
  local jq_bin="${AGENTBOX_HEALTH_BREW_PREFIX}/bin/jq"
  local openclaw_home=""
  local runner_config=""

  openclaw_home="$(user_home_dir_value "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
  runner_config="${openclaw_home}/.openclaw/openclaw.json"
  if [[ -x "${jq_bin}" ]] &&
    "${jq_bin}" -e '.gateway.auth.allowTailscale == true' "${runner_config}" >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

autologin_user_value() {
  /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
}

nested_group_value() {
  local parent_group="$1"
  local child_group="$2"
  local child_group_guid

  child_group_guid="$(dscl . -read "/Groups/${child_group}" GeneratedUID 2>/dev/null | awk '$1 == "GeneratedUID:" { print $2; exit }')"
  if [[ -z "${child_group_guid}" ]]; then
    printf '0'
    return 0
  fi

  if dscl . -read "/Groups/${parent_group}" NestedGroups 2>/dev/null | awk -v expected="${child_group_guid}" '
    $1 == "NestedGroups:" {
      for (i = 2; i <= NF; i++) {
        if ($i == expected) {
          found = 1
        }
      }
      next
    }
    $1 == expected {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  '; then
    printf '1'
  else
    printf '0'
  fi
}

root_disk_available_kb() {
  df -Pk / 2>/dev/null | awk 'NR == 2 { print $4; found = 1 } END { if (!found) print "unknown" }'
}

gatekeeper_status() {
  if command -v spctl >/dev/null 2>&1; then
    spctl --status 2>/dev/null || true
  else
    printf 'unavailable'
  fi
}

filevault_status() {
  local status

  if command -v fdesetup >/dev/null 2>&1; then
    if status="$(fdesetup status 2>/dev/null)" && [[ -n "${status}" ]]; then
      printf '%s' "${status}"
      return 0
    fi
  fi
  printf 'unavailable'
}

path_file_contains_value() {
  local file="$1"
  local value="$2"

  if [[ -f "${file}" ]] && grep -Fxq -- "${value}" "${file}" 2>/dev/null; then
    printf '1'
  else
    printf '0'
  fi
}

executable_ok_value() {
  if [[ -x "$1" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_gateway_status_ready() {
  local openclaw_bin=""
  local openclaw_home=""
  local path_value=""

  if [[ -z "${AGENTBOX_HEALTH_OPENCLAW_USER}" ||
    -z "${AGENTBOX_HEALTH_BREW_PREFIX}" ||
    -z "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT}" ]]; then
    return 1
  fi

  openclaw_bin="${AGENTBOX_HEALTH_BREW_PREFIX}/bin/openclaw"
  if [[ ! -x "${openclaw_bin}" ]]; then
    return 1
  fi

  openclaw_home="$(user_home_dir_value "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
  if [[ -z "${openclaw_home}" || ! -d "${openclaw_home}" ]]; then
    return 1
  fi

  path_value="${AGENTBOX_HEALTH_BREW_PREFIX}/bin:${AGENTBOX_HEALTH_BREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
  sudo -u "${AGENTBOX_HEALTH_OPENCLAW_USER}" env \
    "HOME=${openclaw_home}" \
    "USER=${AGENTBOX_HEALTH_OPENCLAW_USER}" \
    "LOGNAME=${AGENTBOX_HEALTH_OPENCLAW_USER}" \
    "PATH=${path_value}" \
    "OPENCLAW_HOME=${openclaw_home}" \
    "OPENCLAW_STATE_DIR=${openclaw_home}/.openclaw" \
    "${openclaw_bin}" gateway status --require-rpc --timeout 10000 >/dev/null 2>&1
}

openclaw_gateway_status_ok_value() {
  if openclaw_gateway_status_ready; then
    printf '1'
  else
    printf '0'
  fi
}

openclaw_gateway_tailscale_serve_route_ok_value() {
  local port="$1"
  local status

  if [[ -z "${port}" ]] || ! command -v tailscale >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf '0'
    return 0
  fi

  status="$(tailscale serve status --json 2>/dev/null || true)"
  if [[ -z "${status}" ]]; then
    printf '0'
    return 0
  fi

  if printf "%s" "${status}" | jq -e --arg port "${port}" '
    any((.Web // {}) | to_entries[]?;
      (.key | endswith(":443"))
      and ((.value.Handlers["/"].Proxy // "")
        | test("^https?://(127[.]0[.]0[.]1|localhost|\\[::1\\]):" + $port + "$"))
    )
  ' >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

tailscale_magicdns_enabled_value() {
  local status_json="$1"

  if printf "%s" "${status_json}" | jq -e '.CurrentTailnet.MagicDNSEnabled == true' >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

tailscale_https_certificates_enabled_value() {
  local status_json="$1"

  if printf "%s" "${status_json}" | jq -e '((.CertDomains // []) | length) > 0' >/dev/null 2>&1; then
    printf '1'
  else
    printf '0'
  fi
}

tailscale_magicdns_suffix_value() {
  local status_json="$1"

  printf "%s" "${status_json}" | jq -r '.CurrentTailnet.MagicDNSSuffix // ""' 2>/dev/null | sed 's/[.]$//'
}

tailscale_magicdns_suffix_valid() {
  local suffix="$1"

  [[ -n "${suffix}" &&
    "${suffix}" != *..* &&
    "${suffix}" =~ ^[A-Za-z0-9][-A-Za-z0-9.]*[A-Za-z0-9]$ ]]
}

tailscale_magicdns_resolver_path_value() {
  local suffix="$1"

  if tailscale_magicdns_suffix_valid "${suffix}"; then
    printf "/etc/resolver/%s" "${suffix}"
  fi
  return 0
}

tailscale_magicdns_resolver_ok_value() {
  local status_json="$1"
  local resolver_path=""
  local suffix=""

  if [[ -z "${status_json}" ]] || ! command -v jq >/dev/null 2>&1; then
    printf '0'
    return 0
  fi

  suffix="$(tailscale_magicdns_suffix_value "${status_json}" || true)"
  resolver_path="$(tailscale_magicdns_resolver_path_value "${suffix}")"
  if [[ -n "${resolver_path}" &&
    -f "${resolver_path}" ]] &&
    grep -Eq '^[[:space:]]*nameserver[[:space:]]+100[.]100[.]100[.]100([[:space:]]|$)' "${resolver_path}" 2>/dev/null; then
    printf '1'
  else
    printf '0'
  fi
}

print_brewgroup() {
  if [[ "${STATE_LOADED}" != "1" ]]; then
    printf 'off\n'
    return 1
  fi

  if [[ "${AGENTBOX_HEALTH_BREWGROUP_ENABLED}" == "1" && -n "${AGENTBOX_HEALTH_BREWGROUP}" ]]; then
    printf '%s\n' "${AGENTBOX_HEALTH_BREWGROUP}"
    return 0
  fi

  printf 'off\n'
}

generate_report() {
  local failures="0"
  local admin_uid=""
  local computer_name=""
  local host_name=""
  local local_host_name=""
  local sleep_value=""
  local disksleep_value=""
  local displaysleep_value=""
  local autorestart_value=""
  local autorestart_ok="skipped"
  local power_ok="0"
  local network_time_ok=""
  local restart_freeze_ok=""
  local firewall_global_enabled=""
  local firewall_stealth_enabled=""
  local remote_login_ok=""
  local ssh_access_admin_user_ok="skipped"
  local ssh_access_group_exists_ok="0"
  local ssh_access_openclaw_user_ok="skipped"
  local ssh_hardening_ok="skipped"
  local ssh_allowed_users=""
  local brew_prefix_group=""
  local brew_prefix_group_ok="skipped"
  local brew_prefix_group_rwx_ok="skipped"
  local brew_prefix_ok="skipped"
  local brewgroup_admin_user_ok="skipped"
  local brewgroup_openclaw_user_ok="skipped"
  local openclaw_autologin_ok="skipped"
  local openclaw_autologin_user=""
  local openclaw_home=""
  local openclaw_user_exists_ok="0"
  local openclaw_user_home_ok="0"
  local openclaw_user_non_admin_ok="0"
  local openclaw_user_ok="0"
  local homebrew_bin_path=""
  local homebrew_sbin_path=""
  local homebrew_login_path_bin_ok="0"
  local homebrew_login_path_file_ok="0"
  local homebrew_login_path_sbin_ok="0"
  local node_cli_path=""
  local node_cli_ok="0"
  local openclaw_cli_path=""
  local openclaw_cli_ok="0"
  local openclaw_gateway_label="${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_LABEL:-${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}}"
  local openclaw_gateway_activation_ok="0"
  local openclaw_gateway_state="not_configured"
  local openclaw_gui_domain_present="0"
  local openclaw_native_launchagent_installed_ok="0"
  local openclaw_native_launchagent_loaded_ok="0"
  local openclaw_native_launchagent_running_ok="0"
  local openclaw_gateway_agentbox_managed="0"
  local openclaw_gateway_mdns_hostname_ok="skipped"
  local openclaw_gateway_agent_environment_ok="skipped"
  local openclaw_gateway_log_permissions_ok="skipped"
  local openclaw_finalizer_installed="0"
  local openclaw_finalizer_permissions_ok="skipped"
  local openclaw_finalizer_state=""
  local openclaw_duplicate_admin_gateway_detected="0"
  local openclaw_expected_port_ownership_ok="0"
  local openclaw_unattended_reboot_ready="0"
  local openclaw_filevault_enabled="0"
  local openclaw_uid=""
  local openclaw_domain=""
  local openclaw_primary_group=""
  local openclaw_native_plist=""
  local openclaw_admin_native_plist=""
  local openclaw_finalizer_plist=""
  local openclaw_finalizer_executable=""
  local openclaw_finalizer_state_dir=""
  local openclaw_finalizer_state_path=""
  local openclaw_finalizer_log_dir=""
  local openclaw_gateway_log_dir=""
  local openclaw_gateway_log_path=""
  local openclaw_gateway_tailscale_auth_ok="skipped"
  local openclaw_gateway_status_ok="0"
  local openclaw_gateway_tailscale_serve_route_ok="skipped"
  local openclaw_gateway_ok="0"
  local openclaw_admin_app_attach_only_ok="skipped"
  local openclaw_admin_app_gateway_config_expected="0"
  local openclaw_admin_app_gateway_config_ok="skipped"
  local ripgrep_path=""
  local ripgrep_ok="0"
  local trusted_brewgroup_nested_ok="skipped"
  local health_launchd_loaded_ok="0"
  local tailscaled_launchd_loaded_ok="skipped"
  local tailscaled_launchd_running_ok="skipped"
  local tailscaled_homebrew_launchd_absent_ok="skipped"
  local tailscaled_homebrew_user_launchd_absent_ok="skipped"
  local tailscaled_official_launchd_absent_ok="skipped"
  local tailscaled_state_file_ok="skipped"
  local tailscale_backend_state=""
  local tailscale_hostname=""
  local tailscale_https_certificates_enabled="skipped"
  local tailscale_ip=""
  local tailscale_magicdns_enabled="skipped"
  local tailscale_magicdns_resolver_ok="skipped"
  local tailscale_magicdns_resolver_path="skipped"
  local tailscale_magicdns_suffix="skipped"
  local tailscale_firewall_warning="skipped"
  local tailscale_operator_ok="skipped"
  local tailscale_operator_user=""
  local tailscale_ok="skipped"
  local tailscale_status_json=""

  mark_required() {
    local key="$1"
    local value="$2"

    print_kv "${key}" "${value}"
    if [[ "${value}" != "1" ]]; then
      failures=$((failures + 1))
    fi
  }

  computer_name="$(scutil --get ComputerName 2>/dev/null || true)"
  host_name="$(scutil --get HostName 2>/dev/null || true)"
  local_host_name="$(scutil --get LocalHostName 2>/dev/null || true)"
  sleep_value="$(pmset_setting_value sleep)"
  disksleep_value="$(pmset_setting_value disksleep)"
  displaysleep_value="$(pmset_setting_value displaysleep)"
  autorestart_value="$(pmset_setting_value autorestart)"
  network_time_ok="$(systemsetup_toggle_value -getusingnetworktime)"
  restart_freeze_ok="$(systemsetup_toggle_value -getrestartfreeze)"
  firewall_global_enabled="$(firewall_global_value)"
  firewall_stealth_enabled="$(firewall_stealth_value)"
  remote_login_ok="$(remote_login_value)"
  admin_uid="$(id -u "${AGENTBOX_HEALTH_ADMIN_USER}" 2>/dev/null || true)"
  ssh_allowed_users="${AGENTBOX_HEALTH_SSH_ALLOWED_USERS:-${AGENTBOX_HEALTH_ADMIN_USER}}"
  openclaw_user_exists_ok="$(user_exists_value "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
  openclaw_home="$(user_home_dir_value "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
  openclaw_autologin_user="$(autologin_user_value)"

  if [[ "${openclaw_user_exists_ok}" == "1" && -n "${openclaw_home}" && -d "${openclaw_home}" ]]; then
    openclaw_user_home_ok="1"
  fi

  if [[ "${openclaw_user_exists_ok}" == "1" &&
    "$(group_user_member_value admin "${AGENTBOX_HEALTH_OPENCLAW_USER}")" != "1" &&
    "${AGENTBOX_HEALTH_OPENCLAW_USER}" != "${AGENTBOX_HEALTH_ADMIN_USER}" &&
    "${AGENTBOX_HEALTH_OPENCLAW_USER}" != "root" ]]; then
    openclaw_user_non_admin_ok="1"
  fi

  if [[ "${openclaw_user_exists_ok}" == "1" &&
    "${openclaw_user_home_ok}" == "1" &&
    "${openclaw_user_non_admin_ok}" == "1" ]]; then
    openclaw_user_ok="1"
  fi

  if [[ -z "${autorestart_value}" && "${AGENTBOX_HEALTH_MANAGED_MACOS_RUNNER}" == "1" ]]; then
    autorestart_ok="skipped"
  elif [[ "${autorestart_value}" == "1" ]]; then
    autorestart_ok="1"
  else
    autorestart_ok="0"
  fi

  if [[ "${sleep_value}" == "0" &&
    "${disksleep_value}" == "0" &&
    "${displaysleep_value}" == "0" &&
    "${autorestart_ok}" != "0" ]]; then
    power_ok="1"
  fi

  if launchctl print "system/${HEALTH_LABEL}" >/dev/null 2>&1; then
    health_launchd_loaded_ok="1"
  fi

  print_kv timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  print_kv agentbox_version "${AGENTBOX_HEALTH_AGENTBOX_VERSION}"
  print_kv managed_macos_runner "${AGENTBOX_HEALTH_MANAGED_MACOS_RUNNER}"
  print_kv expected_hostname "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}"
  print_kv computer_name "${computer_name}"
  print_kv host_name "${host_name}"
  print_kv local_host_name "${local_host_name}"

  if [[ -n "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}" &&
    "${computer_name}" == "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}" &&
    "${host_name}" == "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}" &&
    "${local_host_name}" == "${AGENTBOX_HEALTH_EXPECTED_HOSTNAME}" ]]; then
    mark_required macos_identity_ok 1
  else
    mark_required macos_identity_ok 0
  fi

  print_kv sleep "${sleep_value}"
  print_kv disksleep "${disksleep_value}"
  print_kv displaysleep "${displaysleep_value}"
  print_kv autorestart "${autorestart_value}"
  print_kv autorestart_ok "${autorestart_ok}"
  mark_required headless_power_ok "${power_ok}"
  mark_required network_time_ok "${network_time_ok}"
  mark_required restart_freeze_ok "${restart_freeze_ok}"
  print_kv firewall_global_enabled "${firewall_global_enabled}"
  print_kv firewall_stealth_enabled "${firewall_stealth_enabled}"
  if [[ "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE}" == "serve" ]]; then
    tailscale_firewall_warning="0"
    if [[ "${firewall_global_enabled}" == "1" ]]; then
      tailscale_firewall_warning="1"
    fi
  fi
  print_kv tailscale_firewall_warning "${tailscale_firewall_warning}"
  mark_required remote_login_ok "${remote_login_ok}"

  print_kv ssh_hardening_expected "${AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED}"
  print_kv admin_user "${AGENTBOX_HEALTH_ADMIN_USER}"
  print_kv ssh_allowed_users "${ssh_allowed_users}"
  print_kv ssh_access_group "${SSH_ACCESS_GROUP}"
  ssh_access_group_exists_ok="$(group_exists_value "${SSH_ACCESS_GROUP}")"
  print_kv ssh_access_group_exists_ok "${ssh_access_group_exists_ok}"
  if [[ "${ssh_access_group_exists_ok}" == "1" ]]; then
    ssh_access_admin_user_ok="$(group_user_member_value "${SSH_ACCESS_GROUP}" "${AGENTBOX_HEALTH_ADMIN_USER}")"
    ssh_access_openclaw_user_ok="$(group_user_member_value "${SSH_ACCESS_GROUP}" "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
    mark_required ssh_access_admin_user_ok "${ssh_access_admin_user_ok}"
    mark_required ssh_access_openclaw_user_ok "${ssh_access_openclaw_user_ok}"
  else
    print_kv ssh_access_admin_user_ok "${ssh_access_admin_user_ok}"
    print_kv ssh_access_openclaw_user_ok "${ssh_access_openclaw_user_ok}"
  fi
  if [[ "${AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED}" == "1" ]]; then
    ssh_hardening_ok="$(sshd_hardened_value "${ssh_allowed_users}")"
    mark_required ssh_hardening_ok "${ssh_hardening_ok}"
    if [[ "${ssh_hardening_ok}" != "1" && -n "${SSH_HARDENING_DIAGNOSTIC}" ]]; then
      print_kv ssh_hardening_diagnostic "${SSH_HARDENING_DIAGNOSTIC}"
    fi
  else
    print_kv ssh_hardening_ok "${ssh_hardening_ok}"
  fi

  print_kv openclaw_user "${AGENTBOX_HEALTH_OPENCLAW_USER}"
  print_kv openclaw_full_name "${AGENTBOX_HEALTH_OPENCLAW_FULL_NAME}"
  print_kv openclaw_home "${openclaw_home}"
  mark_required openclaw_user_exists_ok "${openclaw_user_exists_ok}"
  mark_required openclaw_user_home_ok "${openclaw_user_home_ok}"
  mark_required openclaw_user_non_admin_ok "${openclaw_user_non_admin_ok}"
  mark_required openclaw_user_ok "${openclaw_user_ok}"
  print_kv openclaw_autologin_expected "${AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED}"
  if [[ "${AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED}" == "1" ]]; then
    print_kv openclaw_autologin_configured_user "${AGENTBOX_HEALTH_OPENCLAW_USER}"
  else
    print_kv openclaw_autologin_configured_user off
  fi
  print_kv openclaw_autologin_user "${openclaw_autologin_user}"
  if [[ "${AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED}" == "1" ]]; then
    if [[ -n "${AGENTBOX_HEALTH_OPENCLAW_USER}" && "${openclaw_autologin_user}" == "${AGENTBOX_HEALTH_OPENCLAW_USER}" ]]; then
      openclaw_autologin_ok="1"
    else
      openclaw_autologin_ok="0"
    fi
    mark_required openclaw_autologin_ok "${openclaw_autologin_ok}"
  else
    print_kv openclaw_autologin_ok "${openclaw_autologin_ok}"
  fi

  print_kv brewgroup_enabled "${AGENTBOX_HEALTH_BREWGROUP_ENABLED}"
  print_kv brewgroup_expected "${AGENTBOX_HEALTH_BREWGROUP}"
  if [[ "${AGENTBOX_HEALTH_BREWGROUP_ENABLED}" == "1" ]]; then
    brewgroup_admin_user_ok="$(group_user_member_value "${AGENTBOX_HEALTH_BREWGROUP}" "${AGENTBOX_HEALTH_ADMIN_USER}")"
    brewgroup_openclaw_user_ok="$(group_user_member_value "${AGENTBOX_HEALTH_BREWGROUP}" "${AGENTBOX_HEALTH_OPENCLAW_USER}")"
    mark_required brewgroup_admin_user_ok "${brewgroup_admin_user_ok}"
    mark_required brewgroup_openclaw_user_ok "${brewgroup_openclaw_user_ok}"
  else
    print_kv brewgroup_admin_user_ok "${brewgroup_admin_user_ok}"
    print_kv brewgroup_openclaw_user_ok "${brewgroup_openclaw_user_ok}"
  fi
  print_kv trusted_brewgroup_enabled "${AGENTBOX_HEALTH_TRUSTED_BREWGROUP_ENABLED}"
  print_kv trusted_brewgroup_expected "${AGENTBOX_HEALTH_TRUSTED_BREWGROUP}"
  if [[ "${AGENTBOX_HEALTH_TRUSTED_BREWGROUP_ENABLED}" == "1" ]]; then
    trusted_brewgroup_nested_ok="$(nested_group_value "${AGENTBOX_HEALTH_BREWGROUP}" "${AGENTBOX_HEALTH_TRUSTED_BREWGROUP}")"
    mark_required trusted_brewgroup_nested_ok "${trusted_brewgroup_nested_ok}"
  else
    print_kv trusted_brewgroup_nested_ok "${trusted_brewgroup_nested_ok}"
  fi
  print_kv brew_prefix "${AGENTBOX_HEALTH_BREW_PREFIX}"
  if [[ "${AGENTBOX_HEALTH_BREWGROUP_ENABLED}" == "1" ]]; then
    brew_prefix_group_ok="0"
    brew_prefix_group_rwx_ok="0"
    brew_prefix_ok="0"

    if [[ -d "${AGENTBOX_HEALTH_BREW_PREFIX}" ]]; then
      brew_prefix_group="$(stat -f "%Sg" "${AGENTBOX_HEALTH_BREW_PREFIX}" 2>/dev/null || true)"
      brew_prefix_group_rwx_ok="$(path_group_rwx_value "${AGENTBOX_HEALTH_BREW_PREFIX}")"
      if [[ "${brew_prefix_group}" == "${AGENTBOX_HEALTH_BREWGROUP}" ]]; then
        brew_prefix_group_ok="1"
      fi
    fi

    if [[ "${brew_prefix_group_ok}" == "1" && "${brew_prefix_group_rwx_ok}" == "1" ]]; then
      brew_prefix_ok="1"
    fi

    print_kv brew_prefix_group "${brew_prefix_group}"
    mark_required brew_prefix_group_ok "${brew_prefix_group_ok}"
    mark_required brew_prefix_group_rwx_ok "${brew_prefix_group_rwx_ok}"
    mark_required brew_prefix_ok "${brew_prefix_ok}"
  else
    print_kv brew_prefix_group "${brew_prefix_group}"
    print_kv brew_prefix_group_ok "${brew_prefix_group_ok}"
    print_kv brew_prefix_group_rwx_ok "${brew_prefix_group_rwx_ok}"
    print_kv brew_prefix_ok "${brew_prefix_ok}"
  fi

  print_kv homebrew_login_path_file "${AGENTBOX_HEALTH_HOMEBREW_PATHS_FILE}"
  if [[ -n "${AGENTBOX_HEALTH_BREW_PREFIX}" ]]; then
    homebrew_bin_path="${AGENTBOX_HEALTH_BREW_PREFIX}/bin"
    homebrew_sbin_path="${AGENTBOX_HEALTH_BREW_PREFIX}/sbin"
    homebrew_login_path_bin_ok="$(path_file_contains_value "${AGENTBOX_HEALTH_HOMEBREW_PATHS_FILE}" "${homebrew_bin_path}")"
    homebrew_login_path_sbin_ok="$(path_file_contains_value "${AGENTBOX_HEALTH_HOMEBREW_PATHS_FILE}" "${homebrew_sbin_path}")"

    if [[ "${homebrew_login_path_bin_ok}" == "1" && "${homebrew_login_path_sbin_ok}" == "1" ]]; then
      homebrew_login_path_file_ok="1"
    fi

    openclaw_cli_path="${homebrew_bin_path}/openclaw"
    node_cli_path="${homebrew_bin_path}/node"
    ripgrep_path="${homebrew_bin_path}/rg"
    openclaw_cli_ok="$(executable_ok_value "${openclaw_cli_path}")"
    node_cli_ok="$(executable_ok_value "${node_cli_path}")"
    ripgrep_ok="$(executable_ok_value "${ripgrep_path}")"
  fi
  print_kv homebrew_login_path_bin "${homebrew_bin_path}"
  print_kv homebrew_login_path_sbin "${homebrew_sbin_path}"
  mark_required homebrew_login_path_bin_ok "${homebrew_login_path_bin_ok}"
  mark_required homebrew_login_path_sbin_ok "${homebrew_login_path_sbin_ok}"
  mark_required homebrew_login_path_file_ok "${homebrew_login_path_file_ok}"
  print_kv openclaw_cli_path "${openclaw_cli_path}"
  mark_required openclaw_cli_ok "${openclaw_cli_ok}"
  print_kv node_cli_path "${node_cli_path}"
  mark_required node_cli_ok "${node_cli_ok}"
  print_kv ripgrep_path "${ripgrep_path}"
  mark_required ripgrep_ok "${ripgrep_ok}"

  openclaw_uid="$(id -u "${AGENTBOX_HEALTH_OPENCLAW_USER}" 2>/dev/null || true)"
  openclaw_primary_group="$(id -gn "${AGENTBOX_HEALTH_OPENCLAW_USER}" 2>/dev/null || true)"
  openclaw_domain="gui/${openclaw_uid}"
  openclaw_native_plist="${openclaw_home}/Library/LaunchAgents/${openclaw_gateway_label}.plist"
  openclaw_admin_native_plist="$(user_home_dir_value "${AGENTBOX_HEALTH_ADMIN_USER}")/Library/LaunchAgents/${openclaw_gateway_label}.plist"
  openclaw_finalizer_plist="${openclaw_home}/Library/LaunchAgents/${AGENTBOX_HEALTH_OPENCLAW_FINALIZER_LABEL}.plist"
  openclaw_finalizer_executable="${openclaw_home}/.local/libexec/agentbox-openclaw-finalize"
  openclaw_finalizer_state_dir="${openclaw_home}/.agentbox"
  openclaw_finalizer_state_path="${openclaw_finalizer_state_dir}/openclaw-gateway-finalizer-state"
  openclaw_finalizer_log_dir="${openclaw_home}/Library/Logs/agentbox"
  openclaw_gateway_log_dir="${openclaw_home}/Library/Logs/openclaw"
  openclaw_gateway_log_path="${openclaw_gateway_log_dir}/gateway.log"

  if [[ -n "${openclaw_uid}" ]]; then
    openclaw_gui_domain_present="$(launchd_job_loaded_value gui "${openclaw_uid}")"
    openclaw_native_launchagent_loaded_ok="$(launchd_job_loaded_value "${openclaw_domain}" "${openclaw_gateway_label}")"
    openclaw_native_launchagent_running_ok="$(launchd_job_running_value "${openclaw_domain}" "${openclaw_gateway_label}")"
  fi
  [[ -f "${openclaw_native_plist}" ]] && openclaw_native_launchagent_installed_ok="1"
  if [[ -f "${openclaw_finalizer_plist}" ]]; then
    openclaw_finalizer_installed="1"
  fi
  openclaw_finalizer_state="$(openclaw_finalizer_state_value "${openclaw_home}")"
  openclaw_gateway_agentbox_managed="$(openclaw_gateway_agentbox_managed_value "${openclaw_home}")"
  if [[ "${openclaw_gateway_agentbox_managed}" == "1" ]]; then
    openclaw_gateway_mdns_hostname_ok="$(openclaw_gateway_mdns_hostname_ok_value "${openclaw_home}" "${openclaw_native_launchagent_installed_ok}")"
    openclaw_gateway_agent_environment_ok="$(openclaw_gateway_agent_environment_ok_value "${openclaw_home}" "${openclaw_native_launchagent_installed_ok}")"
  fi
  if [[ "${openclaw_native_launchagent_installed_ok}" == "1" &&
    "${openclaw_gateway_agentbox_managed}" == "1" ]]; then
    if [[ "$(path_owner_group_without_mode_bits_value "${openclaw_gateway_log_dir}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 022)" == "1" ]] &&
      [[ "$(path_owner_group_mode_value "${openclaw_gateway_log_path}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 600)" == "1" ]]; then
      openclaw_gateway_log_permissions_ok="1"
    else
      openclaw_gateway_log_permissions_ok="0"
    fi
  fi
  if [[ -n "${openclaw_primary_group}" &&
    "$(path_owner_group_mode_value "${openclaw_finalizer_executable}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 700)" == "1" &&
    "$(path_owner_group_mode_value "${openclaw_finalizer_state_dir}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 700)" == "1" &&
    "$(path_owner_group_mode_value "${openclaw_finalizer_log_dir}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 700)" == "1" &&
    ( ! -e "${openclaw_finalizer_state_path}" || "$(path_owner_group_mode_value "${openclaw_finalizer_state_path}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 600)" == "1" ) &&
    ( "${openclaw_finalizer_installed}" != "1" || "$(path_owner_group_mode_value "${openclaw_finalizer_plist}" "${AGENTBOX_HEALTH_OPENCLAW_USER}" "${openclaw_primary_group}" 644)" == "1" ) ]]; then
    openclaw_finalizer_permissions_ok="1"
  elif [[ -e "${openclaw_finalizer_executable}" || -e "${openclaw_finalizer_state_dir}" || "${openclaw_finalizer_installed}" == "1" ]]; then
    openclaw_finalizer_permissions_ok="0"
  fi

  if [[ -n "${admin_uid}" ]] &&
    { [[ "$(launchd_job_loaded_value "gui/${admin_uid}" "${openclaw_gateway_label}")" == "1" ]] || [[ -e "${openclaw_admin_native_plist}" ]]; }; then
    openclaw_duplicate_admin_gateway_detected="1"
  fi

  openclaw_admin_app_attach_only_ok="$(openclaw_admin_app_attach_only_ok_value)"
  openclaw_admin_app_gateway_config_expected="$(openclaw_admin_app_gateway_config_expected_value)"
  if [[ "${openclaw_admin_app_gateway_config_expected}" == "1" ]]; then
    openclaw_admin_app_gateway_config_ok="$(openclaw_admin_app_gateway_config_ok_value)"
  fi
  if [[ "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE}" == "serve" ]]; then
    openclaw_gateway_tailscale_auth_ok="$(openclaw_gateway_tailscale_auth_ok_value)"
  fi
  openclaw_gateway_status_ok="$(openclaw_gateway_status_ok_value)"
  openclaw_expected_port_ownership_ok="$(openclaw_expected_port_ownership_ok_value)"
  openclaw_filevault_enabled="$(filevault_enabled_value)"
  if [[ "${AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED}" == "1" &&
    "${openclaw_autologin_ok}" == "1" && "${openclaw_filevault_enabled}" == "0" ]]; then
    openclaw_unattended_reboot_ready="1"
  fi

  if [[ "${openclaw_duplicate_admin_gateway_detected}" == "1" ]]; then
    openclaw_gateway_state="duplicate_gateway_detected"
  elif [[ "${openclaw_finalizer_state}" == "failed" ]]; then
    openclaw_gateway_state="failed"
  elif [[ "${openclaw_finalizer_state}" == "installing" ]]; then
    openclaw_gateway_state="installing"
  elif [[ "${openclaw_native_launchagent_installed_ok}" == "1" &&
    "${openclaw_native_launchagent_loaded_ok}" == "1" &&
    "${openclaw_native_launchagent_running_ok}" == "1" &&
    "${openclaw_gateway_status_ok}" == "1" &&
    "${openclaw_expected_port_ownership_ok}" == "1" &&
    "${openclaw_gateway_mdns_hostname_ok}" != "0" &&
    "${openclaw_gateway_agent_environment_ok}" != "0" &&
    ( "${openclaw_gateway_log_permissions_ok}" == "1" || "${openclaw_gateway_agentbox_managed}" == "0" ) &&
    "${openclaw_admin_app_attach_only_ok}" == "1" &&
    "${openclaw_admin_app_gateway_config_ok}" != "0" &&
    "${openclaw_gateway_tailscale_auth_ok}" != "0" ]]; then
    openclaw_gateway_state="healthy"
    openclaw_gateway_activation_ok="1"
    openclaw_gateway_ok="1"
  elif [[ "${openclaw_finalizer_installed}" == "1" && "${openclaw_finalizer_state}" == "pending_first_login" ]]; then
    openclaw_gateway_state="pending_first_login"
  elif [[ "${openclaw_finalizer_installed}" == "1" && "${openclaw_gui_domain_present}" == "0" ]]; then
    openclaw_gateway_state="pending_first_login"
  elif [[ "${openclaw_gui_domain_present}" == "0" && "${openclaw_native_launchagent_installed_ok}" == "1" ]]; then
    openclaw_gateway_state="gui_session_inactive"
  elif [[ -f "${openclaw_home}/.openclaw/openclaw.json" ]]; then
    openclaw_gateway_state="failed"
  fi

  print_kv openclaw_auth_choice "${AGENTBOX_HEALTH_OPENCLAW_AUTH_CHOICE}"
  print_kv openclaw_gateway_state "${openclaw_gateway_state}"
  print_kv openclaw_gateway_label "${openclaw_gateway_label}"
  print_kv openclaw_gateway_bind "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_BIND}"
  print_kv openclaw_gateway_tailscale_mode "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE}"
  print_kv openclaw_gateway_port "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT}"
  print_kv openclaw_filevault_enabled "${openclaw_filevault_enabled}"
  if [[ "${AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED}" == "1" ]]; then
    mark_required openclaw_unattended_reboot_ready "${openclaw_unattended_reboot_ready}"
  else
    print_kv openclaw_unattended_reboot_ready "${openclaw_unattended_reboot_ready}"
  fi
  print_kv openclaw_gui_domain_present "${openclaw_gui_domain_present}"
  print_kv openclaw_finalizer_installed "${openclaw_finalizer_installed}"
  print_kv openclaw_finalizer_state "${openclaw_finalizer_state:-none}"
  print_kv openclaw_finalizer_permissions_ok "${openclaw_finalizer_permissions_ok}"
  print_kv openclaw_native_launchagent_installed_ok "${openclaw_native_launchagent_installed_ok}"
  print_kv openclaw_native_launchagent_loaded_ok "${openclaw_native_launchagent_loaded_ok}"
  print_kv openclaw_native_launchagent_running_ok "${openclaw_native_launchagent_running_ok}"
  print_kv openclaw_gateway_agentbox_managed "${openclaw_gateway_agentbox_managed}"
  if [[ "${openclaw_gateway_agentbox_managed}" == "1" ]]; then
    mark_required openclaw_gateway_mdns_hostname_ok "${openclaw_gateway_mdns_hostname_ok}"
    mark_required openclaw_gateway_agent_environment_ok "${openclaw_gateway_agent_environment_ok}"
  else
    print_kv openclaw_gateway_mdns_hostname_ok "${openclaw_gateway_mdns_hostname_ok}"
    print_kv openclaw_gateway_agent_environment_ok "${openclaw_gateway_agent_environment_ok}"
  fi
  if [[ "${openclaw_native_launchagent_installed_ok}" == "1" &&
    "${openclaw_gateway_agentbox_managed}" == "1" ]]; then
    mark_required openclaw_gateway_log_permissions_ok "${openclaw_gateway_log_permissions_ok}"
  else
    print_kv openclaw_gateway_log_permissions_ok "${openclaw_gateway_log_permissions_ok}"
  fi
  print_kv openclaw_gateway_rpc_ok "${openclaw_gateway_status_ok}"
  print_kv openclaw_duplicate_admin_gateway_detected "${openclaw_duplicate_admin_gateway_detected}"
  print_kv openclaw_expected_port_ownership_ok "${openclaw_expected_port_ownership_ok}"
  print_kv openclaw_admin_app_attach_only_ok "${openclaw_admin_app_attach_only_ok}"
  print_kv openclaw_admin_app_gateway_config_expected "${openclaw_admin_app_gateway_config_expected}"
  print_kv openclaw_admin_app_gateway_config_ok "${openclaw_admin_app_gateway_config_ok}"
  print_kv openclaw_gateway_tailscale_auth_ok "${openclaw_gateway_tailscale_auth_ok}"
  print_kv openclaw_gateway_status_ok "${openclaw_gateway_status_ok}"
  mark_required openclaw_gateway_activation_ok "${openclaw_gateway_activation_ok}"
  print_kv openclaw_gateway_ok "${openclaw_gateway_ok}"

  print_kv tailscale_expected "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}"
  print_kv expected_tailscale_hostname "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}"
  if [[ "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}" == "1" ]]; then
    tailscaled_launchd_loaded_ok="0"
    tailscaled_launchd_running_ok="0"
    tailscaled_homebrew_launchd_absent_ok="1"
    tailscaled_homebrew_user_launchd_absent_ok="1"
    tailscaled_official_launchd_absent_ok="1"
    tailscaled_state_file_ok="0"

    if launchctl print "system/${TAILSCALED_LABEL}" >/dev/null 2>&1; then
      tailscaled_launchd_loaded_ok="1"
    fi

    if launchctl print "system/${TAILSCALED_LABEL}" 2>/dev/null |
      grep -Eq '^[[:space:]]*state = running$'; then
      tailscaled_launchd_running_ok="1"
    fi

    if launchctl print "system/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
      tailscaled_homebrew_launchd_absent_ok="0"
    fi

    if [[ -n "${admin_uid}" ]] && launchctl print "gui/${admin_uid}/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
      tailscaled_homebrew_user_launchd_absent_ok="0"
    fi

    if launchctl print "system/${OFFICIAL_TAILSCALE_LABEL}" >/dev/null 2>&1 ||
      [[ -f "${OFFICIAL_TAILSCALE_PLIST}" ]]; then
      tailscaled_official_launchd_absent_ok="0"
    fi

    if [[ -s "${TAILSCALED_STATE_FILE}" ]]; then
      tailscaled_state_file_ok="1"
    fi

    if command -v tailscale >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      tailscale_status_json="$(tailscale status --json 2>/dev/null || true)"
      if [[ -n "${tailscale_status_json}" ]]; then
        tailscale_backend_state="$(printf "%s" "${tailscale_status_json}" | jq -r '.BackendState // ""' 2>/dev/null || true)"
        tailscale_hostname="$(printf "%s" "${tailscale_status_json}" | jq -r '.Self.HostName // ""' 2>/dev/null || true)"
        tailscale_ip="$(printf "%s" "${tailscale_status_json}" | jq -r '(.Self.TailscaleIPs // []) | .[0] // ""' 2>/dev/null || true)"
        tailscale_magicdns_enabled="$(tailscale_magicdns_enabled_value "${tailscale_status_json}")"
        tailscale_https_certificates_enabled="$(tailscale_https_certificates_enabled_value "${tailscale_status_json}")"
        tailscale_magicdns_suffix="$(tailscale_magicdns_suffix_value "${tailscale_status_json}" || true)"
        tailscale_magicdns_resolver_path="$(tailscale_magicdns_resolver_path_value "${tailscale_magicdns_suffix}")"
        tailscale_magicdns_resolver_ok="$(tailscale_magicdns_resolver_ok_value "${tailscale_status_json}")"
      fi
      tailscale_operator_user="$(tailscale debug prefs 2>/dev/null | jq -r '.OperatorUser // ""' 2>/dev/null || true)"
    fi

    print_kv tailscale_backend_state "${tailscale_backend_state}"
    print_kv tailscale_hostname "${tailscale_hostname}"
    print_kv tailscale_ip "${tailscale_ip}"
    print_kv tailscale_operator_user "${tailscale_operator_user}"
    print_kv tailscale_magicdns_suffix "${tailscale_magicdns_suffix}"
    print_kv tailscale_magicdns_resolver_path "${tailscale_magicdns_resolver_path}"

    if [[ "${tailscale_backend_state}" == "Running" &&
      -n "${tailscale_ip}" &&
      -n "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}" &&
      "${tailscale_hostname}" == "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}" ]]; then
      tailscale_ok="1"
    else
      tailscale_ok="0"
    fi
    if [[ -n "${AGENTBOX_HEALTH_OPENCLAW_USER}" &&
      "${tailscale_operator_user}" == "${AGENTBOX_HEALTH_OPENCLAW_USER}" ]]; then
      tailscale_operator_ok="1"
    else
      tailscale_operator_ok="0"
    fi
    if [[ "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE}" == "serve" ]]; then
      mark_required tailscale_magicdns_enabled "${tailscale_magicdns_enabled}"
      mark_required tailscale_magicdns_resolver_ok "${tailscale_magicdns_resolver_ok}"
      mark_required tailscale_https_certificates_enabled "${tailscale_https_certificates_enabled}"
      openclaw_gateway_tailscale_serve_route_ok="$(
        openclaw_gateway_tailscale_serve_route_ok_value "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT}"
      )"
      mark_required openclaw_gateway_tailscale_serve_route_ok "${openclaw_gateway_tailscale_serve_route_ok}"
    else
      print_kv tailscale_magicdns_enabled "${tailscale_magicdns_enabled}"
      print_kv tailscale_magicdns_resolver_ok "${tailscale_magicdns_resolver_ok}"
      print_kv tailscale_https_certificates_enabled "${tailscale_https_certificates_enabled}"
    fi
    mark_required tailscaled_launchd_loaded_ok "${tailscaled_launchd_loaded_ok}"
    mark_required tailscaled_launchd_running_ok "${tailscaled_launchd_running_ok}"
    mark_required tailscaled_homebrew_launchd_absent_ok "${tailscaled_homebrew_launchd_absent_ok}"
    mark_required tailscaled_homebrew_user_launchd_absent_ok "${tailscaled_homebrew_user_launchd_absent_ok}"
    mark_required tailscaled_official_launchd_absent_ok "${tailscaled_official_launchd_absent_ok}"
    mark_required tailscaled_state_file_ok "${tailscaled_state_file_ok}"
    mark_required tailscale_operator_ok "${tailscale_operator_ok}"
    mark_required tailscale_ok "${tailscale_ok}"
  else
    print_kv tailscaled_launchd_loaded_ok "${tailscaled_launchd_loaded_ok}"
    print_kv tailscaled_launchd_running_ok "${tailscaled_launchd_running_ok}"
    print_kv tailscaled_homebrew_launchd_absent_ok "${tailscaled_homebrew_launchd_absent_ok}"
    print_kv tailscaled_homebrew_user_launchd_absent_ok "${tailscaled_homebrew_user_launchd_absent_ok}"
    print_kv tailscaled_official_launchd_absent_ok "${tailscaled_official_launchd_absent_ok}"
    print_kv tailscaled_state_file_ok "${tailscaled_state_file_ok}"
    print_kv tailscale_magicdns_enabled "${tailscale_magicdns_enabled}"
    print_kv tailscale_magicdns_resolver_ok "${tailscale_magicdns_resolver_ok}"
    print_kv tailscale_magicdns_suffix "${tailscale_magicdns_suffix}"
    print_kv tailscale_magicdns_resolver_path "${tailscale_magicdns_resolver_path}"
    print_kv tailscale_https_certificates_enabled "${tailscale_https_certificates_enabled}"
    print_kv tailscale_operator_user "${tailscale_operator_user}"
    print_kv tailscale_operator_ok "${tailscale_operator_ok}"
    print_kv tailscale_ok "${tailscale_ok}"
  fi
  if [[ "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}" != "1" ||
    "${AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE}" != "serve" ]]; then
    print_kv openclaw_gateway_tailscale_serve_route_ok "${openclaw_gateway_tailscale_serve_route_ok}"
  fi

  mark_required health_launchd_loaded_ok "${health_launchd_loaded_ok}"
  print_kv root_disk_available_kb "$(root_disk_available_kb)"
  print_kv uptime "$(uptime)"
  print_kv gatekeeper_status "$(gatekeeper_status)"
  print_kv filevault_status "$(filevault_status)"

  if [[ "${failures}" -eq 0 ]]; then
    print_kv agentbox_ok 1
    return 0
  fi

  print_kv agentbox_ok 0
  return 1
}

case "${1:-}" in
  "")
    {
      generate_report || true
      printf '%s\n' '---'
    } >> "${LOG_FILE}"
    ;;
  --report)
    generate_report || true
    ;;
  --check)
    generate_report
    ;;
  --brewgroup)
    print_brewgroup
    ;;
  *)
    printf 'Usage: health.sh [--report|--check|--brewgroup]\n' >&2
    exit 2
    ;;
esac
