#!/bin/bash
set -euo pipefail
# Bootstrap a macOS machine as a Tanaab agentbox profile.
#
# Examples assume the hosted script has been installed on PATH as `agentbox`.
# Running ./macos.sh from a source checkout also works for development.
#
#   $ AGENTBOX_AUTHORIZED_KEY="$(cat ~/.ssh/id_ed25519.pub)" AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" agentbox --hostname TANAABAGENTBOX1
#   $ agentbox --authorized-key file:~/.ssh/id_ed25519.pub --tailscale-authkey "$TS_AUTHKEY" --yes
#   $ AGENTBOX_DEBUG=1 AGENTBOX_AUTHORIZED_KEY="$(cat ~/.ssh/id_ed25519.pub)" AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" agentbox --yes
#
# Option precedence: CLI options override environment variables, which override defaults.

MACOS_OLDEST_SUPPORTED="26.0"
MACOS_UNSUPPORTED_AT_OR_AFTER="27.0"
MACOS_SUPPORTED_RANGE="26.x"
REQUIRED_CURL_VERSION="7.41.0"
BOOTBOX_URL="https://bootbox.tanaab.sh/bootbox.sh"
DEFAULT_AGENTBOX_HOSTNAME="TANAABAGENTBOX1"
DEFAULT_BREWGROUP="brewer"
BREWGROUP_DIRECTORY_ACL_RIGHTS="list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,directory_inherit"
BREWGROUP_FILE_ACL_RIGHTS="read,write,append,readattr,writeattr,readextattr,writeextattr,readsecurity"
BREWGROUP_FILE_INHERIT_ACL_RIGHTS="${BREWGROUP_FILE_ACL_RIGHTS},file_inherit,directory_inherit,only_inherit"
DEFAULT_OPENCLAW_IDENTITY="A Tanaab-based Claw <openclaw>"
DEFAULT_OPENCLAW_AUTOLOGIN="on"
DEFAULT_OPENCLAW_GATEWAY_PORT="18789"
DEFAULT_OPENCLAW_AUTH_CHOICE="skip"
OPENCLAW_UI_ASSISTANT_NAME="MODEL L3-37"
OPENCLAW_UI_SEAM_COLOR="#00c88a"
AGENTBOX_OPT_DIR="/opt/tanaab/agentbox"
AGENTBOX_PROFILE_IMAGE_PATH="${AGENTBOX_OPT_DIR}/profile.png"
AGENTBOX_LOG_DIR="/var/log/tanaab/agentbox"
AGENTBOX_STATE_DIR="/var/db/tanaab/agentbox"
AGENTBOX_TAILSCALED_STATE_DIR="${AGENTBOX_STATE_DIR}/tailscale"
AGENTBOX_HEALTH_STATE_PATH="${AGENTBOX_STATE_DIR}/health.env"
AGENTBOX_HEALTH_LABEL="dev.tanaab.agentbox.health"
AGENTBOX_TAILSCALED_LABEL="dev.tanaab.agentbox.tailscaled"
AGENTBOX_TAILSCALED_PLIST_PATH="/Library/LaunchDaemons/${AGENTBOX_TAILSCALED_LABEL}.plist"
OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL="ai.openclaw.gateway"
AGENTBOX_OPENCLAW_FINALIZER_LABEL="dev.tanaab.agentbox.openclaw-finalize"
AGENTBOX_OPENCLAW_SERVICE_KIND="openclaw-gateway"
OPENCLAW_DISABLE_LAUNCH_AGENT_MARKER=".openclaw/disable-launchagent"
AGENTBOX_HOMEBREW_PATHS_FILE="/etc/paths.d/00-agentbox-homebrew"
HOMEBREW_TAILSCALE_LABEL="homebrew.mxcl.tailscale"
HOMEBREW_TAILSCALE_SYSTEM_PLIST_PATH="/Library/LaunchDaemons/${HOMEBREW_TAILSCALE_LABEL}.plist"
OFFICIAL_TAILSCALE_LABEL="com.tailscale.tailscaled"
OFFICIAL_TAILSCALE_SYSTEM_PLIST_PATH="/Library/LaunchDaemons/${OFFICIAL_TAILSCALE_LABEL}.plist"
AGENTBOX_REPO_ARCHIVE_BASE_URL="https://github.com/tanaabased/agentbox/archive/refs/tags"
SSHD_BIN="/usr/sbin/sshd"
SSHD_CONFIG_PATH="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_AGENTBOX_CONFIG_PATH="${SSHD_CONFIG_DIR}/agentbox.conf"
SSH_ACCESS_GROUP="com.apple.access_ssh"
SUDO_BIN="/usr/bin/sudo"
TAILSCALE_DNS_ADMIN_URL="https://login.tailscale.com/admin/dns"
TAILSCALE_MAGICDNS_DOCS_URL="https://tailscale.com/docs/features/magicdns"
TAILSCALE_HTTPS_CERTS_DOCS_URL="https://tailscale.com/docs/how-to/set-up-https-certificates"

abort() {
  printf "%serror%s: %s\n" "${tty_red-}" "${tty_reset-}" "$*" >&2
  exit 1
}

abort_multi() {
  while read -r line; do
    printf "%serror%s: %s\n" "${tty_red-}" "${tty_reset-}" "${line}" >&2
  done <<< "$*"
  exit 1
}

value_enabled() {
  case "${1:-}" in
    '' | 0 | false | FALSE | False | no | NO | No | off | OFF | Off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

value_disabled() {
  case "${1:-}" in
    0 | false | FALSE | False | no | NO | No | off | OFF | Off | null | NULL | Null)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mask_secret_for_display() {
  local value="$1"
  local length="${#value}"
  local prefix_length="4"
  local suffix_length="4"
  local suffix_start

  if [[ -z "${value}" ]]; then
    printf "none"
    return 0
  fi

  if [[ "${length}" -le 4 ]]; then
    printf "****"
    return 0
  fi

  if [[ "${length}" -le 8 ]]; then
    prefix_length="2"
    suffix_length="2"
  fi

  suffix_start=$((length - suffix_length))
  printf "%s...%s" "${value:0:${prefix_length}}" "${value:${suffix_start}:${suffix_length}}"
}

trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf "%s" "${value}"
}

append_array_value() {
  local array_name="$1"
  local value
  local quoted

  value="$(trim_whitespace "$2")"
  if [[ -n "${value}" ]]; then
    printf -v quoted "%q" "${value}"
    eval "${array_name}+=(${quoted})"
  fi
}

array_has_values() {
  local array_name="$1"
  local count

  # Bash 3.2 with nounset treats empty array expansion as unbound.
  eval "count=\${#${array_name}[@]}"
  [[ "${count}" -gt 0 ]]
}

array_count() {
  local array_name="$1"
  local count

  # Bash 3.2 with nounset treats empty array expansion as unbound.
  eval "count=\${#${array_name}[@]}"
  printf "%s" "${count}"
}

array_join() {
  local delimiter="$1"
  local array_name="$2"
  local count
  local index
  local value

  # Bash 3.2 with nounset treats empty array expansion as unbound.
  eval "count=\${#${array_name}[@]}"
  for ((index = 0; index < count; index++)); do
    eval "value=\"\${${array_name}[${index}]}\""
    if [[ "${index}" -gt 0 ]]; then
      printf "%s" "${delimiter}"
    fi
    printf "%s" "${value}"
  done
}

append_csv_to_array() {
  local array_name="$1"
  local old_ifs="${IFS}"
  local entry
  local -a values=()

  if [[ -z "${2}" ]]; then
    return 0
  fi

  IFS=","
  read -r -a values <<< "${2}"
  IFS="${old_ifs}"

  if ! array_has_values values; then
    return 0
  fi

  for entry in "${values[@]}"; do
    append_array_value "${array_name}" "${entry}"
  done
}

shell_join() {
  local arg

  printf "%s" "${1:-}"
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  shift

  for arg in "$@"; do
    printf " "
    printf "%q" "${arg}"
  done
}

shell_quote() {
  printf "%q" "$1"
}

shell_single_quote() {
  local value="$1"

  printf "'"
  printf "%s" "${value}" | sed "s/'/'\\\\''/g"
  printf "'"
}

dotenv_double_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "${value}"
}

xml_escape() {
  local value="$1"

  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf "%s" "${value}"
}

# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]; then
  abort "bash is required to interpret this script."
fi

if [[ -n "${CI-}" && -n "${INTERACTIVE-}" ]]; then
  abort "cannot run force-interactive mode in CI."
fi

# shellcheck disable=SC2016
if [[ -n "${INTERACTIVE-}" && -n "${NONINTERACTIVE-}" ]]; then
  abort 'both $INTERACTIVE and $NONINTERACTIVE are set. please unset at least one variable and try again.'
fi

if [[ -n "${POSIXLY_CORRECT+1}" ]]; then
  abort 'bash must not run in POSIX mode. please unset POSIXLY_CORRECT and try again.'
fi

if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi

tty_mkbold() { tty_escape "1;$1"; }
tty_mkdim() { tty_escape "2;$1"; }
tty_bold="$(tty_mkbold 39)"
tty_dim="$(tty_mkdim 39)"
tty_green="$(tty_mkbold 32)"
tty_magenta="$(tty_escape 35)"
tty_red="$(tty_mkbold 31)"
tty_reset="$(tty_escape 0)"
tty_underline="$(tty_escape "4;39")"
tty_yellow="$(tty_escape 33)"
tty_tp="$(tty_escape '38;2;0;200;138')"
tty_ts="$(tty_escape '38;2;219;39;119')"

SCRIPT_NAME="${0##*/}"
# Keep a single top-level assignment so release automation can stamp the entrypoint in place.
SCRIPT_VERSION="${SCRIPT_VERSION:-$(git describe --tags --always --abbrev=1 2>/dev/null || printf '%s' '0.0.0-unreleased')}"
INVOCATION_CWD="${PWD}"

DEBUG="${AGENTBOX_DEBUG:-${DEBUG:-${RUNNER_DEBUG:-}}}"
FORCE="${AGENTBOX_FORCE:-}"
AGENTBOX_PAYLOAD_DIR_INPUT="${AGENTBOX_PAYLOAD_DIR:-}"
AGENTBOX_PAYLOAD_DIR=""
AGENTBOX_LIBEXEC_DIR=""
AGENTBOX_PAYLOAD_SOURCE_KIND=""
AGENTBOX_PAYLOAD_RELEASE_TAG=""
AGENTBOX_HOSTNAME_VALUE="${AGENTBOX_HOSTNAME:-${DEFAULT_AGENTBOX_HOSTNAME}}"
BREWGROUP_INPUT="${AGENTBOX_BREWGROUP:-${DEFAULT_BREWGROUP}}"
BREWGROUP_VALUE=""
TRUSTED_BREWGROUP_VALUE=""
OPENCLAW_IDENTITY_INPUT="${AGENTBOX_OPENCLAW_IDENTITY:-${DEFAULT_OPENCLAW_IDENTITY}}"
OPENCLAW_FULL_NAME=""
OPENCLAW_USER=""
OPENCLAW_PASSWORD="${AGENTBOX_OPENCLAW_PASSWORD:-}"
OPENCLAW_AUTOLOGIN="${AGENTBOX_OPENCLAW_AUTOLOGIN:-${DEFAULT_OPENCLAW_AUTOLOGIN}}"
OPENCLAW_GATEWAY_BIND_VALUE="loopback"
OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE=""
OPENCLAW_GATEWAY_PORT="${AGENTBOX_OPENCLAW_GATEWAY_PORT:-${DEFAULT_OPENCLAW_GATEWAY_PORT}}"
OPENCLAW_GATEWAY_PORT_EXPLICIT="${AGENTBOX_OPENCLAW_GATEWAY_PORT+x}"
OPENCLAW_AUTH_CHOICE="${AGENTBOX_OPENCLAW_AUTH_CHOICE:-${DEFAULT_OPENCLAW_AUTH_CHOICE}}"
OPENCLAW_AUTH_ENV="${AGENTBOX_OPENCLAW_AUTH_ENV:-}"
TAILSCALE_AUTHKEY="${AGENTBOX_TAILSCALE_AUTHKEY:-}"
ADMIN_USER=""
AUTHORIZED_KEY_CLI_SEEN="0"
EXTRA_BREWFILE_CLI_SEEN="0"
declare -a PLANNED_ACTIONS=()
declare -a AUTHORIZED_KEY_SPECS=()
declare -a AUTHORIZED_KEY_LINES=()
declare -a EXTRA_BREWFILE_SPECS=()
declare -a RESOLVED_EXTRA_BREWFILES=()
declare -a AGENTBOX_PROFILE_IMAGE_SOURCES=()
BOOT_TMPDIR=""
BOOTBOX_SCRIPT_PATH=""
SUDO_KEEPALIVE_PID=""
SUDO_SESSION_ACTIVE="0"
CORE_NEEDS_REMEDIATION="0"
CURL=""
DETECTED_ARCH=""
DETECTED_OS=""
ARCH=""
OS=""
AGENTBOX_CORE_BREWFILE=""
AGENTBOX_BIN_DIR=""
AGENTBOX_LAUNCHD_DIR=""
AGENTBOX_ASSETS_DIR=""
AGENTBOX_HEALTH_SCRIPT_SOURCE=""
AGENTBOX_HEALTH_PLIST_TEMPLATE=""
AGENTBOX_TAILSCALED_PLIST_TEMPLATE=""
AGENTBOX_OPENCLAW_FINALIZER_PLIST_TEMPLATE=""
AGENTBOX_OPENCLAW_FINALIZER_SOURCE=""
AGENTBOX_PROFILE_IMAGE_SOURCE=""
AGENTBOX_DEFAULT_AVATAR_SOURCE=""
BREW_PREFIX_VALUE=""
TAILSCALE_HOSTNAME_VALUE=""
OPENCLAW_GATEWAY_SETUP_STATUS="not_configured"

if [[ -n "${AGENTBOX_AUTHORIZED_KEY:-}" ]]; then
  append_array_value AUTHORIZED_KEY_SPECS "${AGENTBOX_AUTHORIZED_KEY}"
fi

if [[ -n "${AGENTBOX_AUTHORIZED_KEYS:-}" ]]; then
  append_csv_to_array AUTHORIZED_KEY_SPECS "${AGENTBOX_AUTHORIZED_KEYS}"
fi

if [[ -n "${AGENTBOX_BREWFILE:-}" ]]; then
  append_csv_to_array EXTRA_BREWFILE_SPECS "${AGENTBOX_BREWFILE}"
fi

if [[ -n "${AGENTBOX_BREWFILES:-}" ]]; then
  append_csv_to_array EXTRA_BREWFILE_SPECS "${AGENTBOX_BREWFILES}"
fi

debug_enabled() {
  value_enabled "${DEBUG:-}"
}

force_enabled() {
  value_enabled "${FORCE:-}"
}

unsupported_macos_allowed() {
  value_enabled "${AGENTBOX_ALLOW_UNSUPPORTED_MACOS:-}"
}

tailscale_setup_disabled() {
  value_disabled "${TAILSCALE_AUTHKEY:-}"
}

brewgroup_setup_disabled() {
  value_disabled "${BREWGROUP_INPUT:-}"
}

trusted_brewgroup_enabled() {
  [[ -n "${TRUSTED_BREWGROUP_VALUE}" ]] && ! brewgroup_setup_disabled
}

tailscale_authkey_display() {
  if tailscale_setup_disabled; then
    printf "disabled"
    return 0
  fi

  mask_secret_for_display "${TAILSCALE_AUTHKEY:-}"
}

brewgroup_display() {
  if brewgroup_setup_disabled; then
    printf "disabled"
    return 0
  fi

  printf "%s" "${BREWGROUP_INPUT}"
}

openclaw_autologin_enabled() {
  [[ "${OPENCLAW_AUTOLOGIN}" == "on" ]]
}

openclaw_password_display() {
  if [[ -n "${OPENCLAW_PASSWORD}" ]]; then
    printf "provided"
  else
    printf "none"
  fi
}

openclaw_gateway_port_display() {
  printf "%s" "${OPENCLAW_GATEWAY_PORT}"
}

openclaw_auth_choice_display() {
  printf "%s" "${OPENCLAW_AUTH_CHOICE}"
}

openclaw_auth_env_display() {
  printf "%s" "${OPENCLAW_AUTH_ENV:-none}"
}

env_name_valid() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# Keep this aligned with OpenClaw's manifest-declared env-backed auth choices.
openclaw_auth_choice_env_names() {
  case "${1:-}" in
    alibaba-model-studio-api-key)
      printf "%s\n" MODELSTUDIO_API_KEY DASHSCOPE_API_KEY QWEN_API_KEY
      ;;
    apiKey | setup-token)
      printf "%s\n" ANTHROPIC_OAUTH_TOKEN ANTHROPIC_API_KEY
      ;;
    arceeai-api-key | arceeai-openrouter)
      printf "%s\n" ARCEEAI_API_KEY OPENROUTER_API_KEY
      ;;
    byteplus-api-key)
      printf "%s\n" BYTEPLUS_API_KEY
      ;;
    cerebras-api-key)
      printf "%s\n" CEREBRAS_API_KEY
      ;;
    chutes-api-key)
      printf "%s\n" CHUTES_API_KEY CHUTES_OAUTH_TOKEN
      ;;
    cloudflare-ai-gateway-api-key)
      printf "%s\n" CLOUDFLARE_AI_GATEWAY_API_KEY
      ;;
    comfy-cloud-api-key)
      printf "%s\n" COMFY_API_KEY COMFY_CLOUD_API_KEY
      ;;
    custom-api-key)
      printf "%s\n" CUSTOM_API_KEY
      ;;
    deepinfra-api-key)
      printf "%s\n" DEEPINFRA_API_KEY
      ;;
    deepseek-api-key)
      printf "%s\n" DEEPSEEK_API_KEY
      ;;
    fal-api-key)
      printf "%s\n" FAL_KEY FAL_API_KEY
      ;;
    fireworks-api-key)
      printf "%s\n" FIREWORKS_API_KEY
      ;;
    gmi-api-key)
      printf "%s\n" GMI_API_KEY
      ;;
    gemini-api-key)
      printf "%s\n" GEMINI_API_KEY GOOGLE_API_KEY
      ;;
    huggingface-api-key)
      printf "%s\n" HUGGINGFACE_HUB_TOKEN HF_TOKEN
      ;;
    kilocode-api-key)
      printf "%s\n" KILOCODE_API_KEY
      ;;
    kimi-code-api-key)
      printf "%s\n" KIMI_API_KEY KIMICODE_API_KEY
      ;;
    litellm-api-key)
      printf "%s\n" LITELLM_API_KEY
      ;;
    microsoft-foundry-apikey)
      printf "%s\n" AZURE_OPENAI_API_KEY
      ;;
    minimax-global-api | minimax-cn-api)
      printf "%s\n" MINIMAX_CODE_PLAN_KEY MINIMAX_CODING_API_KEY MINIMAX_API_KEY
      ;;
    mistral-api-key)
      printf "%s\n" MISTRAL_API_KEY
      ;;
    moonshot-api-key | moonshot-api-key-cn)
      printf "%s\n" MOONSHOT_API_KEY KIMI_API_KEY
      ;;
    novita-api-key)
      printf "%s\n" NOVITA_API_KEY
      ;;
    nvidia-api-key)
      printf "%s\n" NVIDIA_API_KEY
      ;;
    ollama-cloud)
      printf "%s\n" OLLAMA_API_KEY
      ;;
    openai-api-key)
      printf "%s\n" OPENAI_API_KEY
      ;;
    opencode-zen | opencode-go)
      printf "%s\n" OPENCODE_API_KEY OPENCODE_ZEN_API_KEY
      ;;
    openrouter-api-key)
      printf "%s\n" OPENROUTER_API_KEY
      ;;
    qianfan-api-key)
      printf "%s\n" QIANFAN_API_KEY
      ;;
    qwen-standard-api-key-cn | qwen-standard-api-key | qwen-api-key-cn | qwen-api-key | qwen-oauth)
      printf "%s\n" QWEN_API_KEY MODELSTUDIO_API_KEY DASHSCOPE_API_KEY
      ;;
    runway-api-key)
      printf "%s\n" RUNWAYML_API_SECRET RUNWAY_API_KEY
      ;;
    stepfun-standard-api-key-cn | stepfun-standard-api-key-intl | stepfun-plan-api-key-cn | stepfun-plan-api-key-intl)
      printf "%s\n" STEPFUN_API_KEY
      ;;
    synthetic-api-key)
      printf "%s\n" SYNTHETIC_API_KEY
      ;;
    tokenhub-api-key)
      printf "%s\n" TOKENHUB_API_KEY
      ;;
    together-api-key)
      printf "%s\n" TOGETHER_API_KEY
      ;;
    venice-api-key)
      printf "%s\n" VENICE_API_KEY
      ;;
    ai-gateway-api-key)
      printf "%s\n" AI_GATEWAY_API_KEY
      ;;
    volcengine-api-key)
      printf "%s\n" VOLCANO_ENGINE_API_KEY
      ;;
    vydra-api-key)
      printf "%s\n" VYDRA_API_KEY
      ;;
    xai-api-key)
      printf "%s\n" XAI_API_KEY
      ;;
    xiaomi-api-key)
      printf "%s\n" XIAOMI_API_KEY
      ;;
    xiaomi-token-plan-ams | xiaomi-token-plan-cn | xiaomi-token-plan-sgp)
      printf "%s\n" XIAOMI_TOKEN_PLAN_API_KEY
      ;;
    zai-api-key)
      printf "%s\n" ZAI_API_KEY Z_AI_API_KEY
      ;;
  esac
}

openclaw_auth_choice_env_name_list() {
  local auth_choice="$1"
  local delimiter="${2:-, }"
  local env_name
  local output=""

  for env_name in $(openclaw_auth_choice_env_names "${auth_choice}"); do
    output="${output}${output:+${delimiter}}${env_name}"
  done

  printf "%s" "${output}"
}

openclaw_auth_choice_present_env_name_list() {
  local auth_choice="$1"
  local delimiter="${2:- }"
  local env_name
  local output=""

  for env_name in $(openclaw_auth_choice_env_names "${auth_choice}"); do
    if [[ -n "${!env_name-}" ]]; then
      output="${output}${output:+${delimiter}}${env_name}"
    fi
  done

  printf "%s" "${output}"
}

validate_openclaw_auth_choice_env() {
  local auth_env_names
  local present_env_names

  if [[ "${OPENCLAW_AUTH_CHOICE}" == "skip" ]]; then
    if [[ -n "${OPENCLAW_AUTH_ENV}" ]]; then
      abort "openclaw auth env ${tty_ts}${OPENCLAW_AUTH_ENV}${tty_reset} requires an openclaw auth choice other than ${tty_ts}skip${tty_reset}."
    fi
    return 0
  fi

  if [[ -n "${OPENCLAW_AUTH_ENV}" ]]; then
    if [[ -z "${!OPENCLAW_AUTH_ENV-}" ]]; then
      abort_multi "$(cat <<EOABORT
openclaw auth env ${tty_ts}${OPENCLAW_AUTH_ENV}${tty_reset} is not set in the parent environment.
set ${tty_ts}${OPENCLAW_AUTH_ENV}${tty_reset} before running agentbox so it can be passed to openclaw onboarding, or remove ${tty_ts}--openclaw-auth-env${tty_reset}.
openclaw provider docs: ${tty_underline}${tty_magenta}https://docs.openclaw.ai/providers${tty_reset}
EOABORT
)"
    fi
    return 0
  fi

  auth_env_names="$(openclaw_auth_choice_env_name_list "${OPENCLAW_AUTH_CHOICE}")"
  if [[ -z "${auth_env_names}" ]]; then
    return 0
  fi

  present_env_names="$(openclaw_auth_choice_present_env_name_list "${OPENCLAW_AUTH_CHOICE}")"
  if [[ -n "${present_env_names}" ]]; then
    return 0
  fi

  abort_multi "$(cat <<EOABORT
openclaw auth choice ${tty_ts}${OPENCLAW_AUTH_CHOICE}${tty_reset} requires one of these parent environment variables: ${tty_ts}${auth_env_names}${tty_reset}.
set the matching provider key in the environment before running agentbox so it can be passed to openclaw onboarding, or use ${tty_ts}--openclaw-auth-choice skip${tty_reset}.
openclaw provider docs: ${tty_underline}${tty_magenta}https://docs.openclaw.ai/providers${tty_reset}
EOABORT
)"
}

extra_brewfiles_display() {
  local display

  display="$(array_join "," EXTRA_BREWFILE_SPECS)"
  printf "%s" "${display:-none}"
}

debug() {
  if debug_enabled; then
    printf "${tty_dim}debug${tty_reset} %s\n" "$(shell_join "$@")" >&2
  fi
}

debug_multi() {
  local label="$1"
  local value="${2:-}"

  if debug_enabled; then
    printf "${tty_dim}debug${tty_reset} %s\n" "${label}" >&2
    printf "%s\n" "${value}" >&2
  fi
}

log() {
  printf "%s\n" "$*"
}

warn() {
  printf "${tty_yellow}warn${tty_reset}: %s\n" "$*" >&2
}

show_version() {
  printf "%s\n" "${SCRIPT_VERSION}"
  exit 0
}

