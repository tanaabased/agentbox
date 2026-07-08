#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/var/db/tanaab/agentbox/health.env"
LOG_FILE="/var/log/tanaab/agentbox/health.log"
HEALTH_LABEL="dev.tanaab.agentbox.health"
TAILSCALED_LABEL="dev.tanaab.agentbox.tailscaled"
HOMEBREW_TAILSCALE_LABEL="homebrew.mxcl.tailscale"
SSHD_BIN="/usr/sbin/sshd"
SOCKETFILTERFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

AGENTBOX_HEALTH_EXPECTED_HOSTNAME=""
AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME=""
AGENTBOX_HEALTH_TAILSCALE_ENABLED="0"
AGENTBOX_HEALTH_BREWGROUP_ENABLED="0"
AGENTBOX_HEALTH_BREWGROUP="off"
AGENTBOX_HEALTH_TRUSTED_BREWGROUP_ENABLED="0"
AGENTBOX_HEALTH_TRUSTED_BREWGROUP="off"
AGENTBOX_HEALTH_BREW_PREFIX=""
AGENTBOX_HEALTH_HOMEBREW_PATHS_FILE="/etc/paths.d/00-agentbox-homebrew"
AGENTBOX_HEALTH_ADMIN_USER=""
AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED="0"
AGENTBOX_HEALTH_MANAGED_MACOS_RUNNER="0"
STATE_LOADED="0"

if [[ -r "${STATE_FILE}" ]]; then
  # shellcheck source=/dev/null
  . "${STATE_FILE}"
  STATE_LOADED="1"
fi

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