is_semver_value() {
  [[ "${1:-}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z-]*(\.[0-9A-Za-z][0-9A-Za-z-]*)*)?$ ]]
}

normalize_release_tag() {
  if [[ "$1" == v* ]]; then
    printf "%s" "$1"
  else
    printf "v%s" "$1"
  fi
}

display_home_path() {
  local path="$1"

  if [[ "${path}" == "${HOME}" ]]; then
    printf "~"
    return 0
  fi

  if [[ "${path}" == "${HOME}/"* ]]; then
    printf "%s/%s" "~" "${path#"${HOME}"/}"
    return 0
  fi

  printf "%s" "${path}"
}

expand_home_path() {
  local path="$1"

  if [[ "${path}" == "~" ]]; then
    printf "%s" "${HOME}"
    return 0
  fi

  if [[ "${path}" == \~/* ]]; then
    printf "%s/%s" "${HOME}" "${path#\~/}"
    return 0
  fi

  printf "%s" "${path}"
}

brewfile_source_url_value() {
  [[ "${1:-}" =~ ^[[:alpha:]][[:alnum:].+-]*:// ]]
}

resolve_extra_brewfile_source_path() {
  local brewfile
  local invocation_path
  local target_path

  brewfile="$(expand_home_path "$1")"

  if [[ "${brewfile}" == /* ]]; then
    if [[ -f "${brewfile}" ]]; then
      printf "%s" "${brewfile}"
      return 0
    fi

    return 1
  fi

  invocation_path="${INVOCATION_CWD}/${brewfile}"
  if [[ -f "${invocation_path}" ]]; then
    printf "%s" "${invocation_path}"
    return 0
  fi

  target_path="${AGENTBOX_PAYLOAD_DIR}/${brewfile}"
  if [[ -f "${target_path}" ]]; then
    printf "%s" "${target_path}"
    return 0
  fi

  return 1
}

hostname_valid() {
  [[ "${1:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

brewgroup_valid() {
  [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_.-]{0,63}$ ]]
}

openclaw_short_name_valid() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]
}

openclaw_gateway_port_valid() {
  local port="${1:-}"

  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  (( 10#${port} >= 1 && 10#${port} <= 65535 ))
}

openclaw_autologin_valid() {
  case "${1:-}" in
    on | off)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

derive_openclaw_gateway_tailscale_mode() {
  if tailscale_setup_disabled; then
    OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE="off"
  else
    OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE="serve"
  fi
}

parse_openclaw_identity_input() {
  local identity
  local identity_regex='^(.+)[[:space:]]<([^<>[:space:]]+)>$'
  local full_name
  local short_name

  identity="$(trim_whitespace "${OPENCLAW_IDENTITY_INPUT}")"
  if [[ -z "${identity}" ]]; then
    abort "openclaw identity must not be empty."
  fi

  if [[ ! "${identity}" =~ ${identity_regex} ]]; then
    abort "openclaw identity ${tty_ts}${identity}${tty_reset} must use ${tty_bold}full name <shortname>${tty_reset} syntax."
  fi

  full_name="$(trim_whitespace "${BASH_REMATCH[1]}")"
  short_name="$(trim_whitespace "${BASH_REMATCH[2]}")"

  if [[ -z "${full_name}" ]]; then
    abort "openclaw identity full name must not be empty."
  fi

  if ! openclaw_short_name_valid "${short_name}"; then
    abort "openclaw short username ${tty_ts}${short_name}${tty_reset} must start with a lowercase letter and contain only lowercase letters, digits, underscore, or dash."
  fi

  if [[ "${short_name}" == "root" ]]; then
    abort "openclaw short username must not be ${tty_ts}root${tty_reset}."
  fi

  OPENCLAW_FULL_NAME="${full_name}"
  OPENCLAW_USER="${short_name}"
}

parse_brewgroup_input() {
  BREWGROUP_VALUE=""
  TRUSTED_BREWGROUP_VALUE=""

  if brewgroup_setup_disabled; then
    return 0
  fi

  if [[ "${BREWGROUP_INPUT}" == *:*:* ]]; then
    abort "brewgroup ${tty_ts}${BREWGROUP_INPUT}${tty_reset} must use brewgroup or brewgroup:trusted-group syntax."
  fi

  if [[ "${BREWGROUP_INPUT}" == *:* ]]; then
    BREWGROUP_VALUE="${BREWGROUP_INPUT%%:*}"
    TRUSTED_BREWGROUP_VALUE="${BREWGROUP_INPUT#*:}"
  else
    BREWGROUP_VALUE="${BREWGROUP_INPUT}"
  fi

  if [[ "${BREWGROUP_INPUT}" == :* || "${BREWGROUP_INPUT}" == *: ]]; then
    abort "brewgroup ${tty_ts}${BREWGROUP_INPUT}${tty_reset} must use brewgroup or brewgroup:trusted-group syntax."
  fi

  if value_disabled "${BREWGROUP_VALUE}" || {
    [[ -n "${TRUSTED_BREWGROUP_VALUE}" ]] && value_disabled "${TRUSTED_BREWGROUP_VALUE}"
  }; then
    abort "falsey brewgroup values must be used alone, not in brewgroup:trusted-group syntax."
  fi
}

derive_tailscale_hostname() {
  local hostname="$1"

  case "${hostname:0:6}" in
    [Tt][Aa][Nn][Aa][Aa][Bb])
      printf "%s" "${hostname:6}"
      ;;
    *)
      printf "%s" "${hostname}"
      ;;
  esac
}

select_openclaw_profile_image_source() {
  local count
  local index

  count="$(array_count AGENTBOX_PROFILE_IMAGE_SOURCES)"
  if [[ "${count}" -lt 1 ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required runtime assets ${tty_ts}assets/profile*.png${tty_reset}."
  fi

  index=$((RANDOM % count))
  eval "AGENTBOX_PROFILE_IMAGE_SOURCE=\"\${AGENTBOX_PROFILE_IMAGE_SOURCES[${index}]}\""
}

usage_option() {
  local option="$1"
  local description="$2"
  local default="${3:-}"

  if [[ "$#" -ge 3 ]]; then
    printf "  %-27s %s %s\n" "${option}" "${description}" "${tty_dim}[default: ${default}]${tty_reset}"
  else
    printf "  %-27s %s\n" "${option}" "${description}"
  fi
}

usage() {
  local debug_display="off"
  local force_display="off"
  local tailscale_authkey_display_value="none"
  local brewgroup_display_value="none"
  local openclaw_password_display_value="none"
  local openclaw_autologin_display_value="${DEFAULT_OPENCLAW_AUTOLOGIN}"
  local openclaw_gateway_port_display_value="${DEFAULT_OPENCLAW_GATEWAY_PORT}"
  local openclaw_auth_choice_display_value="${DEFAULT_OPENCLAW_AUTH_CHOICE}"
  local openclaw_auth_env_display_value="none"
  local extra_brewfiles_display_value="none"
  local authorized_keys_display="none"

  if debug_enabled; then
    debug_display="on"
  fi

  if force_enabled; then
    force_display="on"
  fi

  tailscale_authkey_display_value="$(tailscale_authkey_display)"
  brewgroup_display_value="$(brewgroup_display)"
  openclaw_password_display_value="$(openclaw_password_display)"
  openclaw_autologin_display_value="${OPENCLAW_AUTOLOGIN}"
  openclaw_gateway_port_display_value="$(openclaw_gateway_port_display)"
  openclaw_auth_choice_display_value="$(openclaw_auth_choice_display)"
  openclaw_auth_env_display_value="$(openclaw_auth_env_display)"
  extra_brewfiles_display_value="$(extra_brewfiles_display)"
  if array_has_values AUTHORIZED_KEY_SPECS; then
    authorized_keys_display="$(array_count AUTHORIZED_KEY_SPECS) provided"
  fi

  cat <<EOS
Usage: ${tty_dim}[NONINTERACTIVE=1] [CI=1] [AGENTBOX_*...]${tty_reset} ${tty_bold}${SCRIPT_NAME}${tty_reset} ${tty_dim}[options]${tty_reset}

${tty_tp}Options:${tty_reset}
EOS

  usage_option "--brewfile" "adds an extra Brewfile from a local path or url" "${extra_brewfiles_display_value}"
  usage_option "--hostname" "sets the system hostname and tailscale name source" "${AGENTBOX_HOSTNAME_VALUE}"
  usage_option "--authorized-key" "adds an ssh public key or public-key file path" "${authorized_keys_display}"
  usage_option "--tailscale-authkey" "uses a tailscale auth key to join; falsey disables setup" "${tailscale_authkey_display_value}"
  usage_option "--brewgroup" "manages homebrew prefix group write access; accepts group[:trusted-group]; falsey disables setup" "${brewgroup_display_value}"
  usage_option "--openclaw-identity" "configures the openclaw runner as \"full name <shortname>\"" "${OPENCLAW_IDENTITY_INPUT}"
  usage_option "--openclaw-password" "sets the openclaw runner password for user creation or autologin" "${openclaw_password_display_value}"
  usage_option "--openclaw-autologin" "sets runtime-user autologin for unattended reboot recovery: on or off" "${openclaw_autologin_display_value}"
  usage_option "--openclaw-auth-choice" "sets initial openclaw model auth choice" "${openclaw_auth_choice_display_value}"
  usage_option "--openclaw-auth-env" "passes one extra parent env var to openclaw auth onboarding" "${openclaw_auth_env_display_value}"
  usage_option "--openclaw-gateway-port" "sets openclaw gateway port" "${openclaw_gateway_port_display_value}"
  usage_option "--version" "shows version of this script"
  usage_option "--debug" "shows debug messages" "${debug_display}"
  usage_option "--force" "forces supported replacement operations" "${force_display}"
  usage_option "-h, --help" "displays this help message"
  usage_option "-y, --yes" "runs with all defaults and no prompts, sets NONINTERACTIVE=1"

  cat <<EOS

${tty_tp}Environment Variables:${tty_reset}
  AGENTBOX_BREWFILE              same as --brewfile
  AGENTBOX_HOSTNAME              same as --hostname
  AGENTBOX_AUTHORIZED_KEY        same as --authorized-key
  AGENTBOX_TAILSCALE_AUTHKEY     same as --tailscale-authkey
  AGENTBOX_BREWGROUP             same as --brewgroup
  AGENTBOX_OPENCLAW_IDENTITY     same as --openclaw-identity
  AGENTBOX_OPENCLAW_PASSWORD     same as --openclaw-password
  AGENTBOX_OPENCLAW_AUTOLOGIN    same as --openclaw-autologin
  AGENTBOX_OPENCLAW_AUTH_CHOICE  same as --openclaw-auth-choice
  AGENTBOX_OPENCLAW_AUTH_ENV     same as --openclaw-auth-env
  AGENTBOX_OPENCLAW_GATEWAY_PORT same as --openclaw-gateway-port
  AGENTBOX_FORCE                 same as --force
  NONINTERACTIVE                 same as --yes
  AGENTBOX_DEBUG                 same as --debug
  CI                             runs in CI mode and disables prompts
EOS
  if [[ "${1:-0}" != "noexit" ]]; then
    exit "${1:-0}"
  fi
}

abort_option_usage() {
  usage "noexit"
  abort "$1"
}

require_next_option_value() {
  local option="$1"
  local argc="$2"

  if [[ "${argc}" -lt 2 ]]; then
    abort_option_usage "option ${tty_bold}${option}${tty_reset} requires a value."
  fi
}

require_inline_option_value() {
  local option="$1"
  local value="$2"

  if [[ -z "${value}" ]]; then
    abort_option_usage "option ${tty_bold}${option}${tty_reset} must not be empty."
  fi
}

reset_authorized_key_specs_for_cli() {
  if [[ "${AUTHORIZED_KEY_CLI_SEEN}" == "0" ]]; then
    AUTHORIZED_KEY_SPECS=()
    AUTHORIZED_KEY_CLI_SEEN="1"
  fi
}

reset_extra_brewfile_specs_for_cli() {
  if [[ "${EXTRA_BREWFILE_CLI_SEEN}" == "0" ]]; then
    EXTRA_BREWFILE_SPECS=()
    EXTRA_BREWFILE_CLI_SEEN="1"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brewfile)
        require_next_option_value "--brewfile" "$#"
        reset_extra_brewfile_specs_for_cli
        append_array_value EXTRA_BREWFILE_SPECS "$2"
        shift 2
        ;;
      --brewfile=*)
        reset_extra_brewfile_specs_for_cli
        append_array_value EXTRA_BREWFILE_SPECS "${1#*=}"
        shift
        ;;
      --brewfiles)
        require_next_option_value "--brewfiles" "$#"
        reset_extra_brewfile_specs_for_cli
        append_csv_to_array EXTRA_BREWFILE_SPECS "$2"
        shift 2
        ;;
      --brewfiles=*)
        reset_extra_brewfile_specs_for_cli
        append_csv_to_array EXTRA_BREWFILE_SPECS "${1#*=}"
        shift
        ;;
      --hostname)
        require_next_option_value "--hostname" "$#"
        AGENTBOX_HOSTNAME_VALUE="$2"
        shift 2
        ;;
      --hostname=*)
        require_inline_option_value "--hostname" "${1#*=}"
        AGENTBOX_HOSTNAME_VALUE="${1#*=}"
        shift
        ;;
      --authorized-key)
        require_next_option_value "--authorized-key" "$#"
        reset_authorized_key_specs_for_cli
        append_array_value AUTHORIZED_KEY_SPECS "$2"
        shift 2
        ;;
      --authorized-key=*)
        require_inline_option_value "--authorized-key" "${1#*=}"
        reset_authorized_key_specs_for_cli
        append_array_value AUTHORIZED_KEY_SPECS "${1#*=}"
        shift
        ;;
      --authorized-keys)
        require_next_option_value "--authorized-keys" "$#"
        reset_authorized_key_specs_for_cli
        append_csv_to_array AUTHORIZED_KEY_SPECS "$2"
        shift 2
        ;;
      --authorized-keys=*)
        require_inline_option_value "--authorized-keys" "${1#*=}"
        reset_authorized_key_specs_for_cli
        append_csv_to_array AUTHORIZED_KEY_SPECS "${1#*=}"
        shift
        ;;
      --tailscale-authkey)
        require_next_option_value "--tailscale-authkey" "$#"
        TAILSCALE_AUTHKEY="$2"
        shift 2
        ;;
      --tailscale-authkey=*)
        require_inline_option_value "--tailscale-authkey" "${1#*=}"
        TAILSCALE_AUTHKEY="${1#*=}"
        shift
        ;;
      --brewgroup)
        require_next_option_value "--brewgroup" "$#"
        BREWGROUP_INPUT="$2"
        shift 2
        ;;
      --brewgroup=*)
        require_inline_option_value "--brewgroup" "${1#*=}"
        BREWGROUP_INPUT="${1#*=}"
        shift
        ;;
      --openclaw-identity)
        require_next_option_value "--openclaw-identity" "$#"
        OPENCLAW_IDENTITY_INPUT="$2"
        shift 2
        ;;
      --openclaw-identity=*)
        require_inline_option_value "--openclaw-identity" "${1#*=}"
        OPENCLAW_IDENTITY_INPUT="${1#*=}"
        shift
        ;;
      --openclaw-password)
        require_next_option_value "--openclaw-password" "$#"
        OPENCLAW_PASSWORD="$2"
        shift 2
        ;;
      --openclaw-password=*)
        require_inline_option_value "--openclaw-password" "${1#*=}"
        OPENCLAW_PASSWORD="${1#*=}"
        shift
        ;;
      --openclaw-auth-choice)
        require_next_option_value "--openclaw-auth-choice" "$#"
        OPENCLAW_AUTH_CHOICE="$2"
        shift 2
        ;;
      --openclaw-auth-choice=*)
        require_inline_option_value "--openclaw-auth-choice" "${1#*=}"
        OPENCLAW_AUTH_CHOICE="${1#*=}"
        shift
        ;;
      --openclaw-auth-env)
        require_next_option_value "--openclaw-auth-env" "$#"
        OPENCLAW_AUTH_ENV="$2"
        shift 2
        ;;
      --openclaw-auth-env=*)
        require_inline_option_value "--openclaw-auth-env" "${1#*=}"
        OPENCLAW_AUTH_ENV="${1#*=}"
        shift
        ;;
      --openclaw-autologin)
        require_next_option_value "--openclaw-autologin" "$#"
        OPENCLAW_AUTOLOGIN="$2"
        shift 2
        ;;
      --openclaw-autologin=*)
        require_inline_option_value "--openclaw-autologin" "${1#*=}"
        OPENCLAW_AUTOLOGIN="${1#*=}"
        shift
        ;;
      --openclaw-gateway-port)
        require_next_option_value "--openclaw-gateway-port" "$#"
        OPENCLAW_GATEWAY_PORT="$2"
        OPENCLAW_GATEWAY_PORT_EXPLICIT="1"
        shift 2
        ;;
      --openclaw-gateway-port=*)
        require_inline_option_value "--openclaw-gateway-port" "${1#*=}"
        OPENCLAW_GATEWAY_PORT="${1#*=}"
        OPENCLAW_GATEWAY_PORT_EXPLICIT="1"
        shift
        ;;
      --force)
        FORCE="1"
        shift
        ;;
      -y | --yes)
        NONINTERACTIVE="1"
        shift
        ;;
      --debug)
        DEBUG="1"
        shift
        ;;
      --version)
        show_version
        ;;
      -h | --help)
        usage
        ;;
      *)
        usage "noexit"
        abort "unrecognized option ${tty_bold}$1${tty_reset}; see usage above."
        ;;
    esac
  done
}

detect_arch() {
  local arch
  arch="$(/usr/bin/uname -m || /usr/bin/arch || uname -m || arch)"
  if [[ "${arch}" == "arm64" ]] || [[ "${arch}" == "aarch64" ]]; then
    DETECTED_ARCH="arm64"
  elif [[ "${arch}" == "x86_64" ]] || [[ "${arch}" == "x64" ]]; then
    DETECTED_ARCH="x64"
  else
    DETECTED_ARCH="${arch}"
  fi
}

detect_os() {
  local os
  os="$(uname)"
  if [[ "${os}" == "Darwin" ]]; then
    DETECTED_OS="macos"
  else
    DETECTED_OS="${os}"
  fi
}

major_minor() {
  local major
  local minor
  local rest

  major="${1%%.*}"
  rest="${1#*.}"
  minor="${rest%%.*}"
  printf "%s.%s" "${major}" "${minor}"
}

version_compare() {
  local left="$1"
  local right="$2"
  local left_major
  local left_minor
  local right_major
  local right_minor

  left_major="${left%%.*}"
  left_minor="${left#*.}"
  left_minor="${left_minor%%.*}"
  right_major="${right%%.*}"
  right_minor="${right#*.}"
  right_minor="${right_minor%%.*}"

  left_minor="${left_minor#0}"
  right_minor="${right_minor#0}"

  if [[ "${left_major}" -lt "${right_major}" ]]; then
    return 1
  fi

  if [[ "${left_major}" -gt "${right_major}" ]]; then
    return 0
  fi

  if [[ "${left_minor:-0}" -lt "${right_minor:-0}" ]]; then
    return 1
  fi

  return 0
}

test_curl() {
  local curl_version_output
  local curl_name_and_version

  if [[ ! -x "$1" ]]; then
    return 1
  fi

  curl_version_output="$("$1" --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  version_compare "$(major_minor "${curl_name_and_version##* }")" "$(major_minor "${REQUIRED_CURL_VERSION}")"
}

agentbox_payload_display() {
  display_home_path "${AGENTBOX_PAYLOAD_DIR}"
}

agentbox_brewfile_display() {
  display_home_path "${AGENTBOX_CORE_BREWFILE}"
}

agentbox_payload_source_display() {
  case "${AGENTBOX_PAYLOAD_SOURCE_KIND:-unresolved}" in
    explicit)
      printf "explicit payload dir"
      ;;
    source)
      printf "source-relative payload"
      ;;
    release)
      printf "release archive %s" "${AGENTBOX_PAYLOAD_RELEASE_TAG}"
      ;;
    *)
      printf "unresolved"
      ;;
  esac
}

repo_archive_url() {
  local tag="$1"

  printf "%s/%s.tar.gz" "${AGENTBOX_REPO_ARCHIVE_BASE_URL}" "${tag}"
}

prepare_agentbox_payload() {
  AGENTBOX_PAYLOAD_DIR=""
  AGENTBOX_PAYLOAD_SOURCE_KIND=""
  AGENTBOX_PAYLOAD_RELEASE_TAG=""
}

resolve_existing_dir_path() (
  local path

  path="$(expand_home_path "$1")"
  if [[ ! -d "${path}" ]]; then
    return 1
  fi

  cd "${path}" 2>/dev/null && pwd -P
)

agentbox_payload_valid() {
  local dir="$1"
  local profile_image_source

  [[ -d "${dir}" ]] || return 1
  [[ -f "${dir}/Brewfile" ]] || return 1
  [[ -f "${dir}/bin/health.sh" ]] || return 1
  [[ -f "${dir}/launchd/dev.tanaab.agentbox.health.plist.in" ]] || return 1
  [[ -f "${dir}/launchd/dev.tanaab.agentbox.tailscaled.plist.in" ]] || return 1
  [[ -f "${dir}/launchd/dev.tanaab.agentbox.openclaw-finalize.plist.in" ]] || return 1
  [[ -f "${dir}/libexec/agentbox-openclaw-finalize.sh" ]] || return 1
  [[ -f "${dir}/assets/default_avatar.png" ]] || return 1

  for profile_image_source in "${dir}"/assets/profile*.png; do
    if [[ -f "${profile_image_source}" ]]; then
      return 0
    fi
  done

  return 1
}

validate_agentbox_payload_dir() {
  local dir="$1"

  if ! agentbox_payload_valid "${dir}"; then
    abort "agentbox payload at ${tty_ts}$(display_home_path "${dir}")${tty_reset} must include Brewfile, bin/health.sh, launchd templates, assets/default_avatar.png, and assets/profile*.png."
  fi
}

agentbox_script_real_path() {
  local link_target
  local script_dir
  local script_path="${0}"

  if [[ "${script_path}" != */* ]]; then
    script_path="$(command -v "${script_path}" 2>/dev/null || true)"
  fi

  if [[ -z "${script_path}" ]]; then
    return 1
  fi

  while [[ -L "${script_path}" ]]; do
    script_dir="$(cd -P "$(dirname "${script_path}")" 2>/dev/null && pwd)" || return 1
    link_target="$(readlink "${script_path}")" || return 1
    case "${link_target}" in
      /*)
        script_path="${link_target}"
        ;;
      *)
        script_path="${script_dir}/${link_target}"
        ;;
    esac
  done

  script_dir="$(cd -P "$(dirname "${script_path}")" 2>/dev/null && pwd)" || return 1
  printf "%s/%s" "${script_dir}" "$(basename "${script_path}")"
}

resolve_source_relative_agentbox_payload() {
  local candidate
  local resolved_candidate
  local script_dir
  local script_path

  script_path="$(agentbox_script_real_path)" || return 1
  script_dir="$(dirname "${script_path}")"

  for candidate in "${script_dir}" "${script_dir}/.." "${script_dir}/../.."; do
    resolved_candidate="$(resolve_existing_dir_path "${candidate}")" || continue
    if agentbox_payload_valid "${resolved_candidate}"; then
      printf "%s" "${resolved_candidate}"
      return 0
    fi
  done

  return 1
}

script_version_release_fetch_allowed() {
  is_semver_value "${SCRIPT_VERSION}" || return 1

  case "${SCRIPT_VERSION}" in
    *-ci.* | *-dev* | *dirty* | *unreleased*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

extract_agentbox_archive_payload() {
  local archive_path="$1"
  local extract_dir="$2"
  local payload_root=""
  local entry
  local entry_count="0"

  execute mkdir -p "${extract_dir}"
  execute tar -xf "${archive_path}" -C "${extract_dir}"

  if agentbox_payload_valid "${extract_dir}"; then
    payload_root="${extract_dir}"
  else
    for entry in "${extract_dir}"/* "${extract_dir}"/.[!.]* "${extract_dir}"/..?*; do
      if [[ ! -e "${entry}" ]]; then
        continue
      fi

      entry_count=$((entry_count + 1))
      payload_root="${entry}"
    done

    if [[ "${entry_count}" != "1" ]] || ! agentbox_payload_valid "${payload_root}"; then
      abort "agentbox archive must contain current agentbox payload files at archive root or inside one top-level directory."
    fi
  fi

  resolve_existing_dir_path "${payload_root}"
}

resolve_release_agentbox_payload() {
  local archive_path
  local archive_url
  local payload_dir

  if ! script_version_release_fetch_allowed; then
    return 1
  fi

  AGENTBOX_PAYLOAD_RELEASE_TAG="$(normalize_release_tag "${SCRIPT_VERSION}")"
  archive_url="$(repo_archive_url "${AGENTBOX_PAYLOAD_RELEASE_TAG}")"
  archive_path="${BOOT_TMPDIR}/agentbox-${AGENTBOX_PAYLOAD_RELEASE_TAG}.tar.gz"
  log "${tty_tp}extracting${tty_reset} ${tty_ts}agentbox${tty_reset} release payload ${tty_ts}${AGENTBOX_PAYLOAD_RELEASE_TAG}${tty_reset}"
  execute "${CURL}" -fsSL "${archive_url}" -o "${archive_path}"
  payload_dir="$(extract_agentbox_archive_payload "${archive_path}" "${BOOT_TMPDIR}/agentbox-release")"

  AGENTBOX_PAYLOAD_DIR="${payload_dir}"
  AGENTBOX_PAYLOAD_SOURCE_KIND="release"
}

resolve_agentbox_payload() {
  local explicit_payload_dir
  local source_payload_dir

  AGENTBOX_PAYLOAD_DIR_INPUT="$(trim_whitespace "${AGENTBOX_PAYLOAD_DIR_INPUT}")"

  if [[ -n "${AGENTBOX_PAYLOAD_DIR_INPUT}" ]]; then
    if ! explicit_payload_dir="$(resolve_existing_dir_path "${AGENTBOX_PAYLOAD_DIR_INPUT}")"; then
      abort "agentbox payload dir ${tty_ts}${AGENTBOX_PAYLOAD_DIR_INPUT}${tty_reset} must resolve to an existing directory."
    fi

    validate_agentbox_payload_dir "${explicit_payload_dir}"
    AGENTBOX_PAYLOAD_DIR="${explicit_payload_dir}"
    AGENTBOX_PAYLOAD_SOURCE_KIND="explicit"
    return 0
  fi

  if source_payload_dir="$(resolve_source_relative_agentbox_payload)"; then
    AGENTBOX_PAYLOAD_DIR="${source_payload_dir}"
    AGENTBOX_PAYLOAD_SOURCE_KIND="source"
    return 0
  fi

  if resolve_release_agentbox_payload; then
    return 0
  fi

  abort "could not resolve an agentbox payload for script version ${tty_ts}${SCRIPT_VERSION}${tty_reset}; run from a source checkout, use a released script version, or set AGENTBOX_PAYLOAD_DIR to a current agentbox checkout."
}

resolve_extra_brewfiles() {
  local brewfile
  local resolved_brewfile

  RESOLVED_EXTRA_BREWFILES=()

  if ! array_has_values EXTRA_BREWFILE_SPECS; then
    return 0
  fi

  for brewfile in "${EXTRA_BREWFILE_SPECS[@]}"; do
    if brewfile_source_url_value "${brewfile}"; then
      RESOLVED_EXTRA_BREWFILES+=("${brewfile}")
      continue
    fi

    if ! resolved_brewfile="$(resolve_extra_brewfile_source_path "${brewfile}")"; then
      abort "extra Brewfile ${tty_ts}${brewfile}${tty_reset} must be a url or resolve to a local file relative to ${tty_ts}$(display_home_path "${INVOCATION_CWD}")${tty_reset} or ${tty_ts}$(agentbox_payload_display)${tty_reset}."
    fi

    RESOLVED_EXTRA_BREWFILES+=("${resolved_brewfile}")
  done
}

discover_agentbox_payload() {
  local profile_image_source

  AGENTBOX_CORE_BREWFILE="${AGENTBOX_PAYLOAD_DIR}/Brewfile"
  AGENTBOX_BIN_DIR="${AGENTBOX_PAYLOAD_DIR}/bin"
  AGENTBOX_LAUNCHD_DIR="${AGENTBOX_PAYLOAD_DIR}/launchd"
  AGENTBOX_LIBEXEC_DIR="${AGENTBOX_PAYLOAD_DIR}/libexec"
  AGENTBOX_ASSETS_DIR="${AGENTBOX_PAYLOAD_DIR}/assets"
  AGENTBOX_HEALTH_SCRIPT_SOURCE="${AGENTBOX_BIN_DIR}/health.sh"
  AGENTBOX_HEALTH_PLIST_TEMPLATE="${AGENTBOX_LAUNCHD_DIR}/dev.tanaab.agentbox.health.plist.in"
  AGENTBOX_TAILSCALED_PLIST_TEMPLATE="${AGENTBOX_LAUNCHD_DIR}/dev.tanaab.agentbox.tailscaled.plist.in"
  AGENTBOX_OPENCLAW_FINALIZER_PLIST_TEMPLATE="${AGENTBOX_LAUNCHD_DIR}/dev.tanaab.agentbox.openclaw-finalize.plist.in"
  AGENTBOX_OPENCLAW_FINALIZER_SOURCE="${AGENTBOX_LIBEXEC_DIR}/agentbox-openclaw-finalize.sh"
  AGENTBOX_DEFAULT_AVATAR_SOURCE="${AGENTBOX_ASSETS_DIR}/default_avatar.png"
  AGENTBOX_PROFILE_IMAGE_SOURCES=()
  AGENTBOX_PROFILE_IMAGE_SOURCE=""

  if [[ ! -f "${AGENTBOX_CORE_BREWFILE}" ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required Brewfile ${tty_ts}$(agentbox_brewfile_display)${tty_reset}."
  fi

  if [[ ! -f "${AGENTBOX_HEALTH_SCRIPT_SOURCE}" ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_HEALTH_SCRIPT_SOURCE}")${tty_reset}; use a current agentbox checkout or release payload that includes bin/ and launchd/."
  fi

  if [[ ! -f "${AGENTBOX_HEALTH_PLIST_TEMPLATE}" ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_HEALTH_PLIST_TEMPLATE}")${tty_reset}; use a current agentbox checkout or release payload that includes bin/ and launchd/."
  fi

  if [[ ! -f "${AGENTBOX_TAILSCALED_PLIST_TEMPLATE}" ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_TAILSCALED_PLIST_TEMPLATE}")${tty_reset}; use a current agentbox checkout or release payload that includes bin/ and launchd/."
  fi

  if [[ ! -f "${AGENTBOX_OPENCLAW_FINALIZER_PLIST_TEMPLATE}" || ! -f "${AGENTBOX_OPENCLAW_FINALIZER_SOURCE}" ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing the openclaw Aqua finalizer assets; use a current agentbox checkout or release payload that includes launchd/ and libexec/."
  fi

  if [[ ! -f "${AGENTBOX_DEFAULT_AVATAR_SOURCE}" ]]; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required runtime asset ${tty_ts}assets/default_avatar.png${tty_reset}; use a current agentbox checkout or release payload that includes the bundled default avatar."
  fi

  for profile_image_source in "${AGENTBOX_ASSETS_DIR}"/profile*.png; do
    if [[ -f "${profile_image_source}" ]]; then
      AGENTBOX_PROFILE_IMAGE_SOURCES+=("${profile_image_source}")
    fi
  done

  if ! array_has_values AGENTBOX_PROFILE_IMAGE_SOURCES; then
    abort "agentbox payload at ${tty_ts}$(agentbox_payload_display)${tty_reset} is missing required runtime assets ${tty_ts}assets/profile*.png${tty_reset}; use a current agentbox checkout or release payload that includes bundled profile images."
  fi

  select_openclaw_profile_image_source
}

warn_if_xcode_clt_missing() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "xcode command line tools may need to be installed before developer tools work correctly."
  fi
}

run_agentbox_hostname_setup() {
  if macos_identity_matches; then
    log "${tty_tp}skipping${tty_reset} macos system identity; already set to ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}setting${tty_reset} macos system identity to ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
  execute sudo scutil --set ComputerName "${AGENTBOX_HOSTNAME_VALUE}"
  execute sudo scutil --set HostName "${AGENTBOX_HOSTNAME_VALUE}"
  execute sudo scutil --set LocalHostName "${AGENTBOX_HOSTNAME_VALUE}"
}

scutil_value_matches() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(scutil --get "${key}" 2>/dev/null || true)"
  [[ "${actual}" == "${expected}" ]]
}

macos_identity_matches() {
  scutil_value_matches ComputerName "${AGENTBOX_HOSTNAME_VALUE}" &&
    scutil_value_matches HostName "${AGENTBOX_HOSTNAME_VALUE}" &&
    scutil_value_matches LocalHostName "${AGENTBOX_HOSTNAME_VALUE}"
}

pmset_setting_value() {
  local key="$1"

  pmset -g custom 2>/dev/null | awk -v key="${key}" '$1 == key { value = $2 } END { if (value != "") print value }'
}

ensure_pmset_setting() {
  local key="$1"
  local desired="$2"
  local optional="${3:-0}"
  local current

  current="$(pmset_setting_value "${key}")"
  if [[ "${current}" == "${desired}" ]]; then
    log "${tty_tp}skipping${tty_reset} ${tty_ts}pmset ${key}${tty_reset}; already ${tty_ts}${desired}${tty_reset}"
    return 0
  fi

  if [[ "${optional}" == "1" ]]; then
    debug "${tty_tp}running${tty_reset}" sudo pmset -a "${key}" "${desired}"
    if ! sudo pmset -a "${key}" "${desired}"; then
      warn "could not set pmset ${key}=${desired} on this mac; continuing."
    fi
    return 0
  fi

  execute sudo pmset -a "${key}" "${desired}"
}

systemsetup_toggle_enabled() {
  local getter="$1"

  sudo systemsetup "${getter}" 2>/dev/null | awk -F': ' 'NF { value = $NF } END { exit (tolower(value) == "on" ? 0 : 1) }'
}

ensure_systemsetup_enabled() {
  local getter="$1"
  local setter="$2"
  local label="$3"

  if systemsetup_toggle_enabled "${getter}"; then
    log "${tty_tp}skipping${tty_reset} ${tty_ts}${label}${tty_reset}; already enabled"
    return 0
  fi

  execute sudo systemsetup "${setter}" on
}

firewall_global_enabled() {
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -qi "enabled"
}

warn_if_tailscale_firewall_enabled() {
  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" != "serve" ]]; then
    return 0
  fi

  if firewall_global_enabled; then
    warn "macos application firewall is enabled; this can prevent tailscale serve https from reaching the openclaw gateway over the tailnet."
    warn "agentbox recommends disabling macos application firewall for tailnet gateway access and relying on tailscale acls, no wan port forwarding, ssh hardening, and loopback gateway binding."
  fi
}

run_agentbox_macos_settings() {
  log "${tty_tp}applying${tty_reset} headless macos power, time, and recovery settings"

  ensure_pmset_setting sleep 0
  ensure_pmset_setting disksleep 0
  ensure_pmset_setting displaysleep 0
  ensure_pmset_setting powernap 0 1
  ensure_pmset_setting autorestart 1
  ensure_systemsetup_enabled -getusingnetworktime -setusingnetworktime "network time"
  ensure_systemsetup_enabled -getrestartfreeze -setrestartfreeze "restart after freeze"
  warn_if_tailscale_firewall_enabled
}

user_home_dir() {
  local user="$1"

  dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | awk '/NFSHomeDirectory:/ {print $2; exit}'
}

user_primary_group() {
  local user="$1"

  id -gn "${user}" 2>/dev/null || printf "staff"
}

user_exists() {
  dscl . -read "/Users/$1" >/dev/null 2>&1
}

group_exists() {
  dscl . -read "/Groups/$1" >/dev/null 2>&1
}

group_has_user() {
  local group="$1"
  local user="$2"

  dscl . -read "/Groups/${group}" GroupMembership 2>/dev/null | awk -v expected="${user}" '
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
  '
}

user_is_admin() {
  group_has_user admin "$1"
}

validate_openclaw_user_non_admin() {
  if [[ "${OPENCLAW_USER}" == "root" ]]; then
    abort "openclaw runner user must not be ${tty_ts}root${tty_reset}."
  fi

  if [[ -n "${ADMIN_USER}" && "${OPENCLAW_USER}" == "${ADMIN_USER}" ]]; then
    abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} must be separate from the invoking sudo user."
  fi

  if user_is_admin "${OPENCLAW_USER}"; then
    abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} must not be an admin or sudo-capable user."
  fi
}

validate_existing_openclaw_user() {
  if ! user_exists "${OPENCLAW_USER}"; then
    return 0
  fi

  validate_openclaw_user_non_admin
}

autologin_user_value() {
  /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
}

openclaw_autologin_configured() {
  [[ "$(autologin_user_value)" == "${OPENCLAW_USER}" ]]
}

filevault_state_value() {
  local status

  if ! status="$(/usr/bin/fdesetup status 2>/dev/null)"; then
    printf 'unknown'
    return 0
  fi

  case "${status}" in
    "FileVault is On."*) printf 'enabled' ;;
    "FileVault is Off."*) printf 'disabled' ;;
    *) printf 'unknown' ;;
  esac
}

validate_openclaw_autologin_preflight() {
  local configured_user
  local filevault_state

  if ! openclaw_autologin_enabled; then
    return 0
  fi

  filevault_state="$(filevault_state_value)"
  case "${filevault_state}" in
    enabled)
      abort_multi "$(cat <<EOABORT
FileVault is enabled, so macos cannot provide unattended runtime-user autologin after a cold boot.
disable FileVault deliberately before using the default unattended recovery profile, or rerun with ${tty_bold}--openclaw-autologin off${tty_reset} and accept a graphical login after each reboot.
EOABORT
)"
      ;;
    unknown)
      abort_multi "$(cat <<EOABORT
agentbox could not determine FileVault status, so it cannot safely promise unattended runtime-user autologin.
verify ${tty_bold}fdesetup status${tty_reset}, or rerun with ${tty_bold}--openclaw-autologin off${tty_reset} and accept a graphical login after each reboot.
EOABORT
)"
      ;;
  esac

  configured_user="$(autologin_user_value)"
  if [[ -n "${configured_user}" && "${configured_user}" != "${OPENCLAW_USER}" ]]; then
    abort_multi "$(cat <<EOABORT
macos autologin is already configured for ${tty_ts}${configured_user}${tty_reset}; agentbox will not replace login-window state owned by another account.
rerun with ${tty_bold}--openclaw-autologin off${tty_reset}, or deliberately disable the existing autologin configuration before rerunning.
EOABORT
)"
  fi
}

openclaw_password_required() {
  if ! user_exists "${OPENCLAW_USER}"; then
    return 0
  fi

  if openclaw_autologin_enabled && ! openclaw_autologin_configured; then
    return 0
  fi

  return 1
}

abort_missing_openclaw_password() {
  local reason="$1"

abort_multi "$(cat <<EOABORT
openclaw runner password is required to ${reason}.
set ${tty_bold}AGENTBOX_OPENCLAW_PASSWORD${tty_reset}, pass ${tty_bold}--openclaw-password${tty_reset}, or rerun interactively so agentbox can prompt without echoing the password.
EOABORT
)"
}

prompt_for_openclaw_password() {
  local reason="$1"
  local password=""
  local confirm=""
  local input_path

  if [[ -n "${OPENCLAW_PASSWORD}" ]]; then
    return 0
  fi

  if [[ -n "${NONINTERACTIVE-}" || -n "${CI-}" ]]; then
    abort_missing_openclaw_password "${reason}"
  fi

  input_path="$(interactive_tty_input)"

  printf "enter password for openclaw runner %s to %s: " "${tty_ts}${OPENCLAW_USER}${tty_reset}" "${reason}" >&2
  IFS= read -r -s password < "${input_path}"
  printf "\n" >&2
  printf "confirm password for openclaw runner %s: " "${tty_ts}${OPENCLAW_USER}${tty_reset}" >&2
  IFS= read -r -s confirm < "${input_path}"
  printf "\n" >&2

  if [[ -z "${password}" ]]; then
    abort "openclaw runner password must not be empty."
  fi

  if [[ "${password}" != "${confirm}" ]]; then
    abort "openclaw runner password confirmation did not match."
  fi

  OPENCLAW_PASSWORD="${password}"
}

ensure_openclaw_password_available() {
  local reason="$1"

  if [[ -n "${OPENCLAW_PASSWORD}" ]]; then
    return 0
  fi

  prompt_for_openclaw_password "${reason}"
}

write_openclaw_profile_image() {
  debug raw AGENTBOX_PROFILE_IMAGE_SOURCE="$(display_home_path "${AGENTBOX_PROFILE_IMAGE_SOURCE}")"
  execute sudo mkdir -p "${AGENTBOX_OPT_DIR}"
  execute sudo cp "${AGENTBOX_PROFILE_IMAGE_SOURCE}" "${AGENTBOX_PROFILE_IMAGE_PATH}"
  execute sudo chown root:wheel "${AGENTBOX_PROFILE_IMAGE_PATH}"
  execute sudo chmod 644 "${AGENTBOX_PROFILE_IMAGE_PATH}"
}

openclaw_user_has_picture() {
  dscl . -read "/Users/${OPENCLAW_USER}" Picture >/dev/null 2>&1 ||
    dscl . -read "/Users/${OPENCLAW_USER}" JPEGPhoto >/dev/null 2>&1
}

ensure_openclaw_user_picture() {
  if openclaw_user_has_picture; then
    log "${tty_tp}preserving${tty_reset} existing profile picture for openclaw runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
    return 0
  fi

  write_openclaw_profile_image
  log "${tty_tp}setting${tty_reset} profile picture for openclaw runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  execute sudo dscl . -create "/Users/${OPENCLAW_USER}" Picture "${AGENTBOX_PROFILE_IMAGE_PATH}"
}

ensure_openclaw_user_home_ownership() {
  local home="$1"
  local recursive="${2:-0}"
  local primary_group
  local owner
  local group
  local mode

  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  owner="$(stat -f "%Su" "${home}" 2>/dev/null || true)"
  group="$(stat -f "%Sg" "${home}" 2>/dev/null || true)"

  if [[ "${owner}" != "${OPENCLAW_USER}" || "${group}" != "${primary_group}" ]]; then
    if [[ "${recursive}" == "1" ]]; then
      execute sudo chown -R "${OPENCLAW_USER}:${primary_group}" "${home}"
    else
      execute sudo chown "${OPENCLAW_USER}:${primary_group}" "${home}"
    fi
  fi

  mode="$(stat -f "%Lp" "${home}" 2>/dev/null || true)"
  if [[ -n "${mode}" ]] && (( (8#${mode} & 8#022) != 0 )); then
    execute sudo chmod go-w "${home}"
  fi
}

ensure_openclaw_user_home() {
  local home
  local expected_home
  local created_home="0"

  home="$(user_home_dir "${OPENCLAW_USER}")"
  expected_home="/Users/${OPENCLAW_USER}"

  if [[ -z "${home}" ]]; then
    abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} does not have a configured home directory."
  fi

  if [[ ! -d "${home}" ]]; then
    if [[ "${home}" != "${expected_home}" ]]; then
      abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} has missing home directory ${tty_ts}${home}${tty_reset}; create it manually or set the account home to ${tty_ts}${expected_home}${tty_reset} and rerun."
    fi

    log "${tty_tp}creating${tty_reset} openclaw runner home directory ${tty_ts}${home}${tty_reset}"
    debug "${tty_tp}running${tty_reset}" sudo /usr/sbin/createhomedir -c -u "${OPENCLAW_USER}"
    if ! sudo /usr/sbin/createhomedir -c -u "${OPENCLAW_USER}"; then
      abort "failed to create openclaw runner home directory ${tty_ts}${home}${tty_reset}."
    fi
    created_home="1"
  fi

  if [[ ! -d "${home}" ]]; then
    log "${tty_tp}creating${tty_reset} openclaw runner home directory ${tty_ts}${home}${tty_reset} after createhomedir did not materialize it"
    execute sudo mkdir -p "${home}"
    created_home="1"
  fi

  ensure_openclaw_user_home_ownership "${home}" "${created_home}"

  if [[ ! -d "${home}" ]]; then
    abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} must have a usable home directory."
  fi
}

create_openclaw_user() {
  ensure_openclaw_password_available "create the openclaw runner user"
  write_openclaw_profile_image

  log "${tty_tp}creating${tty_reset} openclaw runner user ${tty_ts}${OPENCLAW_FULL_NAME} <${OPENCLAW_USER}>${tty_reset}"
  debug "${tty_tp}running${tty_reset}" sudo sysadminctl -addUser "${OPENCLAW_USER}" -fullName "${OPENCLAW_FULL_NAME}" -shell /bin/zsh -home "/Users/${OPENCLAW_USER}" -password "****" -picture "${AGENTBOX_PROFILE_IMAGE_PATH}"
  if ! sudo sysadminctl -addUser "${OPENCLAW_USER}" -fullName "${OPENCLAW_FULL_NAME}" -shell /bin/zsh -home "/Users/${OPENCLAW_USER}" -password "${OPENCLAW_PASSWORD}" -picture "${AGENTBOX_PROFILE_IMAGE_PATH}"; then
    if user_exists "${OPENCLAW_USER}"; then
      warn "sysadminctl returned a nonzero status after creating openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset}; continuing with account verification."
    else
      abort "failed to create openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset}."
    fi
  fi
}

ensure_openclaw_autologin() {
  if ! openclaw_autologin_enabled; then
    log "${tty_tp}skipping${tty_reset} openclaw runner autologin because ${tty_ts}--openclaw-autologin off${tty_reset} was selected"
    if openclaw_autologin_configured; then
      warn "${OPENCLAW_USER} is already the configured autologin user; agentbox preserves existing login-window state when autologin is opted out."
    fi
    return 0
  fi

  if openclaw_autologin_configured; then
    log "${tty_tp}skipping${tty_reset} openclaw runner autologin; ${tty_ts}${OPENCLAW_USER}${tty_reset} is already configured"
    return 0
  fi

  ensure_openclaw_password_available "configure openclaw runner autologin"

  log "${tty_tp}configuring${tty_reset} openclaw runner autologin for ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  debug "${tty_tp}running${tty_reset}" sudo sysadminctl -autologin set -userName "${OPENCLAW_USER}" -password "****"
  if ! sudo sysadminctl -autologin set -userName "${OPENCLAW_USER}" -password "${OPENCLAW_PASSWORD}"; then
    abort "macos policy or sysadminctl prevented autologin for ${tty_ts}${OPENCLAW_USER}${tty_reset}; rerun with ${tty_bold}--openclaw-autologin off${tty_reset} and accept manual graphical login after each reboot, or change the machine policy deliberately."
  fi

  if ! openclaw_autologin_configured; then
    abort "openclaw runner autologin did not become active for ${tty_ts}${OPENCLAW_USER}${tty_reset}; rerun with ${tty_bold}--openclaw-autologin off${tty_reset} and accept manual graphical login after each reboot, or change the machine policy deliberately."
  fi
}

run_agentbox_openclaw_user_setup() {
  check_sudo_access "before openclaw runner user setup"

  if user_exists "${OPENCLAW_USER}"; then
    log "${tty_tp}reusing${tty_reset} existing openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  else
    create_openclaw_user
  fi

  validate_existing_openclaw_user
  ensure_openclaw_user_home
  ensure_openclaw_user_picture
  ensure_openclaw_autologin
  OPENCLAW_PASSWORD=""
}

private_key_material_detected() {
  [[ "${1}" == *"PRIVATE KEY"* ]]
}

authorized_key_line_valid() {
  local line="$1"
  local key_type
  local rest
  local key_body

  if private_key_material_detected "${line}"; then
    return 1
  fi

  key_type="${line%%[[:space:]]*}"
  if [[ "${key_type}" == "${line}" ]]; then
    return 1
  fi

  rest="${line#*[[:space:]]}"
  key_body="${rest%%[[:space:]]*}"
  if [[ -z "${key_body}" ]]; then
    return 1
  fi

  case "${key_type}" in
    ssh-ed25519 | ssh-ed25519-cert-v01@openssh.com | ssh-rsa | ssh-rsa-cert-v01@openssh.com | \
      ecdsa-sha2-nistp256 | ecdsa-sha2-nistp256-cert-v01@openssh.com | \
      ecdsa-sha2-nistp384 | ecdsa-sha2-nistp384-cert-v01@openssh.com | \
      ecdsa-sha2-nistp521 | ecdsa-sha2-nistp521-cert-v01@openssh.com | \
      sk-ssh-ed25519@openssh.com | sk-ssh-ed25519-cert-v01@openssh.com | \
      sk-ecdsa-sha2-nistp256@openssh.com | sk-ecdsa-sha2-nistp256-cert-v01@openssh.com)
      ;;
    *)
      return 1
      ;;
  esac

  [[ "${key_body}" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]
}

append_authorized_key_line() {
  local line="$1"
  local existing

  if array_has_values AUTHORIZED_KEY_LINES; then
    for existing in "${AUTHORIZED_KEY_LINES[@]}"; do
      if [[ "${existing}" == "${line}" ]]; then
        return 0
      fi
    done
  fi

  AUTHORIZED_KEY_LINES+=("${line}")
}

resolve_authorized_key_file() {
  local spec="$1"
  local path="$2"
  local line
  local found_count="0"

  if [[ ! -f "${path}" ]]; then
    abort "authorized key file ${tty_ts}${path}${tty_reset} from ${tty_ts}${spec}${tty_reset} does not exist."
  fi

  if [[ ! -r "${path}" ]]; then
    abort "authorized key file ${tty_ts}${path}${tty_reset} from ${tty_ts}${spec}${tty_reset} is not readable."
  fi

  if grep -q "PRIVATE KEY" "${path}"; then
    abort "authorized key file ${tty_ts}${path}${tty_reset} appears to contain private key material."
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(trim_whitespace "${line}")"
    if [[ -z "${line}" || "${line}" == \#* ]]; then
      continue
    fi

    if ! authorized_key_line_valid "${line}"; then
      abort "authorized key file ${tty_ts}${path}${tty_reset} contains an invalid public key line."
    fi

    append_authorized_key_line "${line}"
    found_count=$((found_count + 1))
  done < "${path}"

  if [[ "${found_count}" -eq 0 ]]; then
    abort "authorized key file ${tty_ts}${path}${tty_reset} did not contain any public keys."
  fi
}

resolve_authorized_key_spec() {
  local spec="$1"
  local value
  local path

  value="$(trim_whitespace "${spec}")"
  if [[ -z "${value}" ]]; then
    abort "authorized key values must not be empty."
  fi

  if private_key_material_detected "${value}"; then
    abort "authorized key value appears to contain private key material."
  fi

  if [[ "${value}" == file:* ]]; then
    path="$(expand_home_path "${value#file:}")"
    resolve_authorized_key_file "${value}" "${path}"
    return 0
  fi

  path="$(expand_home_path "${value}")"
  if [[ -f "${path}" ]]; then
    resolve_authorized_key_file "${value}" "${path}"
    return 0
  fi

  if authorized_key_line_valid "${value}"; then
    append_authorized_key_line "${value}"
    return 0
  fi

  if [[ "${value}" == */* || "${value}" == \~/* || "${value}" == *.pub ]]; then
    abort "authorized key file ${tty_ts}${path}${tty_reset} does not exist."
  fi

  abort "authorized key value must be a public key line or readable public-key file path."
}

resolve_authorized_key_specs() {
  local spec

  AUTHORIZED_KEY_LINES=()
  if ! array_has_values AUTHORIZED_KEY_SPECS; then
    return 0
  fi

  for spec in "${AUTHORIZED_KEY_SPECS[@]}"; do
    resolve_authorized_key_spec "${spec}"
  done
}

install_authorized_keys_for_user() {
  local user="$1"
  local home
  local authorized_keys
  local key
  local installed_count="0"

  home="$(user_home_dir "${user}")"
  if [[ -z "${home}" ]]; then
    abort "could not determine home directory for user ${tty_ts}${user}${tty_reset}."
  fi

  authorized_keys="${home}/.ssh/authorized_keys"
  execute sudo mkdir -p "${home}/.ssh"
  execute sudo chown "${user}:staff" "${home}/.ssh"
  execute sudo chmod 700 "${home}/.ssh"
  execute sudo touch "${authorized_keys}"
  execute sudo chown "${user}:staff" "${authorized_keys}"
  execute sudo chmod 600 "${authorized_keys}"

  if array_has_values AUTHORIZED_KEY_LINES; then
    while IFS= read -r key || [[ -n "${key}" ]]; do
      key="$(trim_whitespace "${key}")"
      if [[ -z "${key}" || "${key}" == \#* ]]; then
        continue
      fi

      if ! sudo grep -qxF -- "${key}" "${authorized_keys}"; then
        printf "%s\n" "${key}" | sudo tee -a "${authorized_keys}" >/dev/null
        installed_count=$((installed_count + 1))
      fi
    done < <(printf "%s\n" "${AUTHORIZED_KEY_LINES[@]}")
  fi

  execute sudo chown "${user}:staff" "${authorized_keys}"
  execute sudo chmod 600 "${authorized_keys}"
  log "${tty_tp}installed${tty_reset} ${installed_count} new ssh authorized key entries for ${tty_ts}${user}${tty_reset}"
}

remote_login_enabled() {
  sudo systemsetup -getremotelogin 2>/dev/null | grep -Fq "Remote Login: On"
}

ensure_remote_login_access_user() {
  local user="$1"

  if ! group_exists "${SSH_ACCESS_GROUP}"; then
    log "${tty_tp}skipping${tty_reset} macos remote login access group update; ${tty_ts}${SSH_ACCESS_GROUP}${tty_reset} does not exist"
    return 0
  fi

  if group_has_user "${SSH_ACCESS_GROUP}" "${user}"; then
    log "${tty_tp}skipping${tty_reset} macos remote login access; ${tty_ts}${user}${tty_reset} is already a direct member of ${tty_ts}${SSH_ACCESS_GROUP}${tty_reset}"
    return 0
  fi

  log "${tty_tp}adding${tty_reset} ${tty_ts}${user}${tty_reset} to macos remote login access group ${tty_ts}${SSH_ACCESS_GROUP}${tty_reset}"
  execute sudo dseditgroup -o edit -a "${user}" -t user "${SSH_ACCESS_GROUP}"

  if ! group_has_user "${SSH_ACCESS_GROUP}" "${user}"; then
    abort "user ${tty_ts}${user}${tty_reset} is still not a direct member of macos remote login access group ${tty_ts}${SSH_ACCESS_GROUP}${tty_reset} after remediation."
  fi
}

ensure_remote_login_access_users() {
  ensure_remote_login_access_user "${ADMIN_USER}"
  ensure_remote_login_access_user "${OPENCLAW_USER}"
}

sshd_config_drop_in_supported() {
  [[ -f "${SSHD_CONFIG_PATH}" ]] && grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*([[:space:]]|$)' "${SSHD_CONFIG_PATH}"
}

restore_agentbox_sshd_config() {
  local backup_path="$1"

  if [[ -n "${backup_path}" && -f "${backup_path}" ]]; then
    sudo cp "${backup_path}" "${SSHD_AGENTBOX_CONFIG_PATH}"
    sudo chown root:wheel "${SSHD_AGENTBOX_CONFIG_PATH}"
    sudo chmod 644 "${SSHD_AGENTBOX_CONFIG_PATH}"
  else
    sudo rm -f "${SSHD_AGENTBOX_CONFIG_PATH}"
  fi
}

sshd_effective_config_hardened() {
  local allowed_users="$1"
  local config
  local user
  local -a users=()

  config="$(sudo "${SSHD_BIN}" -T 2>/dev/null)" || {
    debug "${tty_tp}missing${tty_reset}" sshd effective config output
    return 1
  }

  if ! printf "%s\n" "${config}" | grep -Fxq "passwordauthentication no"; then
    debug "${tty_tp}missing${tty_reset}" sshd effective config line: "passwordauthentication no"
    return 1
  fi

  if ! printf "%s\n" "${config}" | grep -Fxq "kbdinteractiveauthentication no"; then
    debug "${tty_tp}missing${tty_reset}" sshd effective config line: "kbdinteractiveauthentication no"
    return 1
  fi

  if ! printf "%s\n" "${config}" | grep -Fxq "permitrootlogin no"; then
    debug "${tty_tp}missing${tty_reset}" sshd effective config line: "permitrootlogin no"
    return 1
  fi

  if ! printf "%s\n" "${config}" | grep -Fxq "pubkeyauthentication yes"; then
    debug "${tty_tp}missing${tty_reset}" sshd effective config line: "pubkeyauthentication yes"
    return 1
  fi

  IFS=' ' read -r -a users <<< "${allowed_users}"
  for user in "${users[@]}"; do
    if [[ -z "${user}" ]]; then
      continue
    fi

    if ! printf "%s\n" "${config}" | grep -Fxq "allowusers ${user}"; then
      debug "${tty_tp}missing${tty_reset}" sshd effective config line: "allowusers ${user}"
      return 1
    fi
  done
}

harden_sshd_for_users() {
  local allowed_users="$1"
  local backup_path=""

  if [[ ! -x "${SSHD_BIN}" ]]; then
    abort "sshd binary not found at ${tty_ts}${SSHD_BIN}${tty_reset}."
  fi

  if ! sshd_config_drop_in_supported; then
    abort "sshd config drop-ins are not enabled in ${tty_ts}${SSHD_CONFIG_PATH}${tty_reset}; cannot safely install agentbox ssh hardening."
  fi

  if sudo test -e "${SSHD_AGENTBOX_CONFIG_PATH}"; then
    backup_path="${BOOT_TMPDIR}/agentbox.sshd_config.backup"
    execute sudo cp "${SSHD_AGENTBOX_CONFIG_PATH}" "${backup_path}"
  fi

  log "${tty_tp}hardening${tty_reset} ssh for key-only access by ${tty_ts}${allowed_users}${tty_reset}"
  execute sudo mkdir -p "${SSHD_CONFIG_DIR}"
  if ! sudo tee "${SSHD_AGENTBOX_CONFIG_PATH}" >/dev/null <<EOSSHD
# Managed by agentbox.
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers ${allowed_users}
EOSSHD
  then
    abort "failed to write agentbox sshd config."
  fi

  execute sudo chown root:wheel "${SSHD_AGENTBOX_CONFIG_PATH}"
  execute sudo chmod 644 "${SSHD_AGENTBOX_CONFIG_PATH}"

  if ! sudo "${SSHD_BIN}" -t; then
    restore_agentbox_sshd_config "${backup_path}"
    abort "agentbox sshd hardening config failed syntax validation; changes were rolled back."
  fi

  if ! sshd_effective_config_hardened "${allowed_users}"; then
    restore_agentbox_sshd_config "${backup_path}"
    abort "agentbox sshd hardening config did not become effective; changes were rolled back."
  fi

  execute sudo launchctl kickstart -k system/com.openssh.sshd
}

run_agentbox_ssh_setup() {
  local ssh_allowed_users="${ADMIN_USER} ${OPENCLAW_USER}"

  if remote_login_enabled; then
    log "${tty_tp}skipping${tty_reset} classic ssh enablement; remote login is already on"
  else
    log "${tty_tp}enabling${tty_reset} classic ssh for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
    execute sudo systemsetup -setremotelogin on
  fi

  ensure_remote_login_access_users

  if array_has_values AUTHORIZED_KEY_LINES; then
    install_authorized_keys_for_user "${ADMIN_USER}"
    install_authorized_keys_for_user "${OPENCLAW_USER}"
    harden_sshd_for_users "${ssh_allowed_users}"
  else
    log "${tty_tp}skipping${tty_reset} ssh authorized key install because no keys were provided"
    warn "classic ssh is enabled, but key-based access and password-login hardening were not configured by this bootstrap run."
  fi
}

write_agentbox_health_state() {
  local tailscale_enabled="1"
  local brewgroup_enabled="1"
  local brewgroup_value="${BREWGROUP_VALUE}"
  local trusted_brewgroup_enabled_value="0"
  local trusted_brewgroup_value="off"
  local ssh_hardening_expected="0"
  local openclaw_autologin_expected="0"
  local managed_macos_runner="0"
  local ssh_allowed_users="${ADMIN_USER} ${OPENCLAW_USER}"

  if tailscale_setup_disabled; then
    tailscale_enabled="0"
  fi

  if brewgroup_setup_disabled; then
    brewgroup_enabled="0"
    brewgroup_value="off"
  elif trusted_brewgroup_enabled; then
    trusted_brewgroup_enabled_value="1"
    trusted_brewgroup_value="${TRUSTED_BREWGROUP_VALUE}"
  fi

  if array_has_values AUTHORIZED_KEY_LINES; then
    ssh_hardening_expected="1"
  fi

  if openclaw_autologin_enabled; then
    openclaw_autologin_expected="1"
  fi

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    managed_macos_runner="1"
  fi

  if ! sudo tee "${AGENTBOX_HEALTH_STATE_PATH}" >/dev/null <<EOHEALTHSTATE
# Managed by agentbox.
AGENTBOX_HEALTH_AGENTBOX_VERSION=$(shell_quote "${SCRIPT_VERSION}")
AGENTBOX_HEALTH_EXPECTED_HOSTNAME=$(shell_quote "${AGENTBOX_HOSTNAME_VALUE}")
AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME=$(shell_quote "${TAILSCALE_HOSTNAME_VALUE}")
AGENTBOX_HEALTH_TAILSCALE_ENABLED=${tailscale_enabled}
AGENTBOX_HEALTH_BREWGROUP_ENABLED=${brewgroup_enabled}
AGENTBOX_HEALTH_BREWGROUP=$(shell_quote "${brewgroup_value}")
AGENTBOX_HEALTH_TRUSTED_BREWGROUP_ENABLED=${trusted_brewgroup_enabled_value}
AGENTBOX_HEALTH_TRUSTED_BREWGROUP=$(shell_quote "${trusted_brewgroup_value}")
AGENTBOX_HEALTH_BREW_PREFIX=$(shell_quote "${BREW_PREFIX_VALUE}")
AGENTBOX_HEALTH_HOMEBREW_PATHS_FILE=$(shell_quote "${AGENTBOX_HOMEBREW_PATHS_FILE}")
AGENTBOX_HEALTH_ADMIN_USER=$(shell_quote "${ADMIN_USER}")
AGENTBOX_HEALTH_OPENCLAW_USER=$(shell_quote "${OPENCLAW_USER}")
AGENTBOX_HEALTH_OPENCLAW_FULL_NAME=$(shell_quote "${OPENCLAW_FULL_NAME}")
AGENTBOX_HEALTH_OPENCLAW_AUTOLOGIN_EXPECTED=${openclaw_autologin_expected}
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_LABEL=$(shell_quote "${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}")
AGENTBOX_HEALTH_OPENCLAW_FINALIZER_LABEL=$(shell_quote "${AGENTBOX_OPENCLAW_FINALIZER_LABEL}")
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_BIND=$(shell_quote "${OPENCLAW_GATEWAY_BIND_VALUE}")
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_TAILSCALE_MODE=$(shell_quote "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}")
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_PORT=$(shell_quote "${OPENCLAW_GATEWAY_PORT}")
AGENTBOX_HEALTH_OPENCLAW_AUTH_CHOICE=$(shell_quote "${OPENCLAW_AUTH_CHOICE}")
AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED=${ssh_hardening_expected}
AGENTBOX_HEALTH_SSH_ALLOWED_USERS=$(shell_quote "${ssh_allowed_users}")
AGENTBOX_HEALTH_MANAGED_MACOS_RUNNER=${managed_macos_runner}
EOHEALTHSTATE
  then
    abort "failed to write agentbox health state."
  fi

  execute sudo chown root:wheel "${AGENTBOX_HEALTH_STATE_PATH}"
  execute sudo chmod 600 "${AGENTBOX_HEALTH_STATE_PATH}"
}

write_agentbox_health_script() {
  execute sudo cp "${AGENTBOX_HEALTH_SCRIPT_SOURCE}" "${AGENTBOX_OPT_DIR}/bin/health.sh"
  execute sudo chown root:wheel "${AGENTBOX_OPT_DIR}/bin/health.sh"
  execute sudo chmod 755 "${AGENTBOX_OPT_DIR}/bin/health.sh"
}

openclaw_gateway_state_dir() {
  printf "%s/.openclaw" "$(openclaw_runner_home_required)"
}

openclaw_gateway_service_env_dir() {
  printf "%s/service-env" "$(openclaw_gateway_state_dir)"
}

openclaw_gateway_dotenv_path() {
  printf "%s/.env" "$(openclaw_gateway_state_dir)"
}

openclaw_native_gateway_service_env_file_path() {
  printf "%s/%s.env" "$(openclaw_gateway_service_env_dir)" "${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}"
}

openclaw_native_gateway_log_dir() {
  printf "%s/Library/Logs/openclaw" "$(openclaw_runner_home_required)"
}

openclaw_native_gateway_log_path() {
  printf "%s/gateway.log" "$(openclaw_native_gateway_log_dir)"
}

agentbox_launchd_template_content() {
  local template_path="$1"
  local tailscaled_bin="${2:-}"
  local rendered
  local agentbox_version
  local health_label
  local health_script_path
  local health_stdout_log
  local health_stderr_log
  local tailscaled_label
  local tailscaled_stdout_log
  local tailscaled_stderr_log
  local tailscaled_statedir
  local tailscaled_statedir_argument

  if ! rendered="$(cat "${template_path}")"; then
    abort "failed to read agentbox launchd template ${tty_ts}$(display_home_path "${template_path}")${tty_reset}."
  fi

  agentbox_version="$(xml_escape "${SCRIPT_VERSION}")"
  health_label="$(xml_escape "${AGENTBOX_HEALTH_LABEL}")"
  health_script_path="$(xml_escape "${AGENTBOX_OPT_DIR}/bin/health.sh")"
  health_stdout_log="$(xml_escape "${AGENTBOX_LOG_DIR}/health.stdout.log")"
  health_stderr_log="$(xml_escape "${AGENTBOX_LOG_DIR}/health.stderr.log")"
  tailscaled_label="$(xml_escape "${AGENTBOX_TAILSCALED_LABEL}")"
  tailscaled_bin="$(xml_escape "${tailscaled_bin}")"
  tailscaled_stdout_log="$(xml_escape "${AGENTBOX_LOG_DIR}/tailscaled.stdout.log")"
  tailscaled_stderr_log="$(xml_escape "${AGENTBOX_LOG_DIR}/tailscaled.stderr.log")"
  tailscaled_statedir="${AGENTBOX_TAILSCALED_STATE_DIR}"
  tailscaled_statedir_argument="      <string>$(xml_escape "--statedir=${tailscaled_statedir}")</string>"

  rendered="${rendered//__AGENTBOX_VERSION__/${agentbox_version}}"
  rendered="${rendered//__AGENTBOX_HEALTH_LABEL__/${health_label}}"
  rendered="${rendered//__AGENTBOX_HEALTH_SCRIPT_PATH__/${health_script_path}}"
  rendered="${rendered//__AGENTBOX_HEALTH_STDOUT_LOG__/${health_stdout_log}}"
  rendered="${rendered//__AGENTBOX_HEALTH_STDERR_LOG__/${health_stderr_log}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_LABEL__/${tailscaled_label}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_BIN__/${tailscaled_bin}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_STATEDIR_ARGUMENT__/${tailscaled_statedir_argument}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_STDOUT_LOG__/${tailscaled_stdout_log}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_STDERR_LOG__/${tailscaled_stderr_log}}"

  if [[ "${rendered}" == *"__AGENTBOX_"* ]]; then
    abort "agentbox launchd template ${tty_ts}$(display_home_path "${template_path}")${tty_reset} contains unresolved placeholders."
  fi

  printf "%s\n" "${rendered}"
}

AGENTBOX_LAST_LAUNCHD_PLIST_CHANGED="0"

render_agentbox_launchd_template() {
  local template_path="$1"
  local output_path="$2"
  local tailscaled_bin="${3:-}"
  local rendered
  local tmp_dir
  local tmp_path

  AGENTBOX_LAST_LAUNCHD_PLIST_CHANGED="0"
  rendered="$(agentbox_launchd_template_content "${template_path}" "${tailscaled_bin}")"
  tmp_dir="${BOOT_TMPDIR:-/tmp}"
  tmp_path="${tmp_dir}/agentbox.$(basename "${output_path}").rendered.$$"

  if ! printf "%s\n" "${rendered}" > "${tmp_path}"; then
    abort "failed to write temporary agentbox launchd daemon ${tty_ts}${tmp_path}${tty_reset}."
  fi

  execute /usr/bin/plutil -lint "${tmp_path}"

  if ! sudo test -f "${output_path}" || ! sudo cmp -s "${tmp_path}" "${output_path}"; then
    AGENTBOX_LAST_LAUNCHD_PLIST_CHANGED="1"
    execute sudo cp "${tmp_path}" "${output_path}"
  fi

  execute sudo chown root:wheel "${output_path}"
  execute sudo chmod 644 "${output_path}"
  rm -f "${tmp_path}"
}

agentbox_system_launchd_loaded() {
  local label="$1"

  sudo launchctl print "system/${label}" >/dev/null 2>&1
}

refresh_agentbox_system_launchd_service() {
  local label="$1"
  local plist_path="$2"
  local kickstart="${3:-0}"
  local force_reload="${4:-0}"
  local loaded="0"

  if agentbox_system_launchd_loaded "${label}"; then
    loaded="1"
  fi

  if [[ "${force_reload}" != "1" && "${AGENTBOX_LAST_LAUNCHD_PLIST_CHANGED}" != "1" && "${loaded}" == "1" ]]; then
    execute sudo launchctl enable "system/${label}"
    log "${tty_tp}skipping${tty_reset} launchd reload for ${tty_ts}${label}${tty_reset}; rendered plist is unchanged and already loaded"
    return 0
  fi

  sudo launchctl bootout "system/${label}" >/dev/null 2>&1 || true
  sudo launchctl bootout system "${plist_path}" >/dev/null 2>&1 || true
  execute sudo launchctl enable "system/${label}"
  execute sudo launchctl bootstrap system "${plist_path}"
  if [[ "${kickstart}" == "1" ]]; then
    execute sudo launchctl kickstart -k "system/${label}"
  fi
}

write_agentbox_health_plist() {
  render_agentbox_launchd_template "${AGENTBOX_HEALTH_PLIST_TEMPLATE}" "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist"
}

run_agentbox_launchd_health_setup() {
  if sudo launchctl print "system/${AGENTBOX_HEALTH_LABEL}" >/dev/null 2>&1; then
    log "${tty_tp}refreshing${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
  else
    log "${tty_tp}installing${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
  fi

  execute sudo mkdir -p "${AGENTBOX_OPT_DIR}/bin" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  execute sudo chown -R root:wheel "${AGENTBOX_OPT_DIR}"
  execute sudo chown root:wheel "${AGENTBOX_STATE_DIR}"
  execute sudo chown root:wheel "${AGENTBOX_LOG_DIR}"
  execute sudo chmod 755 "${AGENTBOX_OPT_DIR}" "${AGENTBOX_OPT_DIR}/bin" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  write_agentbox_health_state
  write_agentbox_health_script
  write_agentbox_health_plist

  refresh_agentbox_system_launchd_service "${AGENTBOX_HEALTH_LABEL}" "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist" "1" "1"
}

run_agentbox_post_bootstrap_summary() {
  local health_command="${AGENTBOX_OPT_DIR}/bin/health.sh"
  local health_ok="0"
  local health_report

  if health_report="$(sudo "${health_command}" --check 2>&1)"; then
    health_ok="1"
  fi

  debug_multi "agentbox health report" "${health_report}"
  log
  if [[ "${OPENCLAW_GATEWAY_SETUP_STATUS}" == "pending_first_login" ]]; then
    log "agentbox setup ${tty_green}succeeded${tty_reset}; openclaw Gateway activation is staged for the runtime user's next graphical login"
    log
    log "after activation, ${tty_tp}open${tty_reset} the openclaw dashboard from the ${tty_ts}${OPENCLAW_USER}${tty_reset} graphical session:"
    log "  ${tty_ts}openclaw dashboard${tty_reset}"
    return 0
  fi

  if [[ "${OPENCLAW_GATEWAY_SETUP_STATUS}" == "failed" ]]; then
    printf "agentbox setup completed, but openclaw Gateway activation %sfailed%s\n" "${tty_red}" "${tty_reset}" >&2
    printf "%sdetails:%s inspect %s and rerun agentbox\n" "${tty_dim}" "${tty_reset}" "$(openclaw_finalizer_log_dir)/openclaw-finalize.error.log" >&2
    return 1
  fi

  if [[ "${health_ok}" == "1" ]]; then
    log "agentbox setup ${tty_green}succeeded${tty_reset}"
    log
    log "${tty_tp}open${tty_reset} the openclaw dashboard from the ${tty_ts}${OPENCLAW_USER}${tty_reset} graphical session:"
    log "  ${tty_ts}openclaw dashboard${tty_reset}"
    return 0
  fi

  printf "agentbox setup completed, but health checks %sfailed%s\n" "${tty_red}" "${tty_reset}" >&2
  printf "%sdetails:%s %ssudo %s --report%s\n" "${tty_dim}" "${tty_reset}" "${tty_ts}" "${health_command}" "${tty_reset}" >&2
  return 1
}

plan_action() {
  PLANNED_ACTIONS+=("$1")
}

have_planned_actions() {
  array_has_values PLANNED_ACTIONS
}

show_planned_actions() {
  local action

  if ! have_planned_actions; then
    return 0
  fi

  log "${tty_bold}this script is about to:${tty_reset}"
  log

  for action in "${PLANNED_ACTIONS[@]}"; do
    log "  - ${action}"
  done
}

getc() {
  local input_path
  local save_state

  input_path="$(interactive_tty_input)"
  save_state="$(/bin/stty -g < "${input_path}")"
  /bin/stty raw -echo < "${input_path}"
  IFS='' read -r -n 1 -d '' "$@" < "${input_path}"
  /bin/stty "${save_state}" < "${input_path}"
}

wait_for_user() {
  local c

  trap 'if [[ -r /dev/tty ]]; then /bin/stty sane < /dev/tty; else /bin/stty sane; fi; tput sgr0; echo; exit 1' SIGINT

  echo
  echo "press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
  getc c
  if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]; then
    exit 1
  fi
}

interactive_tty_available() {
  [[ -r /dev/tty && -w /dev/tty ]] || [[ -t 0 ]]
}

interactive_tty_input() {
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    printf "/dev/tty"
  else
    printf "/dev/stdin"
  fi
}

noninteractive_mode_enabled() {
  [[ -n "${NONINTERACTIVE-}" ]]
}

openclaw_onboarding_mode_display() {
  if noninteractive_mode_enabled; then
    printf "non-interactive"
  else
    printf "interactive"
  fi
}

execute() {
  debug "${tty_tp}running${tty_reset}" "$@"
  if ! "$@"; then
    abort "$(printf "failed during: %s" "$(shell_join "$@")")"
  fi
}

sudo() {
  if [[ "${SUDO_SESSION_ACTIVE:-0}" != "1" ]]; then
    abort "internal sudo command attempted before agentbox established its administrator session."
  fi

  "${SUDO_BIN}" -n "$@"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    abort "required command not found: $1"
  fi
}

cleanup() {
  stop_sudo_keepalive
  SUDO_SESSION_ACTIVE="0"

  if [[ -n "${BOOT_TMPDIR:-}" && -d "${BOOT_TMPDIR}" ]]; then
    rm -rf "${BOOT_TMPDIR}"
  fi
}

validate_platform() {
  local macos_version

  detect_arch
  detect_os

  ARCH="${AGENTBOX_ARCH:-${DETECTED_ARCH}}"
  OS="${AGENTBOX_OS:-${DETECTED_OS}}"

  if [[ "${EUID:-${UID}}" == "0" ]]; then
    abort "cannot run this script as root."
  fi

  CURL="$(command -v curl || true)"
  if [[ -z "${CURL}" ]] || ! test_curl "${CURL}"; then
    abort "you must install curl ${REQUIRED_CURL_VERSION} or higher before using this wrapper."
  fi

  if [[ "${OS}" != "macos" ]]; then
    abort_multi "$(cat <<EOABORT
this script only supports ${tty_ts}macos${tty_reset}; ${tty_red}${OS}${tty_reset} is not supported.
check the project README for current support details: ${tty_underline}${tty_magenta}https://github.com/tanaabased/agentbox${tty_reset}
EOABORT
)"
  fi

  if [[ "${ARCH}" != "x64" ]] && [[ "${ARCH}" != "arm64" ]]; then
    abort_multi "$(cat <<EOABORT
this script currently only supports ${tty_ts}x64${tty_reset} and ${tty_ts}arm64${tty_reset} systems.
check the project README for current support details: ${tty_underline}${tty_magenta}https://github.com/tanaabased/agentbox${tty_reset}
EOABORT
)"
  fi

  macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"
  if ! version_compare "${macos_version}" "${MACOS_OLDEST_SUPPORTED}"; then
    abort_multi "$(cat <<EOABORT
your macos version ${tty_red}${macos_version}${tty_reset} is ${tty_bold}too old${tty_reset}; minimum supported version is ${tty_ts}${MACOS_OLDEST_SUPPORTED}${tty_reset}.
check the project README for current support details: ${tty_underline}${tty_magenta}https://github.com/tanaabased/agentbox${tty_reset}
EOABORT
)"
  fi

  if version_compare "${macos_version}" "${MACOS_UNSUPPORTED_AT_OR_AFTER}"; then
    if unsupported_macos_allowed; then
      warn "macos ${macos_version} is outside the validated support range ${MACOS_SUPPORTED_RANGE}; continuing because AGENTBOX_ALLOW_UNSUPPORTED_MACOS is truthy."
    else
      abort_multi "$(cat <<EOABORT
your macos version ${tty_red}${macos_version}${tty_reset} is newer than the validated support range ${tty_ts}${MACOS_SUPPORTED_RANGE}${tty_reset}.
agentbox stops before machine mutation on unvalidated major macos versions.
to intentionally test anyway, set ${tty_bold}AGENTBOX_ALLOW_UNSUPPORTED_MACOS=1${tty_reset} and rerun.
EOABORT
)"
    fi
  fi
}

validate_inputs_before_sudo() {
  TAILSCALE_AUTHKEY="$(trim_whitespace "${TAILSCALE_AUTHKEY}")"
  OPENCLAW_IDENTITY_INPUT="$(trim_whitespace "${OPENCLAW_IDENTITY_INPUT}")"
  OPENCLAW_AUTOLOGIN="$(trim_whitespace "${OPENCLAW_AUTOLOGIN}")"
  OPENCLAW_GATEWAY_PORT="$(trim_whitespace "${OPENCLAW_GATEWAY_PORT}")"
  OPENCLAW_AUTH_CHOICE="$(trim_whitespace "${OPENCLAW_AUTH_CHOICE}")"
  OPENCLAW_AUTH_ENV="$(trim_whitespace "${OPENCLAW_AUTH_ENV}")"

  parse_openclaw_identity_input

  if [[ -z "${OPENCLAW_AUTH_CHOICE}" ]]; then
    abort "openclaw auth choice must not be empty."
  fi

  if [[ "${OPENCLAW_AUTH_CHOICE}" =~ [[:space:]] ]]; then
    abort "openclaw auth choice ${tty_ts}${OPENCLAW_AUTH_CHOICE}${tty_reset} must not contain whitespace."
  fi

  if ! openclaw_autologin_valid "${OPENCLAW_AUTOLOGIN}"; then
    abort "openclaw autologin ${tty_ts}${OPENCLAW_AUTOLOGIN:-empty}${tty_reset} must be ${tty_ts}on${tty_reset} or ${tty_ts}off${tty_reset}."
  fi

  if [[ -n "${OPENCLAW_AUTH_ENV}" ]] && ! env_name_valid "${OPENCLAW_AUTH_ENV}"; then
    abort "openclaw auth env ${tty_ts}${OPENCLAW_AUTH_ENV}${tty_reset} must be a valid environment variable name."
  fi

  validate_openclaw_auth_choice_env

  if ! openclaw_gateway_port_valid "${OPENCLAW_GATEWAY_PORT}"; then
    abort "openclaw gateway port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset} must be an integer from 1 to 65535."
  fi

  derive_openclaw_gateway_tailscale_mode

  if ! hostname_valid "${AGENTBOX_HOSTNAME_VALUE}"; then
    abort "hostname ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} must be dns-safe."
  fi
}

validate_inputs() {
  validate_inputs_before_sudo
  BREWGROUP_INPUT="$(trim_whitespace "${BREWGROUP_INPUT}")"
  ADMIN_USER="$(id -un 2>/dev/null || true)"

  if [[ -z "${ADMIN_USER}" ]]; then
    abort "the current admin user could not be inferred."
  fi

  if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    abort "current admin user ${tty_ts}${ADMIN_USER}${tty_reset} does not exist on this mac."
  fi

  resolve_authorized_key_specs
  validate_existing_openclaw_user
  validate_openclaw_autologin_preflight

  if [[ -n "${NONINTERACTIVE-}" || -n "${CI-}" ]]; then
    if openclaw_password_required && [[ -z "${OPENCLAW_PASSWORD}" ]]; then
      abort_missing_openclaw_password "prepare the openclaw runner user"
    fi
  fi

  parse_brewgroup_input

  if ! brewgroup_setup_disabled && ! brewgroup_valid "${BREWGROUP_VALUE}"; then
    abort "brewgroup ${tty_ts}${BREWGROUP_VALUE}${tty_reset} must start with a letter or underscore and contain only letters, digits, underscore, dot, or dash."
  fi

  if trusted_brewgroup_enabled; then
    if ! brewgroup_valid "${TRUSTED_BREWGROUP_VALUE}"; then
      abort "trusted brewgroup ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} must start with a letter or underscore and contain only letters, digits, underscore, dot, or dash."
    fi

    if [[ "${TRUSTED_BREWGROUP_VALUE}" == "${BREWGROUP_VALUE}" ]]; then
      abort "trusted brewgroup ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} must be different from brewgroup ${tty_ts}${BREWGROUP_VALUE}${tty_reset}."
    fi

    if ! group_exists "${TRUSTED_BREWGROUP_VALUE}"; then
      abort "trusted brewgroup ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} must already exist before it can be nested into ${tty_ts}${BREWGROUP_VALUE}${tty_reset}."
    fi
  fi

  if tailscale_setup_disabled; then
    TAILSCALE_HOSTNAME_VALUE=""
    return 0
  fi

  TAILSCALE_HOSTNAME_VALUE="$(derive_tailscale_hostname "${AGENTBOX_HOSTNAME_VALUE}")"
  if [[ -z "${TAILSCALE_HOSTNAME_VALUE}" ]]; then
    abort "hostname ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} derives an empty tailscale hostname after stripping the leading TANAAB prefix."
  fi

  if ! hostname_valid "${TAILSCALE_HOSTNAME_VALUE}"; then
    abort "derived tailscale hostname ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset} from ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} must be dns-safe."
  fi
}

apply_noninteractive_mode() {
  # shellcheck disable=SC2016
  if [[ -z "${NONINTERACTIVE-}" ]]; then
    if [[ -n "${CI-}" ]]; then
      warn "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} because \$CI is set."
      NONINTERACTIVE=1
    elif ! interactive_tty_available; then
      if [[ -z "${INTERACTIVE-}" ]]; then
        warn "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} because no interactive terminal is available."
        NONINTERACTIVE=1
      else
        abort "cannot run interactive mode because no interactive terminal is available."
      fi
    elif [[ ! -t 0 ]]; then
      debug "${tty_tp}using${tty_reset} ${tty_ts}/dev/tty${tty_reset} for interactive input because stdin is not a tty."
    fi
  else
    log "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} ${tty_dim}because \$NONINTERACTIVE is set${tty_reset}"
  fi
}

validate_sudo_capability() {
  if [[ ! -x "${SUDO_BIN}" ]]; then
    abort "sudo is required for agentbox bootstrap, but ${SUDO_BIN} was not found."
  fi

  if ! user_is_admin "${ADMIN_USER}"; then
    abort "current user ${tty_ts}${ADMIN_USER}${tty_reset} must be a macos administrator before agentbox can continue."
  fi
}

check_sudo_access() {
  local phase="${1:-initial}"
  local keepalive_was_active="1"
  local sudo_failure

  if [[ ! -x "${SUDO_BIN}" ]]; then
    abort "sudo is required for agentbox bootstrap, but ${SUDO_BIN} was not found."
  fi

  if [[ "${SUDO_SESSION_ACTIVE:-0}" == "1" ]]; then
    if ! refresh_sudo_keepalive_state; then
      keepalive_was_active="0"
    fi

    if "${SUDO_BIN}" -n -v; then
      if [[ "${keepalive_was_active}" == "0" ]]; then
        start_sudo_keepalive
        debug "${tty_tp}restarted${tty_reset}" sudo keepalive "${phase}"
      fi
      debug "${tty_tp}verified${tty_reset}" sudo access "${phase}"
      return 0
    fi

    if recover_sudo_authorization "${phase}"; then
      return 0
    fi

    if [[ -n "${CI-}" || -n "${NONINTERACTIVE-}" ]]; then
      sudo_failure="$(cat <<EOS
sudo authorization is no longer available during ${phase}.
agentbox cannot prompt again in CI or non-interactive mode.
rerun agentbox interactively, or configure passwordless sudo for this bootstrap user.
EOS
)"
    else
      sudo_failure="$(cat <<EOS
sudo authorization could not be restored during ${phase}.
rerun agentbox and enter your admin password after plan confirmation.
EOS
)"
    fi

    SUDO_SESSION_ACTIVE="0"
    abort_multi "${sudo_failure}"
  fi

  if [[ -n "${CI-}" || -n "${NONINTERACTIVE-}" ]]; then
    if "${SUDO_BIN}" -n -v; then
      debug "${tty_tp}verified${tty_reset}" sudo access "${phase}"
      return 0
    fi

    sudo_failure="$(cat <<EOS
sudo access is required before agentbox can install packages or configure services.
run this script from an admin account, run it once interactively so sudo can prompt, or configure passwordless sudo for this bootstrap user before using CI/NONINTERACTIVE mode.
EOS
)"
    abort_multi "${sudo_failure}"
  fi

  if "${SUDO_BIN}" -v; then
    if "${SUDO_BIN}" -n -v; then
      debug "${tty_tp}verified${tty_reset}" reusable sudo access "${phase}"
      return 0
    fi

    sudo_failure="$(cat <<EOS
sudo accepted administrator authentication, but reusable authorization is unavailable.
agentbox requires a reusable sudo timestamp so later privileged operations remain non-interactive.
check the sudo timestamp policy on this Mac, or configure passwordless sudo for this bootstrap user.
EOS
)"
    abort_multi "${sudo_failure}"
  fi

  abort "sudo access is required before agentbox can install packages or configure services."
}

refresh_sudo_keepalive_state() {
  if [[ -z "${SUDO_KEEPALIVE_PID:-}" ]]; then
    return 1
  fi

  if kill -0 "${SUDO_KEEPALIVE_PID}" >/dev/null 2>&1; then
    return 0
  fi

  wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  SUDO_KEEPALIVE_PID=""
  debug "${tty_tp}detected${tty_reset}" inactive sudo keepalive
  return 1
}

stop_sudo_keepalive() {
  if [[ -z "${SUDO_KEEPALIVE_PID:-}" ]]; then
    return 0
  fi

  if kill -0 "${SUDO_KEEPALIVE_PID}" >/dev/null 2>&1; then
    kill "${SUDO_KEEPALIVE_PID}" >/dev/null 2>&1 || true
  fi
  wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  SUDO_KEEPALIVE_PID=""
}

start_sudo_keepalive() {
  if [[ "${SUDO_SESSION_ACTIVE:-0}" != "1" ]]; then
    abort "internal sudo keepalive attempted before agentbox established its administrator session."
  fi

  if refresh_sudo_keepalive_state; then
    return 0
  fi

  (
    sleep_pid=""
    trap 'if [[ -n "${sleep_pid}" ]]; then kill "${sleep_pid}" >/dev/null 2>&1 || true; fi; exit 0' INT TERM
    while :; do
      "${SUDO_BIN}" -n -v >/dev/null 2>&1 || exit 1
      sleep 60 &
      sleep_pid="$!"
      wait "${sleep_pid}" || exit 0
      sleep_pid=""
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
}

recover_sudo_authorization() {
  local phase="${1:-before bootstrap changes}"
  local sudo_failure

  if [[ -n "${CI-}" || -n "${NONINTERACTIVE-}" ]]; then
    return 1
  fi

  stop_sudo_keepalive

  log ""
  log "${tty_bold}${tty_tp}administrator authorization required again${tty_reset}"
  log "agentbox could not refresh its sudo authorization during ${phase}."
  log "enter your admin password again to continue; agentbox will restart its sudo keepalive."

  if ! "${SUDO_BIN}" -v; then
    return 1
  fi

  if ! "${SUDO_BIN}" -n -v; then
    sudo_failure="$(cat <<EOS
sudo accepted administrator authentication, but reusable authorization is still unavailable.
agentbox cannot continue without repeatedly requesting your password.
check the sudo timestamp policy on this Mac, or configure passwordless sudo for this bootstrap user.
EOS
)"
    SUDO_SESSION_ACTIVE="0"
    abort_multi "${sudo_failure}"
  fi

  SUDO_SESSION_ACTIVE="1"
  start_sudo_keepalive
  debug "${tty_tp}restored${tty_reset}" sudo access "${phase}"
  return 0
}

start_sudo_session() {
  local phase="${1:-before bootstrap changes}"

  if [[ "${SUDO_SESSION_ACTIVE:-0}" == "1" ]]; then
    check_sudo_access "${phase}"
    start_sudo_keepalive
    return 0
  fi

  if [[ -z "${CI-}" && -z "${NONINTERACTIVE-}" ]]; then
    log ""
    log "${tty_bold}${tty_tp}administrator access required${tty_reset}"
    log "agentbox uses sudo to install packages and configure macOS services."
    log "enter your admin password when prompted; agentbox keeps this authorization active until it exits."
  fi

  check_sudo_access "${phase}"
  SUDO_SESSION_ACTIVE="1"
  start_sudo_keepalive
}

core_remediation_needed() {
  [[ "${CORE_NEEDS_REMEDIATION:-0}" == "1" ]]
}

run_bootbox_from_tmpdir() (
  cd "${BOOT_TMPDIR}" || exit 1
  "$@"
)

bootbox_run() {
  local mode="$1"
  local env_name
  local -a unset_env_names=(
    BOOTBOX_BREWFILE
    BOOTBOX_BREWFILES
    TANAAB_BREWFILE
    TANAAB_BREWFILES
    TANAAB_DOTPKG
    TANAAB_DOTPKGS
    TANAAB_SSH_KEY
    TANAAB_SSH_KEYS
    TANAAB_FORCE
    TANAAB_DEBUG
    BOOTBOX_EXTERNAL_SUDO
    BOOTBOX_QUIET
    HOMEBREW_ASK
    INTERACTIVE
    TANAAB_QUIET
    TANAAB_ARCH
    TANAAB_OS
    TANAAB_TARGET
  )
  local -a bootbox_command=(env)
  local -a bootbox_display_command=()

  shift

  case "${mode}" in
    core | agentbox)
      ;;
    *)
      abort "unsupported internal bootbox mode ${tty_bold}${mode}${tty_reset}."
      ;;
  esac

  for env_name in "${unset_env_names[@]}"; do
    bootbox_command+=(-u "${env_name}")
  done

  if [[ -n "${DEBUG-}" ]]; then
    bootbox_command+=("TANAAB_DEBUG=${DEBUG}")
    bootbox_display_command+=("AGENTBOX_DEBUG=${DEBUG}")
  fi

  if [[ -n "${FORCE-}" ]]; then
    bootbox_command+=("TANAAB_FORCE=${FORCE}")
    bootbox_display_command+=("AGENTBOX_FORCE=${FORCE}")
  fi

  if [[ "${SUDO_SESSION_ACTIVE:-0}" == "1" ]]; then
    bootbox_command+=("BOOTBOX_EXTERNAL_SUDO=1")
  fi
  bootbox_command+=("BOOTBOX_QUIET=1")
  bootbox_display_command+=("BOOTBOX_QUIET=1")

  bootbox_command+=("HOMEBREW_NO_ASK=1")
  bootbox_display_command+=("HOMEBREW_NO_ASK=1")

  bootbox_command+=("NONINTERACTIVE=1")
  bootbox_display_command+=("NONINTERACTIVE=1")

  bootbox_command+=(/bin/bash "${BOOTBOX_SCRIPT_PATH}")
  bootbox_display_command+=(/bin/bash "${BOOTBOX_SCRIPT_PATH}")
  bootbox_command+=("$@")
  bootbox_display_command+=("$@")

  debug "${tty_tp}delegating${tty_reset} to ${tty_ts}bootbox${tty_reset} from ${tty_ts}${BOOT_TMPDIR}${tty_reset} with $(shell_join "${bootbox_display_command[@]}")"
  run_bootbox_from_tmpdir "${bootbox_command[@]}"
}

bootbox_run_or_abort() {
  local mode="$1"
  local failure_message="$2"
  shift 2

  if ! bootbox_run "${mode}" "$@"; then
    abort "${failure_message}"
  fi
}

plan_agentbox_payload() {
  plan_action "${tty_tp}use${tty_reset} ${tty_ts}agentbox${tty_reset} payload from ${tty_ts}$(agentbox_payload_display)${tty_reset} ${tty_dim}($(agentbox_payload_source_display))${tty_reset}"
}

plan_wrapper_execution() {
  if core_remediation_needed; then
    plan_action "${tty_tp}ensure${tty_reset} ${tty_ts}homebrew${tty_reset} is installed"
    plan_action "${tty_tp}install${tty_reset} ${tty_ts}bootbox core packages${tty_reset}"
  fi

  plan_agentbox_payload
  plan_action "${tty_tp}ensure${tty_reset} macos ComputerName, HostName, and LocalHostName are ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
  plan_action "${tty_tp}ensure${tty_reset} headless power, time, and recovery settings"
  if array_has_values EXTRA_BREWFILE_SPECS; then
    plan_action "${tty_tp}run${tty_reset} ${tty_ts}bootbox${tty_reset} against the ${tty_ts}agentbox${tty_reset} Brewfile plus extra brewfiles: ${tty_ts}$(array_join ", " EXTRA_BREWFILE_SPECS)${tty_reset}"
  else
    plan_action "${tty_tp}run${tty_reset} ${tty_ts}bootbox${tty_reset} against the ${tty_ts}agentbox${tty_reset} Brewfile"
  fi
  plan_action "${tty_tp}ensure${tty_reset} homebrew commands are available to login shells through ${tty_ts}${AGENTBOX_HOMEBREW_PATHS_FILE}${tty_reset}"
  if user_exists "${OPENCLAW_USER}"; then
    plan_action "${tty_tp}reuse${tty_reset} non-admin openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  else
    plan_action "${tty_tp}create${tty_reset} non-admin openclaw runner user ${tty_ts}${OPENCLAW_FULL_NAME} <${OPENCLAW_USER}>${tty_reset}"
  fi
  if openclaw_autologin_enabled; then
    plan_action "${tty_tp}ensure${tty_reset} openclaw runner autologin is configured for ${tty_ts}${OPENCLAW_USER}${tty_reset} for unattended reboot recovery"
  else
    plan_action "${tty_tp}preserve${tty_reset} login-window state and require a graphical runtime-user login after each reboot"
  fi
  if brewgroup_setup_disabled; then
    plan_action "${tty_tp}skip${tty_reset} homebrew brewgroup setup because the brewgroup input is disabled"
  else
    plan_action "${tty_tp}ensure${tty_reset} homebrew prefix group write access for ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    plan_action "${tty_tp}add${tty_reset} invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} to homebrew brewgroup ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    plan_action "${tty_tp}add${tty_reset} openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} to homebrew brewgroup ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    if trusted_brewgroup_enabled; then
      plan_action "${tty_tp}nest${tty_reset} trusted homebrew group ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} into ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    fi
  fi
  plan_action "${tty_tp}ensure${tty_reset} classic ssh is enabled for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
  plan_action "${tty_tp}ensure${tty_reset} macos remote login access includes invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} and openclaw runner ${tty_ts}${OPENCLAW_USER}${tty_reset} when ${tty_ts}${SSH_ACCESS_GROUP}${tty_reset} exists"
  if array_has_values AUTHORIZED_KEY_LINES; then
    plan_action "${tty_tp}install${tty_reset} ${tty_ts}$(array_count AUTHORIZED_KEY_LINES)${tty_reset} authorized key entries for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} and openclaw runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
    plan_action "${tty_tp}harden${tty_reset} ssh to key-only access for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} and openclaw runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  fi
  if tailscale_setup_disabled; then
    plan_action "${tty_tp}skip${tty_reset} tailscale setup because the auth-key input is disabled"
  else
    plan_action "${tty_tp}remove${tty_reset} competing official or homebrew ${tty_ts}tailscaled${tty_reset} launchd services if present"
    plan_action "${tty_tp}configure or verify${tty_reset} ${tty_ts}tailscaled${tty_reset} as an agentbox system launchd daemon, tailscale hostname ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}, tailscale serve prerequisites, and scoped magicdns resolver"
  fi
  plan_action "${tty_tp}reconcile${tty_reset} a conflicting invoking-admin native gateway and configure the admin app for attach-only use"
  plan_action "${tty_tp}onboard or reconcile${tty_reset} openclaw gateway configuration for runner ${tty_ts}${OPENCLAW_USER}${tty_reset} without installing a service, using model auth choice ${tty_ts}${OPENCLAW_AUTH_CHOICE}${tty_reset}, loopback bind, tailscale exposure ${tty_ts}${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}${tty_reset}, and port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}"
  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" == "serve" ]]; then
    plan_action "${tty_tp}allow${tty_reset} verified tailscale identities for openclaw gateway authentication"
  fi
  plan_action "${tty_tp}configure${tty_reset} permanent openclaw fallback gateway branding as ${tty_ts}${OPENCLAW_UI_ASSISTANT_NAME}${tty_reset} with the bundled default avatar and Tanaab green seam color"
  if user_exists "${OPENCLAW_USER}"; then
    plan_action "${tty_tp}ensure${tty_reset} native runtime-user openclaw LaunchAgent ${tty_ts}${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}${tty_reset} is installed, current, and healthy, using an Aqua-only one-time finalizer only when installation or repair is required"
  else
    plan_action "${tty_tp}stage${tty_reset} an Aqua-only one-time finalizer to install and verify native LaunchAgent ${tty_ts}${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}${tty_reset}"
  fi
  plan_action "${tty_tp}activate and verify${tty_reset} any staged finalizer immediately when the runtime GUI domain exists; otherwise complete on first graphical login"
  plan_action "${tty_tp}install or refresh${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
  plan_action "${tty_tp}print${tty_reset} a nonfatal post-bootstrap health summary"
}

prepare_bootbox_script() {
  BOOT_TMPDIR="$(mktemp -d -t agentbox-boot.XXXXXX)"
  BOOTBOX_SCRIPT_PATH="${BOOT_TMPDIR}/bootbox.sh"

  execute "${CURL}" -fsSL "${BOOTBOX_URL}" -o "${BOOTBOX_SCRIPT_PATH}"
  execute chmod 700 "${BOOTBOX_SCRIPT_PATH}"
}

run_bootbox_check_core() {
  debug "${tty_tp}checking${tty_reset} ${tty_ts}bootbox core requirements${tty_reset} from ${tty_ts}${BOOT_TMPDIR}${tty_reset}"
  if bootbox_run core --check-core; then
    CORE_NEEDS_REMEDIATION="0"
    debug "bootbox core requirements are satisfied"
    return 0
  fi

  CORE_NEEDS_REMEDIATION="1"
  debug "bootbox core requirements need remediation"
  return 1
}

ensure_bootbox_core_requirements() {
  if ! core_remediation_needed; then
    return 0
  fi

  bootbox_run_or_abort core "bootbox failed while ensuring core requirements."
  if ! run_bootbox_check_core; then
    abort "bootbox core requirements are still not satisfied after remediation."
  fi
}

run_bootbox_for_agentbox_brewfile() {
  local extra_brewfile
  local -a bootbox_args=(--brewfile "${AGENTBOX_CORE_BREWFILE}")

  if array_has_values RESOLVED_EXTRA_BREWFILES; then
    for extra_brewfile in "${RESOLVED_EXTRA_BREWFILES[@]}"; do
      bootbox_args+=(--brewfile "${extra_brewfile}")
    done
  fi

  bootbox_run_or_abort agentbox "bootbox failed while applying agentbox brewfiles." "${bootbox_args[@]}"
  debug "bootbox finished applying agentbox brewfiles"
}

resolve_brew_prefix() {
  require_command brew

  BREW_PREFIX_VALUE="$(brew --prefix 2>/dev/null || true)"
  if [[ -z "${BREW_PREFIX_VALUE}" || ! -d "${BREW_PREFIX_VALUE}" ]]; then
    abort "could not resolve an existing homebrew prefix with ${tty_ts}brew --prefix${tty_reset}."
  fi
}

homebrew_login_paths_content() {
  printf '%s/bin\n%s/sbin\n' "${BREW_PREFIX_VALUE}" "${BREW_PREFIX_VALUE}"
}

homebrew_login_paths_ok() {
  local actual
  local expected

  if [[ -z "${BREW_PREFIX_VALUE}" || ! -f "${AGENTBOX_HOMEBREW_PATHS_FILE}" ]]; then
    return 1
  fi

  expected="$(homebrew_login_paths_content)"
  actual="$(cat "${AGENTBOX_HOMEBREW_PATHS_FILE}" 2>/dev/null || true)"
  [[ "${actual}" == "${expected}" ]]
}

run_agentbox_homebrew_login_path_setup() {
  check_sudo_access "before homebrew login-shell PATH setup"
  resolve_brew_prefix

  if homebrew_login_paths_ok; then
    log "${tty_tp}skipping${tty_reset} homebrew login-shell PATH setup; ${tty_ts}${AGENTBOX_HOMEBREW_PATHS_FILE}${tty_reset} already matches ${tty_ts}${BREW_PREFIX_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}writing${tty_reset} homebrew login-shell PATH entries to ${tty_ts}${AGENTBOX_HOMEBREW_PATHS_FILE}${tty_reset}"
  execute sudo mkdir -p "$(dirname "${AGENTBOX_HOMEBREW_PATHS_FILE}")"
  if ! homebrew_login_paths_content | sudo tee "${AGENTBOX_HOMEBREW_PATHS_FILE}" >/dev/null; then
    abort "failed to write homebrew login-shell PATH file ${tty_ts}${AGENTBOX_HOMEBREW_PATHS_FILE}${tty_reset}."
  fi
  execute sudo chown root:wheel "${AGENTBOX_HOMEBREW_PATHS_FILE}"
  execute sudo chmod 644 "${AGENTBOX_HOMEBREW_PATHS_FILE}"

  if ! homebrew_login_paths_ok; then
    abort "homebrew login-shell PATH file ${tty_ts}${AGENTBOX_HOMEBREW_PATHS_FILE}${tty_reset} does not match ${tty_ts}${BREW_PREFIX_VALUE}${tty_reset} after remediation."
  fi
}

group_generated_uid() {
  dscl . -read "/Groups/$1" GeneratedUID 2>/dev/null | awk '$1 == "GeneratedUID:" { print $2; exit }'
}

brewgroup_has_trusted_group() {
  local trusted_group_guid

  if ! trusted_brewgroup_enabled; then
    return 0
  fi

  trusted_group_guid="$(group_generated_uid "${TRUSTED_BREWGROUP_VALUE}")"
  if [[ -z "${trusted_group_guid}" ]]; then
    return 1
  fi

  dscl . -read "/Groups/${BREWGROUP_VALUE}" NestedGroups 2>/dev/null | awk -v expected="${trusted_group_guid}" '
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
  '
}

brewgroup_has_admin_user() {
  group_has_user "${BREWGROUP_VALUE}" "${ADMIN_USER}"
}

brewgroup_has_openclaw_user() {
  group_has_user "${BREWGROUP_VALUE}" "${OPENCLAW_USER}"
}

next_available_group_id() {
  dscl . -list /Groups PrimaryGroupID 2>/dev/null | awk '
    $2 ~ /^[0-9]+$/ { used[$2] = 1 }
    END {
      for (gid = 700; gid < 1000; gid++) {
        if (!(gid in used)) {
          print gid
          exit
        }
      }
    }
  '
}

ensure_brewgroup_exists() {
  local gid

  if group_exists "${BREWGROUP_VALUE}"; then
    log "${tty_tp}skipping${tty_reset} homebrew group creation; ${tty_ts}${BREWGROUP_VALUE}${tty_reset} already exists"
    return 0
  fi

  gid="$(next_available_group_id)"
  if [[ -z "${gid}" ]]; then
    abort "could not find an available local group id for homebrew group ${tty_ts}${BREWGROUP_VALUE}${tty_reset}."
  fi

  log "${tty_tp}creating${tty_reset} homebrew group ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
  execute sudo dscl . -create "/Groups/${BREWGROUP_VALUE}"
  execute sudo dscl . -create "/Groups/${BREWGROUP_VALUE}" PrimaryGroupID "${gid}"
  execute sudo dscl . -create "/Groups/${BREWGROUP_VALUE}" Password "*"
  execute sudo dscl . -create "/Groups/${BREWGROUP_VALUE}" RealName "agentbox homebrew access"
}

ensure_brewgroup_admin_user() {
  if brewgroup_has_admin_user; then
    log "${tty_tp}skipping${tty_reset} homebrew group membership; invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} is already a direct member of ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}adding${tty_reset} invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} to homebrew group ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
  execute sudo dseditgroup -o edit -a "${ADMIN_USER}" -t user "${BREWGROUP_VALUE}"

  if ! brewgroup_has_admin_user; then
    abort "invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} is still not a direct member of homebrew group ${tty_ts}${BREWGROUP_VALUE}${tty_reset} after remediation."
  fi
}

ensure_brewgroup_openclaw_user() {
  if brewgroup_has_openclaw_user; then
    log "${tty_tp}skipping${tty_reset} homebrew group membership; openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} is already a direct member of ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}adding${tty_reset} openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} to homebrew group ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
  execute sudo dseditgroup -o edit -a "${OPENCLAW_USER}" -t user "${BREWGROUP_VALUE}"

  if ! brewgroup_has_openclaw_user; then
    abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} is still not a direct member of homebrew group ${tty_ts}${BREWGROUP_VALUE}${tty_reset} after remediation."
  fi
}

ensure_trusted_brewgroup_nested() {
  if ! trusted_brewgroup_enabled; then
    return 0
  fi

  if brewgroup_has_trusted_group; then
    log "${tty_tp}skipping${tty_reset} trusted homebrew group nesting; ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} is already nested into ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}nesting${tty_reset} trusted homebrew group ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} into ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
  execute sudo dseditgroup -o edit -a "${TRUSTED_BREWGROUP_VALUE}" -t group "${BREWGROUP_VALUE}"

  if ! brewgroup_has_trusted_group; then
    abort "trusted homebrew group ${tty_ts}${TRUSTED_BREWGROUP_VALUE}${tty_reset} is still not nested into ${tty_ts}${BREWGROUP_VALUE}${tty_reset} after remediation."
  fi
}

path_group_rwx() {
  local path="$1"
  local mode

  mode="$(stat -f "%Lp" "${path}" 2>/dev/null || true)"
  [[ "${mode}" =~ ^[0-7]+$ ]] && (( (8#${mode} & 8#070) == 8#070 ))
}

brewgroup_acl_entry() {
  local group="$1"
  local rights="$2"

  printf "group:%s allow %s" "${group}" "${rights}"
}

brewgroup_acl_identity() {
  /usr/bin/dsmemberutil getuuid -G "$1" 2>/dev/null || true
}

directory_brewgroup_acl_ok() {
  local path="$1"
  local group="$2"
  local identity="$3"
  local acl_output

  acl_output="$(/bin/ls -lde "${path}" 2>/dev/null || true)"
  printf "%s\n" "${acl_output}" | awk -v expected_group="${group}" -v expected_identity="${identity}" '
    index($0, ": " expected_identity " allow ") || index($0, ": " expected_group " allow ") {
      if (index($0, "list") &&
          index($0, "search") &&
          index($0, "add_file") &&
          index($0, "add_subdirectory") &&
          index($0, "delete_child") &&
          index($0, "writeattr") &&
          index($0, "writeextattr") &&
          index($0, "directory_inherit")) {
        directory_access = 1
      }
      if (index($0, "list") &&
          index($0, "add_file") &&
          index($0, "add_subdirectory") &&
          index($0, "writeattr") &&
          index($0, "writeextattr") &&
          index($0, "file_inherit") &&
          index($0, "directory_inherit")) {
        file_inheritance = 1
      }
    }
    END {
      exit(directory_access && file_inheritance ? 0 : 1)
    }
  '
}

brew_prefix_acl_inheritance_ok() {
  local directory
  local identity

  identity="$(brewgroup_acl_identity "${BREWGROUP_VALUE}")"
  if [[ -z "${identity}" ]]; then
    return 1
  fi

  while IFS= read -r -d '' directory; do
    if ! directory_brewgroup_acl_ok "${directory}" "${BREWGROUP_VALUE}" "${identity}"; then
      return 1
    fi
  done < <(find -x "${BREW_PREFIX_VALUE}" -type d -print0)
}

previous_managed_brewgroup() {
  local previous

  if ! sudo test -f "${AGENTBOX_HEALTH_STATE_PATH}"; then
    return 0
  fi

  previous="$(sudo awk -F= '
    $1 == "AGENTBOX_HEALTH_BREWGROUP_ENABLED" { enabled = $2 }
    $1 == "AGENTBOX_HEALTH_BREWGROUP" { brewgroup = $2 }
    END {
      if (enabled == "1") {
        print brewgroup
      }
    }
  ' "${AGENTBOX_HEALTH_STATE_PATH}" 2>/dev/null || true)"

  if [[ -n "${previous}" ]] && brewgroup_valid "${previous}"; then
    printf "%s" "${previous}"
  fi
}

remove_brewgroup_acls() {
  local group="$1"
  local directory_acl
  local file_acl
  local file_inherit_acl

  directory_acl="$(brewgroup_acl_entry "${group}" "${BREWGROUP_DIRECTORY_ACL_RIGHTS}")"
  file_acl="$(brewgroup_acl_entry "${group}" "${BREWGROUP_FILE_ACL_RIGHTS}")"
  file_inherit_acl="$(brewgroup_acl_entry "${group}" "${BREWGROUP_FILE_INHERIT_ACL_RIGHTS}")"

  execute sudo find -x "${BREW_PREFIX_VALUE}" -type d -exec chmod -f -a "${file_inherit_acl}" {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" -type d -exec chmod -f -a "${directory_acl}" {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" ! -type d ! -type l -exec chmod -f -a "${file_acl}" {} +
}

apply_brewgroup_access() {
  local directory_acl
  local file_acl
  local file_inherit_acl

  directory_acl="$(brewgroup_acl_entry "${BREWGROUP_VALUE}" "${BREWGROUP_DIRECTORY_ACL_RIGHTS}")"
  file_acl="$(brewgroup_acl_entry "${BREWGROUP_VALUE}" "${BREWGROUP_FILE_ACL_RIGHTS}")"
  file_inherit_acl="$(brewgroup_acl_entry "${BREWGROUP_VALUE}" "${BREWGROUP_FILE_INHERIT_ACL_RIGHTS}")"

  execute sudo find -x "${BREW_PREFIX_VALUE}" -exec chgrp -h "${BREWGROUP_VALUE}" {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" ! -type l -exec chmod g+rwX {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" -type d -exec chmod +a "${directory_acl}" {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" -type d -exec chmod +a "${file_inherit_acl}" {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" ! -type d ! -type l -exec chmod +a "${file_acl}" {} +
}

brew_prefix_permissions_ok() {
  local current_group

  if [[ -z "${BREW_PREFIX_VALUE}" || ! -d "${BREW_PREFIX_VALUE}" ]]; then
    return 1
  fi

  current_group="$(stat -f "%Sg" "${BREW_PREFIX_VALUE}" 2>/dev/null || true)"
  [[ "${current_group}" == "${BREWGROUP_VALUE}" ]] && path_group_rwx "${BREW_PREFIX_VALUE}"
}

run_agentbox_brewgroup_setup() {
  local previous_brewgroup

  if brewgroup_setup_disabled; then
    log "${tty_tp}skipping${tty_reset} homebrew brewgroup setup because the brewgroup input is disabled"
    return 0
  fi

  check_sudo_access "before homebrew brewgroup setup"
  resolve_brew_prefix

  ensure_brewgroup_exists
  ensure_brewgroup_admin_user
  ensure_brewgroup_openclaw_user
  ensure_trusted_brewgroup_nested

  previous_brewgroup="$(previous_managed_brewgroup)"
  if [[ -n "${previous_brewgroup}" && "${previous_brewgroup}" != "${BREWGROUP_VALUE}" ]]; then
    if ! group_exists "${previous_brewgroup}"; then
      abort "cannot replace homebrew brewgroup ${tty_ts}${previous_brewgroup}${tty_reset} because the previous group no longer exists; restore it before changing to ${tty_ts}${BREWGROUP_VALUE}${tty_reset} so agentbox can remove its managed acl entries."
    fi
    log "${tty_tp}removing${tty_reset} homebrew prefix acl access for previous brewgroup ${tty_ts}${previous_brewgroup}${tty_reset}"
    remove_brewgroup_acls "${previous_brewgroup}"
  fi

  log "${tty_tp}reconciling${tty_reset} recursive and inherited homebrew prefix access for ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
  apply_brewgroup_access

  if ! brew_prefix_permissions_ok || ! brew_prefix_acl_inheritance_ok; then
    abort "homebrew prefix ${tty_ts}${BREW_PREFIX_VALUE}${tty_reset} still lacks recursive or inherited access for ${tty_ts}${BREWGROUP_VALUE}${tty_reset} after remediation."
  fi
}

abort_missing_tailscale_authkey() {
  abort_multi "$(cat <<EOABORT
you must provide a tailscale auth key before this mac can join tailscale.
set ${tty_bold}AGENTBOX_TAILSCALE_AUTHKEY${tty_reset}, or pass ${tty_bold}--tailscale-authkey${tty_reset}. Prefer the environment variable to avoid shell-history exposure.
EOABORT
)"
}

show_tailscale_status_summary() {
  log "${tty_tp}tailscale status:${tty_reset}"
  debug "${tty_tp}running${tty_reset}" tailscale status
  tailscale status || true
  debug "${tty_tp}running${tty_reset}" tailscale ip -4
  tailscale ip -4 || true
}

capture_tailscale_status_json() {
  local attempts="0"
  local output

  while [[ "${attempts}" -lt 3 ]]; do
    attempts=$((attempts + 1))

    if output="$(tailscale status --json 2>/dev/null)" && [[ -n "${output}" ]]; then
      printf "%s" "${output}"
      return 0
    fi

    sleep 1
  done

  return 1
}

json_value() {
  local json="$1"
  local filter="$2"

  printf "%s" "${json}" | jq -r "${filter}" 2>/dev/null
}

tailscale_status_has_identity() {
  local status_json="$1"
  local has_identity

  has_identity="$(json_value "${status_json}" 'if ((.Self.HostName // "") != "") and (((.Self.TailscaleIPs // []) | length) > 0) then "1" else "0" end' || true)"
  [[ "${has_identity}" == "1" ]]
}

tailscale_magicdns_suffix_value() {
  local status_json="$1"

  json_value "${status_json}" '.CurrentTailnet.MagicDNSSuffix // empty' | sed 's/[.]$//'
}

tailscale_magicdns_suffix_valid() {
  local suffix="$1"

  [[ -n "${suffix}" &&
    "${suffix}" != *..* &&
    "${suffix}" =~ ^[A-Za-z0-9][-A-Za-z0-9.]*[A-Za-z0-9]$ ]]
}

tailscale_magicdns_enabled_value() {
  local status_json="$1"
  local value=""

  value="$(json_value "${status_json}" 'if .CurrentTailnet.MagicDNSEnabled == true then "1" else "0" end' || true)"
  if [[ "${value}" == "1" ]]; then
    printf "1"
  else
    printf "0"
  fi
}

tailscale_https_certificates_enabled_value() {
  local status_json="$1"
  local value=""

  value="$(json_value "${status_json}" 'if ((.CertDomains // []) | length) > 0 then "1" else "0" end' || true)"
  if [[ "${value}" == "1" ]]; then
    printf "1"
  else
    printf "0"
  fi
}

verify_tailscale_serve_prerequisites() {
  local status_json="$1"
  local magicdns_enabled="0"
  local https_certificates_enabled="0"

  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" != "serve" ]]; then
    return 0
  fi

  if [[ -z "${status_json}" ]]; then
    abort_multi "$(cat <<EOABORT
could not read tailscale status after joining the tailnet, so agentbox cannot verify tailscale serve prerequisites.
openclaw tailscale serve requires magicdns and https certificates to be enabled in tailscale dns settings: ${tty_underline}${tty_magenta}${TAILSCALE_DNS_ADMIN_URL}${tty_reset}
enable magicdns and https certificates, then rerun agentbox. docs: ${tty_underline}${tty_magenta}${TAILSCALE_MAGICDNS_DOCS_URL}${tty_reset} and ${tty_underline}${tty_magenta}${TAILSCALE_HTTPS_CERTS_DOCS_URL}${tty_reset}
EOABORT
)"
  fi

  magicdns_enabled="$(tailscale_magicdns_enabled_value "${status_json}")"
  https_certificates_enabled="$(tailscale_https_certificates_enabled_value "${status_json}")"

  if [[ "${magicdns_enabled}" == "1" && "${https_certificates_enabled}" == "1" ]]; then
    log "${tty_tp}verified${tty_reset} tailscale magicdns and https certificates for openclaw tailscale serve"
    return 0
  fi

  abort_multi "$(cat <<EOABORT
openclaw tailscale serve requires magicdns and https certificates to be enabled in this tailnet.
tailscale_magicdns_enabled=${magicdns_enabled}
tailscale_https_certificates_enabled=${https_certificates_enabled}
open tailscale dns settings, enable magicdns and https certificates, then rerun agentbox: ${tty_underline}${tty_magenta}${TAILSCALE_DNS_ADMIN_URL}${tty_reset}
docs: ${tty_underline}${tty_magenta}${TAILSCALE_MAGICDNS_DOCS_URL}${tty_reset} and ${tty_underline}${tty_magenta}${TAILSCALE_HTTPS_CERTS_DOCS_URL}${tty_reset}
EOABORT
)"
}

configure_tailscale_magicdns_resolver() {
  local status_json="$1"
  local suffix=""
  local resolver_path=""

  suffix="$(tailscale_magicdns_suffix_value "${status_json}" || true)"
  if [[ -z "${suffix}" ]]; then
    warn "tailscale status did not report a magicdns suffix; skipping macos scoped resolver setup."
    return 0
  fi

  if ! tailscale_magicdns_suffix_valid "${suffix}"; then
    warn "tailscale magicdns suffix ${suffix} is not valid for a macos resolver file; skipping scoped resolver setup."
    return 0
  fi

  resolver_path="/etc/resolver/${suffix}"
  if sudo test -f "${resolver_path}"; then
    if sudo grep -Fxq "# Managed by agentbox." "${resolver_path}" &&
      sudo grep -Eq '^[[:space:]]*nameserver[[:space:]]+100[.]100[.]100[.]100([[:space:]]|$)' "${resolver_path}"; then
      log "${tty_tp}skipping${tty_reset} macos scoped resolver for ${tty_ts}${suffix}${tty_reset}; already configured"
      return 0
    fi

    if ! sudo grep -Fxq "# Managed by agentbox." "${resolver_path}"; then
      if sudo grep -Eq '^[[:space:]]*nameserver[[:space:]]+100[.]100[.]100[.]100([[:space:]]|$)' "${resolver_path}"; then
        log "${tty_tp}skipping${tty_reset} macos scoped resolver for ${tty_ts}${suffix}${tty_reset}; already points to tailscale dns"
      else
        warn "macos resolver ${resolver_path} already exists and is not managed by agentbox; leaving it unchanged."
      fi
      return 0
    fi
  fi

  log "${tty_tp}configuring${tty_reset} macos scoped resolver ${tty_ts}${resolver_path}${tty_reset} for tailscale magicdns"
  execute sudo mkdir -p /etc/resolver
  if ! sudo tee "${resolver_path}" >/dev/null <<EORESOLVER
# Managed by agentbox.
nameserver 100.100.100.100
EORESOLVER
  then
    abort "failed to write macos scoped resolver ${tty_ts}${resolver_path}${tty_reset}."
  fi
  execute sudo chown root:wheel "${resolver_path}"
  execute sudo chmod 644 "${resolver_path}"
}

configure_tailscale_operator_user() {
  log "${tty_tp}configuring${tty_reset} tailscale operator user ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  execute sudo tailscale set "--operator=${OPENCLAW_USER}"
}

tailscaled_bin_path() {
  local formula_prefix=""
  local command_path=""

  formula_prefix="$(brew --prefix tailscale 2>/dev/null || true)"
  if [[ -n "${formula_prefix}" && -x "${formula_prefix}/bin/tailscaled" ]]; then
    printf "%s/bin/tailscaled" "${formula_prefix}"
    return 0
  fi

  command_path="$(command -v tailscaled 2>/dev/null || true)"
  if [[ -n "${command_path}" && -x "${command_path}" ]]; then
    printf "%s" "${command_path}"
    return 0
  fi

  return 1
}

prepare_tailscaled_statedir() {
  log "${tty_tp}configuring${tty_reset} tailscaled state directory ${tty_ts}${AGENTBOX_TAILSCALED_STATE_DIR}${tty_reset}"
  execute sudo mkdir -p "${AGENTBOX_TAILSCALED_STATE_DIR}"
  execute sudo chown root:wheel "${AGENTBOX_TAILSCALED_STATE_DIR}"
  execute sudo chmod 700 "${AGENTBOX_TAILSCALED_STATE_DIR}"
}

remove_official_tailscale_launchd_service() {
  if sudo launchctl print "system/${OFFICIAL_TAILSCALE_LABEL}" >/dev/null 2>&1 ||
    sudo test -f "${OFFICIAL_TAILSCALE_SYSTEM_PLIST_PATH}"; then
    log "${tty_tp}removing${tty_reset} competing official tailscale launchd daemon ${tty_ts}${OFFICIAL_TAILSCALE_LABEL}${tty_reset}"
  fi

  sudo launchctl bootout "system/${OFFICIAL_TAILSCALE_LABEL}" >/dev/null 2>&1 || true
  sudo launchctl bootout system "${OFFICIAL_TAILSCALE_SYSTEM_PLIST_PATH}" >/dev/null 2>&1 || true
  if sudo test -f "${OFFICIAL_TAILSCALE_SYSTEM_PLIST_PATH}"; then
    execute sudo rm -f "${OFFICIAL_TAILSCALE_SYSTEM_PLIST_PATH}"
  fi
}

remove_homebrew_tailscale_launchd_services() {
  local admin_uid=""
  local homebrew_user_plist_path="${HOME}/Library/LaunchAgents/${HOMEBREW_TAILSCALE_LABEL}.plist"

  admin_uid="$(id -u "${ADMIN_USER}" 2>/dev/null || true)"

  sudo launchctl bootout "system/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1 || true
  sudo launchctl bootout system "${HOMEBREW_TAILSCALE_SYSTEM_PLIST_PATH}" >/dev/null 2>&1 || true
  if [[ -f "${HOMEBREW_TAILSCALE_SYSTEM_PLIST_PATH}" ]]; then
    execute sudo rm -f "${HOMEBREW_TAILSCALE_SYSTEM_PLIST_PATH}"
  fi

  if [[ -n "${admin_uid}" ]]; then
    launchctl bootout "gui/${admin_uid}/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1 || true
    launchctl bootout "gui/${admin_uid}" "${homebrew_user_plist_path}" >/dev/null 2>&1 || true
  fi

  if [[ -f "${homebrew_user_plist_path}" ]]; then
    execute sudo rm -f "${homebrew_user_plist_path}"
  fi
}

write_agentbox_tailscaled_plist() {
  local tailscaled_bin="$1"

  render_agentbox_launchd_template "${AGENTBOX_TAILSCALED_PLIST_TEMPLATE}" "${AGENTBOX_TAILSCALED_PLIST_PATH}" "${tailscaled_bin}"
}

verify_agentbox_tailscaled_launchd_setup() {
  local admin_uid=""

  admin_uid="$(id -u "${ADMIN_USER}" 2>/dev/null || true)"

  if ! agentbox_tailscaled_launchd_loaded; then
    abort "agentbox tailscaled launchd daemon is not loaded in the system launchd domain."
  fi

  if sudo launchctl print "system/${OFFICIAL_TAILSCALE_LABEL}" >/dev/null 2>&1 ||
    sudo test -f "${OFFICIAL_TAILSCALE_SYSTEM_PLIST_PATH}"; then
    abort "competing official tailscale launchd daemon ${tty_ts}${OFFICIAL_TAILSCALE_LABEL}${tty_reset} is still installed or loaded."
  fi

  if sudo launchctl print "system/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
    abort "legacy homebrew tailscale launchd daemon is still loaded in the system launchd domain."
  fi

  if [[ -n "${admin_uid}" ]] && launchctl print "gui/${admin_uid}/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
    abort "legacy homebrew tailscale launchd agent is still loaded in the invoking user's launchd domain."
  fi

  if ! wait_for_agentbox_tailscaled_launchd_running; then
    abort "agentbox tailscaled launchd daemon did not remain running; inspect ${tty_ts}${AGENTBOX_LOG_DIR}/tailscaled.stderr.log${tty_reset} for a competing process or startup failure."
  fi
}

agentbox_tailscaled_launchd_loaded() {
  agentbox_system_launchd_loaded "${AGENTBOX_TAILSCALED_LABEL}"
}

agentbox_tailscaled_launchd_running() {
  sudo launchctl print "system/${AGENTBOX_TAILSCALED_LABEL}" 2>/dev/null |
    grep -Eq '^[[:space:]]*state = running$'
}

wait_for_agentbox_tailscaled_launchd_running() {
  local attempts="0"

  while [[ "${attempts}" -lt 30 ]]; do
    attempts=$((attempts + 1))
    if agentbox_tailscaled_launchd_running; then
      sleep 2
      agentbox_tailscaled_launchd_running && return 0
    fi
    sleep 1
  done

  return 1
}

agentbox_tailscaled_state_file_path() {
  printf "%s/tailscaled.state" "${AGENTBOX_TAILSCALED_STATE_DIR}"
}

verify_agentbox_tailscaled_state_file() {
  local state_file

  state_file="$(agentbox_tailscaled_state_file_path)"
  if ! sudo test -s "${state_file}"; then
    abort "agentbox tailscaled state was not persisted at ${tty_ts}${state_file}${tty_reset}; refusing to report a successful tailscale join."
  fi
}

wait_for_agentbox_tailscale_running_status() {
  local attempts="0"
  local backend_state=""
  local current_hostname=""
  local status_json=""

  while [[ "${attempts}" -lt 30 ]]; do
    attempts=$((attempts + 1))
    status_json="$(capture_tailscale_status_json || true)"
    if [[ -n "${status_json}" ]]; then
      backend_state="$(json_value "${status_json}" '.BackendState // empty' || true)"
      current_hostname="$(json_value "${status_json}" '.Self.HostName // empty' || true)"
      if [[ "${backend_state}" == "Running" && "${current_hostname}" == "${TAILSCALE_HOSTNAME_VALUE}" ]]; then
        printf "%s" "${status_json}"
        return 0
      fi
    fi
    sleep 1
  done

  return 1
}

verify_agentbox_tailscale_restart_persistence() {
  local status_json=""

  verify_agentbox_tailscaled_state_file
  log "${tty_tp}verifying${tty_reset} tailscale state survives an agentbox daemon restart"
  execute sudo launchctl kickstart -k "system/${AGENTBOX_TAILSCALED_LABEL}"
  verify_agentbox_tailscaled_launchd_setup
  if ! status_json="$(wait_for_agentbox_tailscale_running_status)"; then
    abort "tailscale did not return as ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset} with backend state ${tty_ts}Running${tty_reset} after restarting the agentbox daemon."
  fi
}

run_agentbox_tailscaled_launchd_setup() {
  local tailscaled_bin=""

  tailscaled_bin="$(tailscaled_bin_path)" || {
    abort "tailscaled binary was not found after installing the agentbox brewfiles."
  }

  execute sudo mkdir -p "${AGENTBOX_LOG_DIR}"
  execute sudo chown root:wheel "${AGENTBOX_LOG_DIR}"
  execute sudo chmod 755 "${AGENTBOX_LOG_DIR}"
  remove_official_tailscale_launchd_service
  remove_homebrew_tailscale_launchd_services
  prepare_tailscaled_statedir
  write_agentbox_tailscaled_plist "${tailscaled_bin}"

  refresh_agentbox_system_launchd_service "${AGENTBOX_TAILSCALED_LABEL}" "${AGENTBOX_TAILSCALED_PLIST_PATH}" "1" "0"
  if ! agentbox_tailscaled_launchd_running; then
    execute sudo launchctl kickstart -k "system/${AGENTBOX_TAILSCALED_LABEL}"
  fi
  verify_agentbox_tailscaled_launchd_setup
}

run_agentbox_tailscale_setup() {
  local status_json=""
  local current_hostname=""
  local backend_state=""
  local tailnet_name=""
  local -a tailscale_args=(
    up
    "--auth-key=${TAILSCALE_AUTHKEY}"
    "--hostname=${TAILSCALE_HOSTNAME_VALUE}"
  )
  local -a tailscale_display_args=(
    up
    "--auth-key=$(mask_secret_for_display "${TAILSCALE_AUTHKEY}")"
    "--hostname=${TAILSCALE_HOSTNAME_VALUE}"
  )

  if tailscale_setup_disabled; then
    log "${tty_tp}skipping${tty_reset} tailscale setup because the auth-key input is disabled"
    return 0
  fi

  check_sudo_access "before tailscale service setup"
  require_command brew
  require_command tailscale
  require_command jq

  log "${tty_tp}starting${tty_reset} ${tty_ts}tailscaled${tty_reset} as a system launchd service"
  run_agentbox_tailscaled_launchd_setup

  status_json="$(capture_tailscale_status_json || true)"
  if [[ -n "${status_json}" ]] && tailscale_status_has_identity "${status_json}"; then
    current_hostname="$(json_value "${status_json}" '.Self.HostName // empty' || true)"
    backend_state="$(json_value "${status_json}" '.BackendState // empty' || true)"
    tailnet_name="$(json_value "${status_json}" '.CurrentTailnet.Name // .CurrentTailnet.MagicDNSSuffix // empty' || true)"

    if [[ -n "${tailnet_name}" ]]; then
      log "${tty_tp}detected${tty_reset} tailscale tailnet ${tty_ts}${tailnet_name}${tty_reset}"
    fi

    if [[ "${current_hostname}" == "${TAILSCALE_HOSTNAME_VALUE}" ]]; then
      if [[ "${backend_state}" == "Running" ]]; then
        log "${tty_tp}skipping${tty_reset} tailscale join; already joined as ${tty_ts}${current_hostname}${tty_reset}"
      else
        log "${tty_tp}resuming${tty_reset} existing tailscale identity ${tty_ts}${current_hostname}${tty_reset} from backend state ${tty_ts}${backend_state:-unknown}${tty_reset}"
        execute sudo tailscale up
        if ! status_json="$(wait_for_agentbox_tailscale_running_status)"; then
          abort "tailscale did not return as ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset} with backend state ${tty_ts}Running${tty_reset} after resuming its existing identity."
        fi
      fi

      verify_agentbox_tailscaled_state_file
      configure_tailscale_operator_user
      configure_tailscale_magicdns_resolver "${status_json}"
      verify_tailscale_serve_prerequisites "${status_json}"
      show_tailscale_status_summary
      return 0
    fi

    abort "tailscale is already joined as ${tty_ts}${current_hostname}${tty_reset}, but agentbox expects ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}; rerun with an agentbox hostname that derives the existing tailscale name, or log out before intentionally replacing the tailscale identity."
  fi

  if [[ -z "${TAILSCALE_AUTHKEY}" ]]; then
    abort_missing_tailscale_authkey
  fi

  log "${tty_tp}joining${tty_reset} ${tty_ts}tailscale${tty_reset} as ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}"
  debug "${tty_tp}running${tty_reset}" sudo tailscale "${tailscale_display_args[@]}"
  if ! sudo tailscale "${tailscale_args[@]}"; then
    abort "agentbox tailscale setup failed."
  fi

  configure_tailscale_operator_user
  verify_agentbox_tailscale_restart_persistence
  status_json="$(wait_for_agentbox_tailscale_running_status || true)"
  if [[ -n "${status_json}" ]]; then
    configure_tailscale_magicdns_resolver "${status_json}"
  else
    warn "could not read tailscale status after join; skipping macos scoped resolver setup."
  fi
  verify_tailscale_serve_prerequisites "${status_json}"
  show_tailscale_status_summary
}

openclaw_runner_home_required() {
  local home

  home="$(user_home_dir "${OPENCLAW_USER}")"
  if [[ -z "${home}" || ! -d "${home}" ]]; then
    abort "openclaw runner user ${tty_ts}${OPENCLAW_USER}${tty_reset} must have a usable home directory before gateway onboarding."
  fi

  printf "%s" "${home}"
}

invoking_admin_home_required() {
  local home

  home="$(user_home_dir "${ADMIN_USER}")"
  if [[ -z "${home}" || ! -d "${home}" ]]; then
    abort "invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset} must have a usable home directory before openclaw app configuration."
  fi

  printf "%s" "${home}"
}

openclaw_runner_path() {
  printf "%s/bin:%s/sbin:/usr/bin:/bin:/usr/sbin:/sbin" "${BREW_PREFIX_VALUE}" "${BREW_PREFIX_VALUE}"
}

openclaw_bin_path() {
  local openclaw_bin

  if [[ -z "${BREW_PREFIX_VALUE}" ]]; then
    resolve_brew_prefix
  fi

  openclaw_bin="${BREW_PREFIX_VALUE}/bin/openclaw"
  if [[ ! -x "${openclaw_bin}" ]]; then
    abort "openclaw cli was not found at ${tty_ts}${openclaw_bin}${tty_reset} after installing the agentbox Brewfile."
  fi

  printf "%s" "${openclaw_bin}"
}

run_as_openclaw_runner() {
  local -a env_args=()
  local -a env_display_args=()
  local env_name
  local env_value
  local extra_env_names="${OPENCLAW_RUNNER_EXTRA_ENV_NAMES:-}"
  local home
  local path_value
  local stdin_path="${OPENCLAW_RUNNER_STDIN_PATH:-}"
  local stdout_path="${OPENCLAW_RUNNER_STDOUT_PATH:-}"

  home="$(openclaw_runner_home_required)"
  path_value="$(openclaw_runner_path)"

  env_args=(
    "HOME=${home}"
    "USER=${OPENCLAW_USER}"
    "LOGNAME=${OPENCLAW_USER}"
    "PATH=${path_value}"
    "OPENCLAW_HOME=${home}"
    "OPENCLAW_STATE_DIR=${home}/.openclaw"
  )
  env_display_args=("${env_args[@]}")

  for env_name in ${extra_env_names}; do
    if ! env_name_valid "${env_name}"; then
      abort "internal openclaw runner environment variable name ${tty_ts}${env_name}${tty_reset} is invalid."
    fi

    env_value="${!env_name-}"
    if [[ -z "${env_value}" ]]; then
      continue
    fi

    env_args+=("${env_name}=${env_value}")
    env_display_args+=("${env_name}=$(mask_secret_for_display "${env_value}")")
  done

  debug "${tty_tp}running${tty_reset}" sudo -u "${OPENCLAW_USER}" env "${env_display_args[@]}" "$@"
  if [[ -n "${stdin_path}" && -n "${stdout_path}" ]]; then
    debug "${tty_tp}using${tty_reset}" "${stdin_path}" "for openclaw runner stdin and" "${stdout_path}" "for stdout"
    # shellcheck disable=SC2024
    sudo -u "${OPENCLAW_USER}" env "${env_args[@]}" "$@" < "${stdin_path}" > "${stdout_path}"
  elif [[ -n "${stdin_path}" ]]; then
    debug "${tty_tp}using${tty_reset}" "${stdin_path}" "for openclaw runner stdin"
    # shellcheck disable=SC2024
    sudo -u "${OPENCLAW_USER}" env "${env_args[@]}" "$@" < "${stdin_path}"
  elif [[ -n "${stdout_path}" ]]; then
    debug "${tty_tp}using${tty_reset}" "${stdout_path}" "for openclaw runner stdout"
    # shellcheck disable=SC2024
    sudo -u "${OPENCLAW_USER}" env "${env_args[@]}" "$@" > "${stdout_path}"
  else
    sudo -u "${OPENCLAW_USER}" env "${env_args[@]}" "$@"
  fi
}

run_as_invoking_admin() {
  local home
  local path_value

  home="$(invoking_admin_home_required)"
  path_value="$(openclaw_runner_path)"

  debug "${tty_tp}running${tty_reset}" /usr/bin/env -i "HOME=${home}" "USER=${ADMIN_USER}" "LOGNAME=${ADMIN_USER}" "PATH=${path_value}" "$@"
  /usr/bin/env -i "HOME=${home}" "USER=${ADMIN_USER}" "LOGNAME=${ADMIN_USER}" "PATH=${path_value}" "$@"
}

execute_as_openclaw_runner() {
  if ! run_as_openclaw_runner "$@"; then
    abort "$(printf "failed during openclaw runner command: %s" "$(shell_join "$@")")"
  fi
}

openclaw_gateway_configuration_initialized() {
  local openclaw_bin="$1"
  local gateway_mode

  if ! run_as_openclaw_runner "${openclaw_bin}" config validate --json >/dev/null 2>&1; then
    debug "${tty_tp}detected${tty_reset}" missing or invalid openclaw gateway configuration for runner "${OPENCLAW_USER}"
    return 1
  fi

  gateway_mode="$(run_as_openclaw_runner "${openclaw_bin}" config get gateway.mode 2>/dev/null)" || {
    debug "${tty_tp}detected${tty_reset}" openclaw gateway configuration without a mode for runner "${OPENCLAW_USER}"
    return 1
  }
  gateway_mode="$(trim_whitespace "${gateway_mode}")"
  if [[ "${gateway_mode}" != "local" ]]; then
    debug "${tty_tp}detected${tty_reset}" openclaw gateway mode "${gateway_mode}" instead of local for runner "${OPENCLAW_USER}"
    return 1
  fi

  debug "${tty_tp}detected${tty_reset}" valid local openclaw gateway configuration for runner "${OPENCLAW_USER}"
  return 0
}

preserve_existing_openclaw_gateway_configuration() {
  local openclaw_bin="$1"
  local existing_bind
  local existing_port
  local existing_tailscale_mode

  existing_bind="$(run_as_openclaw_runner "${openclaw_bin}" config get gateway.bind 2>/dev/null || true)"
  existing_bind="$(trim_whitespace "${existing_bind}")"
  if [[ -n "${existing_bind}" ]]; then
    OPENCLAW_GATEWAY_BIND_VALUE="${existing_bind}"
  fi

  if [[ -z "${OPENCLAW_GATEWAY_PORT_EXPLICIT}" ]]; then
    existing_port="$(run_as_openclaw_runner "${openclaw_bin}" config get gateway.port 2>/dev/null || true)"
    existing_port="$(trim_whitespace "${existing_port}")"
    if openclaw_gateway_port_valid "${existing_port}"; then
      OPENCLAW_GATEWAY_PORT="${existing_port}"
    fi
  fi

  existing_tailscale_mode="$(run_as_openclaw_runner "${openclaw_bin}" config get gateway.tailscale.mode 2>/dev/null || true)"
  existing_tailscale_mode="$(trim_whitespace "${existing_tailscale_mode}")"
  case "${existing_tailscale_mode}" in
    off | serve | funnel) OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE="${existing_tailscale_mode}" ;;
  esac

  debug "${tty_tp}preserving${tty_reset}" existing openclaw gateway "bind ${OPENCLAW_GATEWAY_BIND_VALUE}, tailscale mode ${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}, and port ${OPENCLAW_GATEWAY_PORT}"
}

capture_existing_openclaw_gateway_token() {
  local jq_bin="${BREW_PREFIX_VALUE}/bin/jq"
  local output_path="$1"
  local runner_config

  runner_config="$(openclaw_gateway_state_dir)/openclaw.json"
  /usr/bin/install -m 600 /dev/null "${output_path}"
  if ! run_as_openclaw_runner "${jq_bin}" -ce '.gateway.auth.token | select(type == "string" and length > 0 and (startswith("$") | not) and . != "__OPENCLAW_REDACTED__")' "${runner_config}" > "${output_path}"; then
    rm -f "${output_path}"
    return 1
  fi
}

restore_existing_openclaw_gateway_token() {
  local jq_bin="${BREW_PREFIX_VALUE}/bin/jq"
  local primary_group
  local runner_config
  local token_path="$1"
  local updated_config="${BOOT_TMPDIR}/openclaw-runner-preserved-config.json"

  [[ -f "${token_path}" ]] || return 0
  runner_config="$(openclaw_gateway_state_dir)/openclaw.json"
  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  /usr/bin/install -m 600 /dev/null "${updated_config}"
  # shellcheck disable=SC2024
  if ! sudo "${jq_bin}" --slurpfile gateway_token "${token_path}" '.gateway.auth.token = $gateway_token[0]' "${runner_config}" > "${updated_config}"; then
    rm -f "${token_path}" "${updated_config}"
    abort "failed to preserve the existing openclaw Gateway token during reconciliation."
  fi
  execute sudo /usr/bin/install -o "${OPENCLAW_USER}" -g "${primary_group}" -m 600 "${updated_config}" "${runner_config}"
  rm -f "${token_path}" "${updated_config}"
  if ! run_as_openclaw_runner "$(openclaw_bin_path)" config validate --json >/dev/null; then
    abort "openclaw gateway configuration validation failed after preserving its existing token."
  fi
}

openclaw_help_has_option() {
  local openclaw_bin="$1"
  local option="$2"
  local help_output
  shift 2

  help_output="$(run_as_openclaw_runner "${openclaw_bin}" "$@" --help 2>&1)" || return 1
  grep -Fq -- "${option}" <<< "${help_output}"
}

validate_openclaw_cli_contract() {
  local openclaw_bin="$1"
  local -a missing=()

  openclaw_help_has_option "${openclaw_bin}" "--no-install-daemon" onboard || missing+=("onboard --no-install-daemon")
  openclaw_help_has_option "${openclaw_bin}" "--skip-health" onboard || missing+=("onboard --skip-health")
  openclaw_help_has_option "${openclaw_bin}" "--force" gateway install || missing+=("gateway install --force")
  openclaw_help_has_option "${openclaw_bin}" "--require-rpc" gateway status || missing+=("gateway status --require-rpc")

  if array_has_values missing; then
    abort "installed openclaw cli is incompatible with agentbox gateway activation; missing required options: ${tty_ts}$(array_join ", " missing)${tty_reset}. Update openclaw and rerun."
  fi
}

run_openclaw_gateway_onboarding() {
  local openclaw_bin="$1"
  local reconcile_existing="${2:-0}"
  local -a openclaw_args=()
  local custom_auth_env_value
  local onboarding_env_names
  local runner_stdin_path=""
  local runner_stdout_path=""

  onboarding_env_names="$(openclaw_auth_choice_present_env_name_list "${OPENCLAW_AUTH_CHOICE}")"
  if [[ -n "${OPENCLAW_AUTH_ENV}" ]]; then
    custom_auth_env_value="${!OPENCLAW_AUTH_ENV-}"
    if [[ -n "${custom_auth_env_value}" ]]; then
      case " ${onboarding_env_names} " in
        *" ${OPENCLAW_AUTH_ENV} "*) ;;
        *) onboarding_env_names="${onboarding_env_names}${onboarding_env_names:+ }${OPENCLAW_AUTH_ENV}" ;;
      esac
    fi
  fi

  openclaw_args=(
    onboard
    --mode local
    --flow quickstart
    --auth-choice "${OPENCLAW_AUTH_CHOICE}"
    --gateway-port "${OPENCLAW_GATEWAY_PORT}"
    --gateway-bind "${OPENCLAW_GATEWAY_BIND_VALUE}"
    --tailscale "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}"
    --gateway-auth token
    --skip-bootstrap
    --skip-skills
    --skip-ui
    --skip-hooks
    --skip-health
    --no-install-daemon
    --suppress-gateway-token-output
  )

  if noninteractive_mode_enabled || [[ "${reconcile_existing}" == "1" ]]; then
    openclaw_args+=(--non-interactive --accept-risk --json)
  else
    if [[ ! -t 0 ]]; then
      runner_stdin_path="$(interactive_tty_input)"
    fi
    if [[ ! -t 1 && -w /dev/tty ]]; then
      runner_stdout_path="/dev/tty"
    fi
  fi

  if [[ "${reconcile_existing}" == "1" ]]; then
    log "${tty_tp}reconciling${tty_reset} existing openclaw gateway configuration non-interactively for runner ${tty_ts}${OPENCLAW_USER}${tty_reset} without installing a service, with loopback bind, tailscale exposure ${tty_ts}${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}${tty_reset}, and port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}"
  else
    log "${tty_tp}configuring${tty_reset} openclaw gateway for runner ${tty_ts}${OPENCLAW_USER}${tty_reset} in ${tty_ts}$(openclaw_onboarding_mode_display)${tty_reset} mode without installing a service, with loopback bind, tailscale exposure ${tty_ts}${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}${tty_reset}, and port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}"
  fi
  OPENCLAW_RUNNER_EXTRA_ENV_NAMES="${onboarding_env_names}" \
    OPENCLAW_RUNNER_STDIN_PATH="${runner_stdin_path}" \
    OPENCLAW_RUNNER_STDOUT_PATH="${runner_stdout_path}" \
    execute_as_openclaw_runner "${openclaw_bin}" "${openclaw_args[@]}"
}

configure_openclaw_tailscale_auth() {
  local jq_bin="${BREW_PREFIX_VALUE}/bin/jq"
  local openclaw_bin="$1"
  local runner_config

  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" != "serve" ]]; then
    return 0
  fi

  runner_config="$(openclaw_gateway_state_dir)/openclaw.json"
  log "${tty_tp}allowing${tty_reset} verified tailscale identities for openclaw gateway authentication"
  if ! run_as_openclaw_runner "${openclaw_bin}" config set gateway.auth.allowTailscale true --strict-json >/dev/null; then
    abort "failed to allow tailscale identity authentication for openclaw gateway runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi

  if ! run_as_openclaw_runner "${openclaw_bin}" config validate --json >/dev/null; then
    abort "openclaw gateway configuration validation failed after enabling tailscale identity authentication for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi

  if ! run_as_openclaw_runner "${jq_bin}" -e '.gateway.auth.allowTailscale == true' "${runner_config}" >/dev/null; then
    abort "openclaw gateway tailscale identity authentication verification failed for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi
}

openclaw_default_avatar_data_uri() {
  local encoded

  if ! encoded="$(/usr/bin/base64 < "${AGENTBOX_DEFAULT_AVATAR_SOURCE}" | /usr/bin/tr -d '\r\n')" || [[ -z "${encoded}" ]]; then
    abort "failed to encode openclaw fallback gateway avatar from ${tty_ts}$(display_home_path "${AGENTBOX_DEFAULT_AVATAR_SOURCE}")${tty_reset}."
  fi

  printf "data:image/png;base64,%s" "${encoded}"
}

configure_openclaw_ui_assistant_branding() {
  local avatar_data_uri
  local batch_file
  local jq_bin="${BREW_PREFIX_VALUE}/bin/jq"
  local openclaw_bin="$1"
  local primary_group
  local runner_config

  avatar_data_uri="$(openclaw_default_avatar_data_uri)"
  batch_file="$(openclaw_gateway_state_dir)/.agentbox-ui-assistant.batch.json"
  runner_config="$(openclaw_gateway_state_dir)/openclaw.json"
  primary_group="$(user_primary_group "${OPENCLAW_USER}")"

  # shellcheck disable=SC2016
  if ! "${jq_bin}" -n \
    --arg assistant_name "${OPENCLAW_UI_ASSISTANT_NAME}" \
    --arg assistant_avatar "${avatar_data_uri}" \
    --arg seam_color "${OPENCLAW_UI_SEAM_COLOR}" \
    '[
      {"path":"ui.assistant.name","value":$assistant_name},
      {"path":"ui.assistant.avatar","value":$assistant_avatar},
      {"path":"ui.seamColor","value":$seam_color}
    ]' | sudo tee "${batch_file}" >/dev/null; then
    sudo rm -f "${batch_file}" >/dev/null 2>&1 || true
    abort "failed to prepare openclaw fallback gateway branding for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi

  execute sudo chown "${OPENCLAW_USER}:${primary_group}" "${batch_file}"
  execute sudo chmod 600 "${batch_file}"

  log "${tty_tp}configuring${tty_reset} openclaw fallback gateway branding as ${tty_ts}${OPENCLAW_UI_ASSISTANT_NAME}${tty_reset}"
  if ! run_as_openclaw_runner "${openclaw_bin}" config set --batch-file "${batch_file}" >/dev/null; then
    sudo rm -f "${batch_file}" >/dev/null 2>&1 || true
    abort "failed to configure openclaw fallback gateway branding for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi

  if ! run_as_openclaw_runner "${openclaw_bin}" config validate --json >/dev/null; then
    sudo rm -f "${batch_file}" >/dev/null 2>&1 || true
    abort "openclaw gateway configuration validation failed after setting fallback branding for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi

  # shellcheck disable=SC2016
  if ! run_as_openclaw_runner "${jq_bin}" -e \
    --arg expected_name "${OPENCLAW_UI_ASSISTANT_NAME}" \
    --arg expected_seam_color "${OPENCLAW_UI_SEAM_COLOR}" \
    --slurpfile updates "${batch_file}" \
    '.ui.assistant.name == $expected_name and .ui.assistant.avatar == $updates[0][1].value and .ui.seamColor == $expected_seam_color' \
    "${runner_config}" >/dev/null; then
    sudo rm -f "${batch_file}" >/dev/null 2>&1 || true
    abort "openclaw fallback gateway branding verification failed for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}."
  fi

  execute sudo rm -f "${batch_file}"
}

openclaw_native_gateway_launch_agent_plist_path() {
  local user="$1"
  local home

  home="$(user_home_dir "${user}")"
  if [[ -z "${home}" ]]; then
    abort "could not determine home directory for user ${tty_ts}${user}${tty_reset} while removing the openclaw native gateway service."
  fi

  printf "%s/Library/LaunchAgents/%s.plist" "${home}" "${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}"
}

openclaw_native_gateway_launch_agent_loaded() {
  local uid="$1"

  [[ -n "${uid}" ]] && sudo launchctl print "gui/${uid}/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}" >/dev/null 2>&1
}

openclaw_gateway_managed_env_content() {
  local health_command="${AGENTBOX_OPT_DIR}/bin/health.sh --report"

  printf 'OPENCLAW_MDNS_HOSTNAME='
  dotenv_double_quote "${AGENTBOX_HOSTNAME_VALUE}"
  printf '\nAGENTBOX_MANAGED="1"\nAGENTBOX_SERVICE_KIND='
  dotenv_double_quote "${AGENTBOX_OPENCLAW_SERVICE_KIND}"
  printf '\nAGENTBOX_VERSION='
  dotenv_double_quote "${SCRIPT_VERSION}"
  printf '\nAGENTBOX_HEALTH_COMMAND='
  dotenv_double_quote "${health_command}"
  printf '\n'
}

openclaw_gateway_dotenv_has_value() {
  local expected
  local key="$1"
  local value="$2"
  local path="${3:-$(openclaw_gateway_dotenv_path)}"

  expected="${key}=$(dotenv_double_quote "${value}")"
  sudo /usr/bin/grep -Fqx -- "${expected}" "${path}" 2>/dev/null
}

openclaw_native_gateway_service_env_has_value() {
  local expected
  local key="$1"
  local value="$2"
  local path="${3:-$(openclaw_native_gateway_service_env_file_path)}"

  expected="export ${key}=$(shell_single_quote "${value}")"
  sudo /usr/bin/grep -Fqx -- "${expected}" "${path}" 2>/dev/null
}

openclaw_native_gateway_agentbox_managed() {
  local dotenv_path
  local service_env_path

  dotenv_path="$(openclaw_gateway_dotenv_path)"
  service_env_path="$(openclaw_native_gateway_service_env_file_path)"

  if openclaw_gateway_dotenv_has_value AGENTBOX_MANAGED 1 "${dotenv_path}" &&
    openclaw_gateway_dotenv_has_value AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}" "${dotenv_path}"; then
    return 0
  fi

  openclaw_native_gateway_service_env_has_value AGENTBOX_MANAGED 1 "${service_env_path}" &&
    openclaw_native_gateway_service_env_has_value AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}" "${service_env_path}"
}

openclaw_native_gateway_managed_environment_current() {
  local service_env_path

  service_env_path="$(openclaw_native_gateway_service_env_file_path)"

  openclaw_native_gateway_service_env_has_value OPENCLAW_MDNS_HOSTNAME "${AGENTBOX_HOSTNAME_VALUE}" "${service_env_path}" &&
    openclaw_native_gateway_service_env_has_value AGENTBOX_MANAGED 1 "${service_env_path}" &&
    openclaw_native_gateway_service_env_has_value AGENTBOX_SERVICE_KIND "${AGENTBOX_OPENCLAW_SERVICE_KIND}" "${service_env_path}" &&
    openclaw_native_gateway_service_env_has_value AGENTBOX_VERSION "${SCRIPT_VERSION}" "${service_env_path}" &&
    openclaw_native_gateway_service_env_has_value AGENTBOX_HEALTH_COMMAND "${AGENTBOX_OPT_DIR}/bin/health.sh --report" "${service_env_path}"
}

write_openclaw_gateway_managed_environment() {
  local dotenv_path
  local primary_group
  local state_dir
  local updated_path="${BOOT_TMPDIR}/openclaw-managed.env.$$"

  state_dir="$(openclaw_gateway_state_dir)"
  dotenv_path="$(openclaw_gateway_dotenv_path)"
  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  if sudo test -L "${dotenv_path}"; then
    abort "refusing to replace symlinked openclaw environment file ${tty_ts}${dotenv_path}${tty_reset}."
  fi

  if sudo test -f "${dotenv_path}"; then
    # shellcheck disable=SC2024
    sudo /usr/bin/awk '
      BEGIN {
        managed["OPENCLAW_MDNS_HOSTNAME"] = 1
        managed["AGENTBOX_MANAGED"] = 1
        managed["AGENTBOX_SERVICE_KIND"] = 1
        managed["AGENTBOX_VERSION"] = 1
        managed["AGENTBOX_HEALTH_COMMAND"] = 1
      }
      {
        key = $0
        sub(/^[[:space:]]*(export[[:space:]]+)?/, "", key)
        sub(/[[:space:]]*=.*/, "", key)
        if (key in managed) next
        print
      }
    ' "${dotenv_path}" > "${updated_path}"
  else
    : > "${updated_path}"
  fi
  openclaw_gateway_managed_env_content >> "${updated_path}"

  execute sudo /usr/bin/install -d -o "${OPENCLAW_USER}" -g "${primary_group}" -m 700 "${state_dir}"
  execute sudo /usr/bin/install -o "${OPENCLAW_USER}" -g "${primary_group}" -m 600 "${updated_path}" "${dotenv_path}"
  rm -f "${updated_path}"
  debug "${tty_tp}configured${tty_reset}" managed openclaw gateway environment for runner "${OPENCLAW_USER}"
}

prepare_openclaw_native_gateway_log() {
  local log_dir
  local log_path
  local primary_group

  log_dir="$(openclaw_native_gateway_log_dir)"
  log_path="$(openclaw_native_gateway_log_path)"
  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  execute sudo /usr/bin/install -d -o "${OPENCLAW_USER}" -g "${primary_group}" -m 700 "${log_dir}"
  execute sudo touch "${log_path}"
  execute sudo chown "${OPENCLAW_USER}:${primary_group}" "${log_path}"
  execute sudo chmod 600 "${log_path}"
}

openclaw_gateway_port_pids() {
  /usr/sbin/lsof -nP -iTCP:"${OPENCLAW_GATEWAY_PORT}" -sTCP:LISTEN -t 2>/dev/null | /usr/bin/sort -u || true
}

openclaw_gateway_port_owner() {
  local pid="$1"

  /bin/ps -o user= -p "${pid}" 2>/dev/null | awk '{$1=$1; print}'
}

validate_openclaw_gateway_port_owner() {
  local owner
  local pid
  local pids
  local runner_uid

  pids="$(openclaw_gateway_port_pids)"
  [[ -n "${pids}" ]] || return 0
  runner_uid="$(id -u "${OPENCLAW_USER}" 2>/dev/null || true)"

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    owner="$(openclaw_gateway_port_owner "${pid}")"
    if [[ "${owner}" != "${OPENCLAW_USER}" ]] || ! openclaw_native_gateway_launch_agent_loaded "${runner_uid}"; then
      abort "unexpected process owns gateway port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}: PID ${tty_ts}${pid}${tty_reset}, owner ${tty_ts}${owner:-unknown}${tty_reset}. agentbox will not kill an unverified process."
    fi
  done <<< "${pids}"
}