sshd_hardened_value() {
  local user="$1"
  local config

  if [[ -z "${user}" || ! -x "${SSHD_BIN}" ]]; then
    printf '0'
    return 0
  fi

  config="$("${SSHD_BIN}" -T 2>/dev/null)" || {
    printf '0'
    return 0
  }

  printf "%s\n" "${config}" | grep -Fxq "passwordauthentication no" || {
    printf '0'
    return 0
  }
  printf "%s\n" "${config}" | grep -Fxq "kbdinteractiveauthentication no" || {
    printf '0'
    return 0
  }
  printf "%s\n" "${config}" | grep -Fxq "permitrootlogin no" || {
    printf '0'
    return 0
  }
  printf "%s\n" "${config}" | grep -Fxq "pubkeyauthentication yes" || {
    printf '0'
    return 0
  }
  printf "%s\n" "${config}" | grep -Fxq "allowusers ${user}" || {
    printf '0'
    return 0
  }

  printf '1'
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
  if command -v fdesetup >/dev/null 2>&1; then
    fdesetup status 2>/dev/null || true
  else
    printf 'unavailable'
  fi
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
  local firewall_global_ok=""
  local firewall_stealth_ok=""
  local remote_login_ok=""
  local ssh_hardening_ok="skipped"
  local brew_prefix_group=""
  local brew_prefix_group_ok="skipped"
  local brew_prefix_group_rwx_ok="skipped"
  local brew_prefix_ok="skipped"
  local brewgroup_admin_user_ok="skipped"
  local homebrew_bin_path=""
  local homebrew_sbin_path=""
  local homebrew_login_path_bin_ok="0"
  local homebrew_login_path_file_ok="0"
  local homebrew_login_path_sbin_ok="0"
  local node_cli_path=""
  local node_cli_ok="0"
  local openclaw_cli_path=""
  local openclaw_cli_ok="0"
  local ripgrep_path=""
  local ripgrep_ok="0"
  local trusted_brewgroup_nested_ok="skipped"
  local health_launchd_loaded_ok="0"
  local tailscaled_launchd_loaded_ok="skipped"
  local tailscaled_homebrew_launchd_absent_ok="skipped"
  local tailscaled_homebrew_user_launchd_absent_ok="skipped"
  local tailscale_backend_state=""
  local tailscale_hostname=""
  local tailscale_ip=""
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
  firewall_global_ok="$(firewall_global_value)"
  firewall_stealth_ok="$(firewall_stealth_value)"
  remote_login_ok="$(remote_login_value)"
  admin_uid="$(id -u "${AGENTBOX_HEALTH_ADMIN_USER}" 2>/dev/null || true)"

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
  mark_required firewall_global_ok "${firewall_global_ok}"
  if [[ "${AGENTBOX_HEALTH_MANAGED_MACOS_RUNNER}" == "1" && "${firewall_stealth_ok}" != "1" ]]; then
    print_kv firewall_stealth_ok "${firewall_stealth_ok}"
  else
    mark_required firewall_stealth_ok "${firewall_stealth_ok}"
  fi
  mark_required remote_login_ok "${remote_login_ok}"

  print_kv ssh_hardening_expected "${AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED}"
  print_kv admin_user "${AGENTBOX_HEALTH_ADMIN_USER}"
  if [[ "${AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED}" == "1" ]]; then
    ssh_hardening_ok="$(sshd_hardened_value "${AGENTBOX_HEALTH_ADMIN_USER}")"
    mark_required ssh_hardening_ok "${ssh_hardening_ok}"
  else
    print_kv ssh_hardening_ok "${ssh_hardening_ok}"
  fi

  print_kv brewgroup_enabled "${AGENTBOX_HEALTH_BREWGROUP_ENABLED}"
  print_kv brewgroup_expected "${AGENTBOX_HEALTH_BREWGROUP}"
  if [[ "${AGENTBOX_HEALTH_BREWGROUP_ENABLED}" == "1" ]]; then
    brewgroup_admin_user_ok="$(group_user_member_value "${AGENTBOX_HEALTH_BREWGROUP}" "${AGENTBOX_HEALTH_ADMIN_USER}")"
    mark_required brewgroup_admin_user_ok "${brewgroup_admin_user_ok}"
  else
    print_kv brewgroup_admin_user_ok "${brewgroup_admin_user_ok}"
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

  print_kv tailscale_expected "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}"
  print_kv expected_tailscale_hostname "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}"
  if [[ "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}" == "1" ]]; then
    tailscaled_launchd_loaded_ok="0"
    tailscaled_homebrew_launchd_absent_ok="1"
    tailscaled_homebrew_user_launchd_absent_ok="1"

    if launchctl print "system/${TAILSCALED_LABEL}" >/dev/null 2>&1; then
      tailscaled_launchd_loaded_ok="1"
    fi

    if launchctl print "system/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
      tailscaled_homebrew_launchd_absent_ok="0"
    fi

    if [[ -n "${admin_uid}" ]] && launchctl print "gui/${admin_uid}/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
      tailscaled_homebrew_user_launchd_absent_ok="0"
    fi

    if command -v tailscale >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      tailscale_status_json="$(tailscale status --json 2>/dev/null || true)"
      if [[ -n "${tailscale_status_json}" ]]; then
        tailscale_backend_state="$(printf "%s" "${tailscale_status_json}" | jq -r '.BackendState // ""' 2>/dev/null || true)"
        tailscale_hostname="$(printf "%s" "${tailscale_status_json}" | jq -r '.Self.HostName // ""' 2>/dev/null || true)"
        tailscale_ip="$(printf "%s" "${tailscale_status_json}" | jq -r '(.Self.TailscaleIPs // []) | .[0] // ""' 2>/dev/null || true)"
      fi
    fi

    print_kv tailscale_backend_state "${tailscale_backend_state}"
    print_kv tailscale_hostname "${tailscale_hostname}"
    print_kv tailscale_ip "${tailscale_ip}"

    if [[ "${tailscale_backend_state}" == "Running" &&
      -n "${tailscale_ip}" &&
      -n "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}" &&
      "${tailscale_hostname}" == "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}" ]]; then
      tailscale_ok="1"
    else
      tailscale_ok="0"
    fi
    mark_required tailscaled_launchd_loaded_ok "${tailscaled_launchd_loaded_ok}"
    mark_required tailscaled_homebrew_launchd_absent_ok "${tailscaled_homebrew_launchd_absent_ok}"
    mark_required tailscaled_homebrew_user_launchd_absent_ok "${tailscaled_homebrew_user_launchd_absent_ok}"
    mark_required tailscale_ok "${tailscale_ok}"
  else
    print_kv tailscaled_launchd_loaded_ok "${tailscaled_launchd_loaded_ok}"
    print_kv tailscaled_homebrew_launchd_absent_ok "${tailscaled_homebrew_launchd_absent_ok}"
    print_kv tailscaled_homebrew_user_launchd_absent_ok "${tailscaled_homebrew_user_launchd_absent_ok}"
    print_kv tailscale_ok "${tailscale_ok}"
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