reconcile_openclaw_admin_native_gateway_conflict() {
  local admin_home
  local backup_path
  local native_env_dir
  local native_env_file
  local native_env_wrapper
  local openclaw_bin="$1"
  local plist_path
  local service_present="0"
  local timestamp
  local uid

  admin_home="$(invoking_admin_home_required)"
  uid="$(id -u "${ADMIN_USER}" 2>/dev/null || true)"
  plist_path="$(openclaw_native_gateway_launch_agent_plist_path "${ADMIN_USER}")"
  native_env_dir="${admin_home}/.openclaw/service-env"
  native_env_file="${native_env_dir}/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}.env"
  native_env_wrapper="${native_env_dir}/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}-env-wrapper.sh"
  if openclaw_native_gateway_launch_agent_loaded "${uid}" || sudo test -f "${plist_path}"; then
    service_present="1"
  elif ! sudo test -f "${native_env_file}" && ! sudo test -f "${native_env_wrapper}"; then
    return 0
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_path="${admin_home}/.openclaw.agentbox-backup-${timestamp}-$$"
  if sudo test -d "${admin_home}/.openclaw"; then
    log "${tty_tp}backing up${tty_reset} conflicting invoking-admin openclaw state to ${tty_ts}${backup_path}${tty_reset}"
    execute sudo cp -pR "${admin_home}/.openclaw" "${backup_path}"
    execute sudo chown -R "${ADMIN_USER}:$(user_primary_group "${ADMIN_USER}")" "${backup_path}"
    execute sudo chmod -R go-rwx "${backup_path}"
  fi

  if [[ "${service_present}" == "1" ]]; then
    log "${tty_tp}uninstalling${tty_reset} conflicting invoking-admin native gateway ${tty_ts}${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}${tty_reset}"
    if ! run_as_invoking_admin "${openclaw_bin}" gateway uninstall >/dev/null 2>&1; then
      abort "failed to uninstall the invoking-admin native openclaw gateway; backup retained at ${tty_ts}${backup_path}${tty_reset}."
    fi

    if openclaw_native_gateway_launch_agent_loaded "${uid}" || sudo test -f "${plist_path}"; then
      abort "invoking-admin native openclaw gateway is still present after uninstall; resolve the conflict and rerun agentbox."
    fi
  fi

  log "${tty_tp}removing${tty_reset} invoking-admin native gateway service environment artifacts"
  execute sudo rm -f "${native_env_file}" "${native_env_wrapper}"
  sudo rmdir "${native_env_dir}" >/dev/null 2>&1 || true
}

openclaw_admin_app_state_dir() {
  printf "%s/.openclaw" "$(invoking_admin_home_required)"
}

openclaw_admin_app_attach_only_marker_path() {
  printf "%s/%s" "$(invoking_admin_home_required)" "${OPENCLAW_DISABLE_LAUNCH_AGENT_MARKER}"
}

openclaw_admin_app_config_path() {
  printf "%s/openclaw.json" "$(openclaw_admin_app_state_dir)"
}

ensure_openclaw_admin_app_attach_only() {
  local marker_path
  local primary_group
  local state_dir

  primary_group="$(user_primary_group "${ADMIN_USER}")"
  state_dir="$(openclaw_admin_app_state_dir)"
  marker_path="$(openclaw_admin_app_attach_only_marker_path)"

  execute sudo /usr/bin/install -d -o "${ADMIN_USER}" -g "${primary_group}" -m 700 "${state_dir}"
  execute sudo touch "${marker_path}"
  execute sudo chown "${ADMIN_USER}:${primary_group}" "${marker_path}"
  execute sudo chmod 600 "${marker_path}"
  log "${tty_tp}configured${tty_reset} openclaw app attach-only mode for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset}"
}

file_sha256() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

reconcile_openclaw_admin_app_config() {
  local admin_config
  local admin_token_json
  local admin_token_hash
  local batch_file
  local jq_bin="${BREW_PREFIX_VALUE}/bin/jq"
  local openclaw_bin="$1"
  local primary_group
  local runner_config
  local runner_token_json
  local runner_token_hash

  runner_config="$(openclaw_gateway_state_dir)/openclaw.json"
  admin_config="$(openclaw_admin_app_config_path)"
  runner_token_json="${BOOT_TMPDIR}/openclaw-runner-gateway-token.json"
  admin_token_json="${BOOT_TMPDIR}/openclaw-admin-gateway-token.json"
  batch_file="${BOOT_TMPDIR}/openclaw-admin-config.batch.json"
  primary_group="$(user_primary_group "${ADMIN_USER}")"

  if [[ ! -x "${jq_bin}" ]]; then
    abort "jq was not found at ${tty_ts}${jq_bin}${tty_reset} while configuring the openclaw app."
  fi

  /usr/bin/install -m 600 /dev/null "${runner_token_json}"
  /usr/bin/install -m 600 /dev/null "${admin_token_json}"
  /usr/bin/install -m 600 /dev/null "${batch_file}"

  if ! run_as_openclaw_runner "${jq_bin}" -ce '.gateway.auth.token | select(type == "string" and length > 0 and (startswith("$") | not) and . != "__OPENCLAW_REDACTED__")' "${runner_config}" > "${runner_token_json}"; then
    rm -f "${runner_token_json}" "${admin_token_json}" "${batch_file}"
    warn "skipping openclaw app gateway credential synchronization for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset} because the runner gateway token is not stored as a plaintext config value; attach-only mode remains enabled."
    return 0
  fi

  # shellcheck disable=SC2016
  if ! "${jq_bin}" -n \
    --slurpfile gateway_token "${runner_token_json}" \
    --argjson gateway_port "${OPENCLAW_GATEWAY_PORT}" \
    '[
      {"path":"gateway.mode","value":"local"},
      {"path":"gateway.port","value":$gateway_port},
      {"path":"gateway.auth.mode","value":"token"},
      {"path":"gateway.auth.token","value":$gateway_token[0]}
    ]' > "${batch_file}"; then
    rm -f "${runner_token_json}" "${admin_token_json}" "${batch_file}"
    abort "failed to prepare the openclaw app configuration update for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset}."
  fi

  log "${tty_tp}synchronizing${tty_reset} openclaw app gateway configuration for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset}"
  if ! run_as_invoking_admin "${openclaw_bin}" config set --batch-file "${batch_file}" >/dev/null; then
    rm -f "${runner_token_json}" "${admin_token_json}" "${batch_file}"
    abort "failed to synchronize the openclaw app gateway configuration for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset}."
  fi

  execute sudo chown "${ADMIN_USER}:${primary_group}" "${admin_config}"
  execute sudo chmod 600 "${admin_config}"

  if ! run_as_invoking_admin "${openclaw_bin}" config validate --json >/dev/null; then
    rm -f "${runner_token_json}" "${admin_token_json}" "${batch_file}"
    abort "openclaw app configuration validation failed for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset} after synchronization."
  fi

  if ! run_as_invoking_admin "${jq_bin}" -ce '.gateway.auth.token | select(type == "string" and length > 0)' "${admin_config}" > "${admin_token_json}"; then
    rm -f "${runner_token_json}" "${admin_token_json}" "${batch_file}"
    abort "openclaw app gateway token is missing for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset} after synchronization."
  fi

  runner_token_hash="$(file_sha256 "${runner_token_json}")"
  admin_token_hash="$(file_sha256 "${admin_token_json}")"
  rm -f "${runner_token_json}" "${admin_token_json}" "${batch_file}"

  if [[ -z "${runner_token_hash}" || "${runner_token_hash}" != "${admin_token_hash}" ]]; then
    abort "openclaw app gateway token verification failed for invoking admin ${tty_ts}${ADMIN_USER}${tty_reset} after synchronization."
  fi

  debug "${tty_tp}verified${tty_reset}" openclaw app gateway token synchronization for invoking admin "${ADMIN_USER}" by sha256 equality
}

openclaw_finalizer_executable_path() {
  printf "%s/.local/libexec/agentbox-openclaw-finalize" "$(openclaw_runner_home_required)"
}

openclaw_finalizer_plist_path() {
  printf "%s/Library/LaunchAgents/%s.plist" "$(openclaw_runner_home_required)" "${AGENTBOX_OPENCLAW_FINALIZER_LABEL}"
}

openclaw_finalizer_state_dir() {
  printf "%s/.agentbox" "$(openclaw_runner_home_required)"
}

openclaw_finalizer_state_path() {
  printf "%s/openclaw-gateway-finalizer-state" "$(openclaw_finalizer_state_dir)"
}

openclaw_finalizer_log_dir() {
  printf "%s/Library/Logs/agentbox" "$(openclaw_runner_home_required)"
}

openclaw_finalizer_template_content() {
  local executable
  local finalizer_label
  local finalizer_state_dir
  local gateway_label
  local home
  local openclaw_bin
  local openclaw_path
  local openclaw_state_dir
  local rendered
  local stderr_log
  local stdout_log
  local user

  home="$(openclaw_runner_home_required)"
  executable="$(xml_escape "$(openclaw_finalizer_executable_path)")"
  finalizer_label="$(xml_escape "${AGENTBOX_OPENCLAW_FINALIZER_LABEL}")"
  finalizer_state_dir="$(xml_escape "$(openclaw_finalizer_state_dir)")"
  gateway_label="$(xml_escape "${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}")"
  openclaw_bin="$(xml_escape "${BREW_PREFIX_VALUE}/bin/openclaw")"
  openclaw_path="$(xml_escape "$(openclaw_runner_path)")"
  openclaw_state_dir="$(xml_escape "$(openclaw_gateway_state_dir)")"
  stderr_log="$(xml_escape "$(openclaw_finalizer_log_dir)/openclaw-finalize.error.log")"
  stdout_log="$(xml_escape "$(openclaw_finalizer_log_dir)/openclaw-finalize.log")"
  user="$(xml_escape "${OPENCLAW_USER}")"
  home="$(xml_escape "${home}")"
  rendered="$(cat "${AGENTBOX_OPENCLAW_FINALIZER_PLIST_TEMPLATE}")" || abort "failed to read openclaw Aqua finalizer template."
  rendered="${rendered//__AGENTBOX_OPENCLAW_FINALIZER_LABEL__/${finalizer_label}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_FINALIZER_EXECUTABLE__/${executable}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_HOME__/${home}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_USER__/${user}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_PATH__/${openclaw_path}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_STATE_DIR__/${openclaw_state_dir}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_BIN__/${openclaw_bin}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_LABEL__/${gateway_label}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_FINALIZER_STATE_DIR__/${finalizer_state_dir}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_FINALIZER_STDOUT_LOG__/${stdout_log}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_FINALIZER_STDERR_LOG__/${stderr_log}}"

  if [[ "${rendered}" == *"__AGENTBOX_"* ]]; then
    abort "openclaw Aqua finalizer template contains unresolved placeholders."
  fi
  printf "%s\n" "${rendered}"
}

write_openclaw_finalizer_state() {
  local primary_group
  local state="$1"
  local tmp_path="${BOOT_TMPDIR}/openclaw-finalizer-state.$$"

  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  printf 'status=%s\nstep=staged\nupdated_at=%s\nexit_code=0\n' "${state}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${tmp_path}"
  execute sudo /usr/bin/install -o "${OPENCLAW_USER}" -g "${primary_group}" -m 600 "${tmp_path}" "$(openclaw_finalizer_state_path)"
  rm -f "${tmp_path}"
}

stage_openclaw_finalizer() {
  local home
  local plist_path
  local primary_group
  local rendered_path

  home="$(openclaw_runner_home_required)"
  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  plist_path="$(openclaw_finalizer_plist_path)"
  rendered_path="${BOOT_TMPDIR}/$(basename "${plist_path}").rendered.$$"

  execute sudo /usr/bin/install -d -o "${OPENCLAW_USER}" -g "${primary_group}" -m 700 \
    "${home}/.local" "${home}/.local/libexec" \
    "$(openclaw_finalizer_state_dir)" "$(openclaw_finalizer_log_dir)"
  execute sudo /usr/bin/install -d -o "${OPENCLAW_USER}" -g "${primary_group}" -m 755 "${home}/Library/LaunchAgents"
  execute sudo /usr/bin/install -o "${OPENCLAW_USER}" -g "${primary_group}" -m 700 \
    "${AGENTBOX_OPENCLAW_FINALIZER_SOURCE}" "$(openclaw_finalizer_executable_path)"

  openclaw_finalizer_template_content > "${rendered_path}"
  execute /usr/bin/plutil -lint "${rendered_path}"
  execute sudo /usr/bin/install -o "${OPENCLAW_USER}" -g "${primary_group}" -m 644 "${rendered_path}" "${plist_path}"
  rm -f "${rendered_path}"
  write_openclaw_finalizer_state pending_first_login
}

openclaw_runner_gui_domain_active() {
  local uid

  uid="$(id -u "${OPENCLAW_USER}" 2>/dev/null || true)"
  [[ -n "${uid}" ]] && sudo launchctl print "gui/${uid}" >/dev/null 2>&1
}

openclaw_finalizer_state_value() {
  local state_path

  state_path="$(openclaw_finalizer_state_path)"
  sudo awk -F= '$1 == "status" {print $2; exit}' "${state_path}" 2>/dev/null || true
}

cleanup_stale_openclaw_finalizer() {
  local uid

  uid="$(id -u "${OPENCLAW_USER}" 2>/dev/null || true)"
  if [[ -n "${uid}" ]]; then
    sudo launchctl bootout "gui/${uid}/${AGENTBOX_OPENCLAW_FINALIZER_LABEL}" >/dev/null 2>&1 || true
  fi
  sudo rm -f "$(openclaw_finalizer_plist_path)" "$(openclaw_finalizer_state_path)" >/dev/null 2>&1 || true
}

activate_openclaw_finalizer() {
  local attempts="0"
  local state
  local uid

  uid="$(id -u "${OPENCLAW_USER}")"
  sudo launchctl bootout "gui/${uid}/${AGENTBOX_OPENCLAW_FINALIZER_LABEL}" >/dev/null 2>&1 || true
  if ! sudo launchctl bootstrap "gui/${uid}" "$(openclaw_finalizer_plist_path)"; then
    OPENCLAW_GATEWAY_SETUP_STATUS="failed"
    warn "failed to bootstrap the openclaw Aqua finalizer; inspect $(openclaw_finalizer_log_dir)/openclaw-finalize.error.log and rerun agentbox."
    return 0
  fi

  while [[ "${attempts}" -lt 45 ]]; do
    if openclaw_native_gateway_launch_agent_loaded "${uid}" && openclaw_gateway_status_ready "${BREW_PREFIX_VALUE}/bin/openclaw"; then
      OPENCLAW_GATEWAY_SETUP_STATUS="healthy"
      log "${tty_tp}verified${tty_reset} native openclaw LaunchAgent and RPC health for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
      return 0
    fi
    state="$(openclaw_finalizer_state_value)"
    if [[ "${state}" == "failed" ]]; then
      break
    fi
    attempts=$((attempts + 1))
    sleep 2
  done

  OPENCLAW_GATEWAY_SETUP_STATUS="failed"
  warn "openclaw Aqua finalizer failed; inspect $(openclaw_finalizer_log_dir)/openclaw-finalize.error.log and rerun agentbox."
}

openclaw_gateway_status_ready() {
  local openclaw_bin="$1"

  run_as_openclaw_runner "${openclaw_bin}" gateway status --require-rpc --timeout 10000 >/dev/null 2>&1
}

openclaw_gateway_tailscale_serve_route_ready() {
  local status=""
  local tailscale_bin="${BREW_PREFIX_VALUE}/bin/tailscale"

  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" != "serve" ]]; then
    return 0
  fi

  if [[ ! -x "${tailscale_bin}" ]] || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  status="$(sudo "${tailscale_bin}" serve status --json 2>/dev/null || true)"
  if [[ -z "${status}" ]]; then
    return 1
  fi

  printf "%s" "${status}" | jq -e --arg port "${OPENCLAW_GATEWAY_PORT}" '
    any((.Web // {}) | to_entries[]?;
      (.key | endswith(":443"))
      and ((.value.Handlers["/"].Proxy // "")
        | test("^https?://(127[.]0[.]0[.]1|localhost|\\[::1\\]):" + $port + "$"))
    )
  ' >/dev/null 2>&1
}

print_diagnostic_block() {
  local title="$1"
  local content="${2:-}"

  if [[ -z "${content}" ]]; then
    return 0
  fi

  warn "${title}"
  printf "%s\n" "${content}" >&2
}

print_openclaw_gateway_log_tail() {
  local label="$1"
  local path="$2"
  local output=""

  if ! sudo test -e "${path}"; then
    warn "${label} log is missing: ${path}"
    return 0
  fi

  if ! sudo test -s "${path}"; then
    warn "${label} log is empty: ${path}"
    return 0
  fi

  output="$(sudo tail -n 80 "${path}" 2>&1 || true)"
  print_diagnostic_block "last 80 lines from ${label} log at ${path}:" "${output}"
}

print_openclaw_gateway_failure_diagnostics() {
  local status_output="$1"
  local launchd_output=""
  local serve_output=""
  local tailscale_bin="${BREW_PREFIX_VALUE}/bin/tailscale"

  print_diagnostic_block "openclaw gateway status output:" "${status_output}"

  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" == "serve" && -x "${tailscale_bin}" ]]; then
    serve_output="$(sudo "${tailscale_bin}" serve status --json 2>&1 || true)"
    print_diagnostic_block "tailscale serve status:" "${serve_output}"
  fi

  launchd_output="$(sudo launchctl print "gui/$(id -u "${OPENCLAW_USER}")/${OPENCLAW_NATIVE_GATEWAY_LAUNCH_AGENT_LABEL}" 2>&1 || true)"
  print_diagnostic_block "openclaw native LaunchAgent state:" "${launchd_output}"
  print_openclaw_gateway_log_tail "openclaw gateway" "$(openclaw_native_gateway_log_path)"
  print_openclaw_gateway_log_tail "openclaw finalizer stderr" "$(openclaw_finalizer_log_dir)/openclaw-finalize.error.log"
  print_openclaw_gateway_log_tail "openclaw finalizer stdout" "$(openclaw_finalizer_log_dir)/openclaw-finalize.log"
}

openclaw_gateway_failure_remediation() {
  printf "inspect %s and %s/openclaw-finalize.error.log, then rerun agentbox; a graphical session for %s is required." "$(openclaw_native_gateway_log_path)" "$(openclaw_finalizer_log_dir)" "${OPENCLAW_USER}"
}

wait_for_openclaw_gateway_tailscale_serve_route() {
  local openclaw_bin="$1"
  local attempts="0"
  local output=""

  if [[ "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}" != "serve" ]]; then
    return 0
  fi

  while [[ "${attempts}" -lt 30 ]]; do
    attempts=$((attempts + 1))

    if openclaw_gateway_tailscale_serve_route_ready; then
      log "${tty_tp}verified${tty_reset} openclaw gateway tailscale serve route for port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}"
      return 0
    fi

    sleep 2
  done

  output="$(run_as_openclaw_runner "${openclaw_bin}" gateway status --require-rpc --timeout 10000 2>&1 || true)"
  debug "${tty_tp}openclaw gateway status output${tty_reset}" "${output}"
  print_openclaw_gateway_failure_diagnostics "${output}"
  abort "openclaw gateway tailscale serve route did not become ready for port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}; $(openclaw_gateway_failure_remediation)"
}

run_agentbox_openclaw_gateway_setup() {
  local existing_token_path="${BOOT_TMPDIR}/openclaw-existing-gateway-token.json"
  local openclaw_bin
  local reconcile_existing="0"
  local runner_uid

  check_sudo_access "before openclaw gateway setup"
  resolve_brew_prefix
  openclaw_bin="$(openclaw_bin_path)"
  validate_openclaw_cli_contract "${openclaw_bin}"
  if openclaw_gateway_configuration_initialized "${openclaw_bin}"; then
    reconcile_existing="1"
    preserve_existing_openclaw_gateway_configuration "${openclaw_bin}"
    capture_existing_openclaw_gateway_token "${existing_token_path}" || true
  fi
  reconcile_openclaw_admin_native_gateway_conflict "${openclaw_bin}"
  validate_openclaw_gateway_port_owner
  ensure_openclaw_admin_app_attach_only
  run_openclaw_gateway_onboarding "${openclaw_bin}" "${reconcile_existing}"
  restore_existing_openclaw_gateway_token "${existing_token_path}"
  configure_openclaw_tailscale_auth "${openclaw_bin}"
  configure_openclaw_ui_assistant_branding "${openclaw_bin}"
  reconcile_openclaw_admin_app_config "${openclaw_bin}"

  runner_uid="$(id -u "${OPENCLAW_USER}")"
  if openclaw_native_gateway_launch_agent_loaded "${runner_uid}" && openclaw_gateway_status_ready "${openclaw_bin}"; then
    if ! openclaw_native_gateway_agentbox_managed; then
      cleanup_stale_openclaw_finalizer
      OPENCLAW_GATEWAY_SETUP_STATUS="healthy"
      log "${tty_tp}preserving${tty_reset} healthy runtime-user native openclaw Gateway not managed by agentbox"
      wait_for_openclaw_gateway_tailscale_serve_route "${openclaw_bin}"
      return 0
    fi

    write_openclaw_gateway_managed_environment
    prepare_openclaw_native_gateway_log
    if openclaw_native_gateway_managed_environment_current; then
      cleanup_stale_openclaw_finalizer
      OPENCLAW_GATEWAY_SETUP_STATUS="healthy"
      log "${tty_tp}verified${tty_reset} exactly one healthy agentbox-managed runtime-user native openclaw Gateway"
      wait_for_openclaw_gateway_tailscale_serve_route "${openclaw_bin}"
      return 0
    fi
  fi

  write_openclaw_gateway_managed_environment
  prepare_openclaw_native_gateway_log
  log "${tty_tp}staging${tty_reset} Aqua-only openclaw Gateway finalizer for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  stage_openclaw_finalizer
  if openclaw_runner_gui_domain_active; then
    activate_openclaw_finalizer
    if [[ "${OPENCLAW_GATEWAY_SETUP_STATUS}" == "healthy" ]]; then
      wait_for_openclaw_gateway_tailscale_serve_route "${openclaw_bin}"
    fi
    return 0
  fi

  OPENCLAW_GATEWAY_SETUP_STATUS="pending_first_login"
  if openclaw_autologin_enabled; then
    log "${tty_tp}staged${tty_reset} openclaw Gateway activation; it will complete after a reboot or the next graphical login by ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  else
    warn "openclaw Gateway activation requires a graphical login by ${OPENCLAW_USER}; with autologin off, the user must log in again after every reboot."
  fi
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  validate_platform
  apply_noninteractive_mode
  prepare_agentbox_payload
  validate_inputs_before_sudo
  if [[ -n "${CI-}" || -n "${NONINTERACTIVE-}" ]]; then
    start_sudo_session "before non-interactive input validation"
  fi
  validate_inputs
  validate_sudo_capability
  warn_if_xcode_clt_missing

  debug "${tty_tp}running${tty_reset}" "${SCRIPT_NAME}" script version: "${SCRIPT_VERSION}"
  debug raw CI="${CI:-}"
  debug raw NONINTERACTIVE="${NONINTERACTIVE:-}"
  debug raw DEBUG="${DEBUG:-}"
  debug raw FORCE="${FORCE:-}"
  debug raw AGENTBOX_VERSION="${SCRIPT_VERSION}"
  debug raw AGENTBOX_EXTRA_BREWFILES="$(extra_brewfiles_display)"
  debug raw AGENTBOX_HOSTNAME="${AGENTBOX_HOSTNAME_VALUE}"
  debug raw AGENTBOX_BREWGROUP="$(brewgroup_display)"
  debug raw AGENTBOX_OPENCLAW_IDENTITY="${OPENCLAW_FULL_NAME} <${OPENCLAW_USER}>"
  debug raw AGENTBOX_OPENCLAW_PASSWORD="$(openclaw_password_display)"
  debug raw AGENTBOX_OPENCLAW_AUTOLOGIN="${OPENCLAW_AUTOLOGIN}"
  debug raw AGENTBOX_INTERACTION_MODE="$(openclaw_onboarding_mode_display)"
  debug raw AGENTBOX_OPENCLAW_AUTH_CHOICE="${OPENCLAW_AUTH_CHOICE}"
  debug raw AGENTBOX_OPENCLAW_AUTH_ENV="$(openclaw_auth_env_display)"
  debug raw OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND_VALUE}"
  debug raw OPENCLAW_GATEWAY_TAILSCALE_MODE="${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}"
  debug raw AGENTBOX_OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT}"
  debug raw INVOKING_ADMIN_USER="${ADMIN_USER}"
  debug raw AGENTBOX_AUTHORIZED_KEY_COUNT="$(array_count AUTHORIZED_KEY_LINES)"
  if tailscale_setup_disabled; then
    debug raw TAILSCALE_SETUP="disabled"
    debug raw TAILSCALE_HOSTNAME="disabled"
  else
    debug raw TAILSCALE_SETUP="enabled"
    debug raw TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME_VALUE}"
  fi
  debug raw AGENTBOX_TAILSCALE_AUTHKEY="$(tailscale_authkey_display)"
  debug raw BOOTBOX_URL="${BOOTBOX_URL}"
  debug raw CURL="${CURL}"
  debug raw ARCH="${ARCH}"
  debug raw OS="${OS}"

  prepare_bootbox_script
  resolve_agentbox_payload
  discover_agentbox_payload
  resolve_extra_brewfiles
  debug raw AGENTBOX_PAYLOAD_DIR="$(agentbox_payload_display)"
  debug raw AGENTBOX_PAYLOAD_SOURCE="$(agentbox_payload_source_display)"
  debug raw AGENTBOX_CORE_BREWFILE="$(agentbox_brewfile_display)"
  debug raw AGENTBOX_RESOLVED_EXTRA_BREWFILES="$(array_join "," RESOLVED_EXTRA_BREWFILES)"
  run_bootbox_check_core || true
  debug raw CORE_NEEDS_REMEDIATION="${CORE_NEEDS_REMEDIATION}"
  plan_wrapper_execution

  if [[ -z "${NONINTERACTIVE-}" ]] && have_planned_actions; then
    show_planned_actions
    wait_for_user
  fi

  ensure_bootbox_core_requirements
  run_bootbox_for_agentbox_brewfile
  start_sudo_session
  run_agentbox_hostname_setup
  run_agentbox_macos_settings
  run_agentbox_homebrew_login_path_setup
  run_agentbox_openclaw_user_setup
  run_agentbox_brewgroup_setup
  run_agentbox_ssh_setup
  run_agentbox_tailscale_setup
  run_agentbox_openclaw_gateway_setup
  run_agentbox_launchd_health_setup
  run_agentbox_post_bootstrap_summary
}

main "$@"
