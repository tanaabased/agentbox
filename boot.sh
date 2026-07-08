#!/bin/bash
set -euo pipefail
# Bootstrap a macOS machine as a Tanaab agentbox profile.
#
# Examples:
#
#   $ AGENTBOX_AUTHORIZED_KEY="$(cat ~/.ssh/id_ed25519.pub)" AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" ./boot.sh --hostname TANAABAGENTBOX1
#   $ ./boot.sh --authorized-key file:~/.ssh/id_ed25519.pub --tailscale-authkey "$TS_AUTHKEY" --agentbox-version 1.2.3 --yes
#   $ AGENTBOX_DEBUG=1 AGENTBOX_AUTHORIZED_KEY="$(cat ~/.ssh/id_ed25519.pub)" AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" ./boot.sh --yes
#
# Option precedence: CLI options override environment variables, which override defaults.

MACOS_OLDEST_SUPPORTED="26.0"
MACOS_UNSUPPORTED_AT_OR_AFTER="27.0"
MACOS_SUPPORTED_RANGE="26.x"
REQUIRED_CURL_VERSION="7.41.0"
BOOTBOX_URL="https://bootbox.tanaab.sh/bootbox.sh"
DEFAULT_AGENTBOX_HOSTNAME="TANAABAGENTBOX1"
DEFAULT_BREWGROUP="brewer"
DEFAULT_OPENCLAW_IDENTITY="A Tanaab-based Claw <openclaw>"
DEFAULT_OPENCLAW_GATEWAY_PORT="18789"
DEFAULT_OPENCLAW_AUTH_CHOICE="skip"
AGENTBOX_OPT_DIR="/opt/tanaab/agentbox"
AGENTBOX_PROFILE_IMAGE_PATH="${AGENTBOX_OPT_DIR}/profile.png"
AGENTBOX_LOG_DIR="/var/log/tanaab/agentbox"
AGENTBOX_STATE_DIR="/var/db/tanaab/agentbox"
AGENTBOX_TAILSCALED_STATE_DIR="${AGENTBOX_STATE_DIR}/tailscale"
AGENTBOX_HEALTH_STATE_PATH="${AGENTBOX_STATE_DIR}/health.env"
AGENTBOX_HEALTH_LABEL="dev.tanaab.agentbox.health"
AGENTBOX_TAILSCALED_LABEL="dev.tanaab.agentbox.tailscaled"
AGENTBOX_TAILSCALED_PLIST_PATH="/Library/LaunchDaemons/${AGENTBOX_TAILSCALED_LABEL}.plist"
AGENTBOX_OPENCLAW_GATEWAY_LABEL="dev.tanaab.agentbox.openclaw-gateway"
AGENTBOX_OPENCLAW_GATEWAY_PLIST_PATH="/Library/LaunchDaemons/${AGENTBOX_OPENCLAW_GATEWAY_LABEL}.plist"
AGENTBOX_HOMEBREW_PATHS_FILE="/etc/paths.d/00-agentbox-homebrew"
HOMEBREW_TAILSCALE_LABEL="homebrew.mxcl.tailscale"
HOMEBREW_TAILSCALE_SYSTEM_PLIST_PATH="/Library/LaunchDaemons/${HOMEBREW_TAILSCALE_LABEL}.plist"
AGENTBOX_REPO_HTTPS_URL="https://github.com/tanaabased/agentbox.git"
AGENTBOX_REPO_ARCHIVE_BASE_URL="https://github.com/tanaabased/agentbox/archive/refs/tags"
SSHD_BIN="/usr/sbin/sshd"
SSHD_CONFIG_PATH="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_AGENTBOX_CONFIG_PATH="${SSHD_CONFIG_DIR}/agentbox.conf"
SSH_ACCESS_GROUP="com.apple.access_ssh"
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
  abort 'both `$INTERACTIVE` and `$NONINTERACTIVE` are set. please unset at least one variable and try again.'
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
AGENTBOX_VERSION_VALUE="${AGENTBOX_VERSION:-}"
AGENTBOX_HOSTNAME_VALUE="${AGENTBOX_HOSTNAME:-${DEFAULT_AGENTBOX_HOSTNAME}}"
BREWGROUP_INPUT="${AGENTBOX_BREWGROUP:-${DEFAULT_BREWGROUP}}"
BREWGROUP_VALUE=""
TRUSTED_BREWGROUP_VALUE=""
OPENCLAW_IDENTITY_INPUT="${AGENTBOX_OPENCLAW_IDENTITY:-${DEFAULT_OPENCLAW_IDENTITY}}"
OPENCLAW_FULL_NAME=""
OPENCLAW_USER=""
OPENCLAW_PASSWORD="${AGENTBOX_OPENCLAW_PASSWORD:-}"
OPENCLAW_AUTOLOGIN_INPUT="${AGENTBOX_OPENCLAW_AUTOLOGIN:-1}"
OPENCLAW_GATEWAY_BIND_VALUE="loopback"
OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE=""
OPENCLAW_GATEWAY_PORT="${AGENTBOX_OPENCLAW_GATEWAY_PORT:-${DEFAULT_OPENCLAW_GATEWAY_PORT}}"
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
CORE_NEEDS_REMEDIATION="0"
CURL=""
DETECTED_ARCH=""
DETECTED_OS=""
ARCH=""
OS=""
AGENTBOX_VERSION_TAG=""
AGENTBOX_SOURCE_KIND=""
AGENTBOX_SOURCE_LOCAL_PATH=""
AGENTBOX_SOURCE_ARCHIVE_URL=""
AGENTBOX_SOURCE_ARCHIVE_PATH=""
AGENTBOX_TARGET_PATH=""
AGENTBOX_CORE_BREWFILE=""
AGENTBOX_BIN_DIR=""
AGENTBOX_LAUNCHD_DIR=""
AGENTBOX_ASSETS_DIR=""
AGENTBOX_HEALTH_SCRIPT_SOURCE=""
AGENTBOX_HEALTH_PLIST_TEMPLATE=""
AGENTBOX_TAILSCALED_PLIST_TEMPLATE=""
AGENTBOX_OPENCLAW_GATEWAY_PLIST_TEMPLATE=""
AGENTBOX_PROFILE_IMAGE_SOURCE=""
BREW_PREFIX_VALUE=""
TAILSCALE_HOSTNAME_VALUE=""

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
  ! value_disabled "${OPENCLAW_AUTOLOGIN_INPUT:-1}"
}

openclaw_autologin_display() {
  if openclaw_autologin_enabled; then
    printf "enabled"
  else
    printf "disabled"
  fi
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

agentbox_version_display() {
  if [[ -z "${AGENTBOX_VERSION_VALUE}" ]]; then
    printf "latest"
  elif is_semver_value "${AGENTBOX_VERSION_VALUE}"; then
    normalize_release_tag "${AGENTBOX_VERSION_VALUE}"
  else
    printf "%s" "${AGENTBOX_VERSION_VALUE}"
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

http_url_value() {
  [[ "${1:-}" == http://* || "${1:-}" == https://* ]]
}

tar_archive_path_value() {
  case "${1:-}" in
    *.tar | *.tar.gz | *.tgz)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

brewfile_source_url_value() {
  [[ "${1:-}" =~ ^[[:alpha:]][[:alnum:].+-]*:// ]]
}

find_git_repo_root() {
  local path="$1"
  local parent

  while :; do
    if [[ -d "${path}/.git" ]]; then
      printf "%s" "${path}"
      return 0
    fi

    if [[ -f "${path}/HEAD" && -d "${path}/objects" && -d "${path}/refs" ]]; then
      printf "%s" "${path}"
      return 0
    fi

    parent="$(dirname "${path}")"
    if [[ "${parent}" == "${path}" ]]; then
      return 1
    fi

    path="${parent}"
  done
}

resolve_local_repo_source_path() {
  local source_path="$1"
  local absolute_path
  local repo_root

  if ! absolute_path="$(cd "${source_path}" 2>/dev/null && pwd -P)"; then
    return 1
  fi

  if ! repo_root="$(find_git_repo_root "${absolute_path}")"; then
    return 1
  fi

  printf "%s" "${repo_root}"
}

resolve_local_archive_source_path() {
  local source_path
  local source_dir
  local source_name

  source_path="$(expand_home_path "$1")"
  if [[ ! -f "${source_path}" ]] || ! tar_archive_path_value "${source_path}"; then
    return 1
  fi

  source_dir="$(cd "$(dirname "${source_path}")" 2>/dev/null && pwd -P)" || return 1
  source_name="$(basename "${source_path}")"
  printf "%s/%s" "${source_dir}" "${source_name}"
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

  target_path="${AGENTBOX_TARGET_PATH}/${brewfile}"
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
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required runtime assets ${tty_ts}assets/profile*.png${tty_reset}."
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

  usage_option "--agentbox-version" "installs a tagged release, local git repo, or tar archive url/path" "$(agentbox_version_display)"
  usage_option "--brewfile" "adds an extra Brewfile from a local path or url" "${extra_brewfiles_display_value}"
  usage_option "--hostname" "sets the system hostname and tailscale name source" "${AGENTBOX_HOSTNAME_VALUE}"
  usage_option "--authorized-key" "adds an ssh public key or public-key file path" "${authorized_keys_display}"
  usage_option "--tailscale-authkey" "uses a tailscale auth key to join; falsey disables setup" "${tailscale_authkey_display_value}"
  usage_option "--brewgroup" "manages homebrew prefix group write access; accepts group[:trusted-group]; falsey disables setup" "${brewgroup_display_value}"
  usage_option "--openclaw-identity" "configures the openclaw runner as \"full name <shortname>\"" "${OPENCLAW_IDENTITY_INPUT}"
  usage_option "--openclaw-password" "sets the openclaw runner password for user creation or autologin" "${openclaw_password_display_value}"
  usage_option "--openclaw-auth-choice" "sets initial openclaw model auth choice" "${openclaw_auth_choice_display_value}"
  usage_option "--openclaw-auth-env" "passes one extra parent env var to openclaw auth onboarding" "${openclaw_auth_env_display_value}"
  usage_option "--openclaw-gateway-port" "sets openclaw gateway port" "${openclaw_gateway_port_display_value}"
  usage_option "--skip-openclaw-autologin" "skips default openclaw runner autologin"
  usage_option "--version" "shows version of this script"
  usage_option "--debug" "shows debug messages" "${debug_display}"
  usage_option "--force" "forces supported replacement operations" "${force_display}"
  usage_option "-h, --help" "displays this help message"
  usage_option "-y, --yes" "runs with all defaults and no prompts, sets NONINTERACTIVE=1"

  cat <<EOS

${tty_tp}Environment Variables:${tty_reset}
  AGENTBOX_VERSION               same as --agentbox-version
  AGENTBOX_BREWFILE              same as --brewfile
  AGENTBOX_HOSTNAME              same as --hostname
  AGENTBOX_AUTHORIZED_KEY        same as --authorized-key
  AGENTBOX_TAILSCALE_AUTHKEY     same as --tailscale-authkey
  AGENTBOX_BREWGROUP             same as --brewgroup
  AGENTBOX_OPENCLAW_IDENTITY     same as --openclaw-identity
  AGENTBOX_OPENCLAW_PASSWORD     same as --openclaw-password
  AGENTBOX_OPENCLAW_AUTOLOGIN    falsey disables openclaw runner autologin
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
      --agentbox-version)
        require_next_option_value "--agentbox-version" "$#"
        AGENTBOX_VERSION_VALUE="$2"
        shift 2
        ;;
      --agentbox-version=*)
        require_inline_option_value "--agentbox-version" "${1#*=}"
        AGENTBOX_VERSION_VALUE="${1#*=}"
        shift
        ;;
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
      --openclaw-gateway-port)
        require_next_option_value "--openclaw-gateway-port" "$#"
        OPENCLAW_GATEWAY_PORT="$2"
        shift 2
        ;;
      --openclaw-gateway-port=*)
        require_inline_option_value "--openclaw-gateway-port" "${1#*=}"
        OPENCLAW_GATEWAY_PORT="${1#*=}"
        shift
        ;;
      --skip-openclaw-autologin)
        OPENCLAW_AUTOLOGIN_INPUT="0"
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

agentbox_target_display() {
  display_home_path "${AGENTBOX_TARGET_PATH}"
}

agentbox_brewfile_display() {
  display_home_path "${AGENTBOX_CORE_BREWFILE}"
}

prepare_agentbox_source() {
  AGENTBOX_TARGET_PATH="${HOME}/tanaab/agentbox"
  AGENTBOX_VERSION_TAG=""
  AGENTBOX_SOURCE_KIND=""
  AGENTBOX_SOURCE_LOCAL_PATH=""
  AGENTBOX_SOURCE_ARCHIVE_URL=""
  AGENTBOX_SOURCE_ARCHIVE_PATH=""

  if [[ -z "${AGENTBOX_VERSION_VALUE}" || "${AGENTBOX_VERSION_VALUE}" == "latest" ]]; then
    AGENTBOX_SOURCE_KIND="default"
  elif is_semver_value "${AGENTBOX_VERSION_VALUE}"; then
    AGENTBOX_SOURCE_KIND="version"
    AGENTBOX_VERSION_TAG="$(normalize_release_tag "${AGENTBOX_VERSION_VALUE}")"
  elif http_url_value "${AGENTBOX_VERSION_VALUE}"; then
    AGENTBOX_SOURCE_KIND="archive_url"
    AGENTBOX_SOURCE_ARCHIVE_URL="${AGENTBOX_VERSION_VALUE}"
  elif tar_archive_path_value "${AGENTBOX_VERSION_VALUE}"; then
    AGENTBOX_SOURCE_KIND="archive_file"
    if ! AGENTBOX_SOURCE_ARCHIVE_PATH="$(resolve_local_archive_source_path "${AGENTBOX_VERSION_VALUE}")"; then
      abort "local agentbox archive ${tty_ts}${AGENTBOX_VERSION_VALUE}${tty_reset} must resolve to an existing .tar, .tar.gz, or .tgz file."
    fi
  else
    AGENTBOX_SOURCE_KIND="local"

    if ! AGENTBOX_SOURCE_LOCAL_PATH="$(resolve_local_repo_source_path "${AGENTBOX_VERSION_VALUE}")"; then
      abort "local agentbox source ${tty_ts}${AGENTBOX_VERSION_VALUE}${tty_reset} must resolve to a local git repo."
    fi

    if [[ "${AGENTBOX_SOURCE_LOCAL_PATH}" == "${AGENTBOX_TARGET_PATH}" ]]; then
      abort "local agentbox source ${tty_ts}${AGENTBOX_SOURCE_LOCAL_PATH}${tty_reset} cannot be the same as target ${tty_ts}$(agentbox_target_display)${tty_reset}."
    fi
  fi
}

agentbox_source_display() {
  case "${AGENTBOX_SOURCE_KIND:-default}" in
    version)
      printf "%s" "${AGENTBOX_VERSION_TAG}"
      ;;
    archive_url)
      printf "%s" "${AGENTBOX_SOURCE_ARCHIVE_URL}"
      ;;
    archive_file)
      display_home_path "${AGENTBOX_SOURCE_ARCHIVE_PATH}"
      ;;
    local)
      display_home_path "${AGENTBOX_SOURCE_LOCAL_PATH}"
      ;;
    *)
      printf "default branch over https"
      ;;
  esac
}

repo_archive_url() {
  local tag="$1"

  printf "%s/%s.tar.gz" "${AGENTBOX_REPO_ARCHIVE_BASE_URL}" "${tag}"
}

extract_agentbox_archive() {
  local archive_path="$1"
  local extract_dir="$2"
  local payload_root=""
  local entry
  local entry_count="0"

  execute mkdir -p "${extract_dir}" "${AGENTBOX_TARGET_PATH}"
  execute tar -xf "${archive_path}" -C "${extract_dir}"

  if [[ -f "${extract_dir}/Brewfile" ]]; then
    payload_root="${extract_dir}"
  else
    for entry in "${extract_dir}"/* "${extract_dir}"/.[!.]* "${extract_dir}"/..?*; do
      if [[ ! -e "${entry}" ]]; then
        continue
      fi

      entry_count=$((entry_count + 1))
      payload_root="${entry}"
    done

    if [[ "${entry_count}" != "1" || ! -d "${payload_root}" || ! -f "${payload_root}/Brewfile" ]]; then
      abort "agentbox archive must contain a Brewfile at archive root or inside one top-level directory."
    fi
  fi

  execute cp -R "${payload_root}/." "${AGENTBOX_TARGET_PATH}"
}

repo_prepare_target() {
  local target="$1"

  if [[ -e "${target}" ]]; then
    if ! force_enabled; then
      return 1
    fi

    execute rm -rf "${target}"
  fi

  execute mkdir -p "$(dirname "${target}")"
  return 0
}

agentbox_target_git_repo() {
  git -C "${AGENTBOX_TARGET_PATH}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

warn_agentbox_fetch_skipped() {
  local target_display
  target_display="$(agentbox_target_display)"

  if [[ "${AGENTBOX_SOURCE_KIND}" == "default" ]] && agentbox_target_git_repo; then
    warn "${tty_tp}skipping${tty_reset} agentbox fetch because ${tty_ts}${target_display}${tty_reset} already exists and ${tty_bold}--force${tty_reset} is not set; using the existing checkout. to update it manually, run: ${tty_bold}git -C ${target_display} pull --ff-only${tty_reset}"
  else
    warn "${tty_tp}skipping${tty_reset} agentbox fetch because ${tty_ts}${target_display}${tty_reset} already exists and ${tty_bold}--force${tty_reset} is not set; using the existing directory. re-run with ${tty_bold}--force${tty_reset} to replace it."
  fi
}

fetch_agentbox_source() {
  local archive_path
  local archive_url

  if ! repo_prepare_target "${AGENTBOX_TARGET_PATH}"; then
    warn_agentbox_fetch_skipped
    return 0
  fi

  if [[ "${AGENTBOX_SOURCE_KIND}" == "version" ]]; then
    archive_url="$(repo_archive_url "${AGENTBOX_VERSION_TAG}")"
    archive_path="${BOOT_TMPDIR}/agentbox-${AGENTBOX_VERSION_TAG}.tar.gz"
    log "${tty_tp}extracting${tty_reset} ${tty_ts}agentbox${tty_reset} release ${tty_ts}${AGENTBOX_VERSION_TAG}${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    execute "${CURL}" -fsSL "${archive_url}" -o "${archive_path}"
    extract_agentbox_archive "${archive_path}" "${BOOT_TMPDIR}/agentbox-source"
  elif [[ "${AGENTBOX_SOURCE_KIND}" == "archive_url" ]]; then
    archive_path="${BOOT_TMPDIR}/agentbox-archive.tar.gz"
    log "${tty_tp}extracting${tty_reset} ${tty_ts}agentbox${tty_reset} archive ${tty_ts}${AGENTBOX_SOURCE_ARCHIVE_URL}${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    execute "${CURL}" -fsSL "${AGENTBOX_SOURCE_ARCHIVE_URL}" -o "${archive_path}"
    extract_agentbox_archive "${archive_path}" "${BOOT_TMPDIR}/agentbox-source"
  elif [[ "${AGENTBOX_SOURCE_KIND}" == "archive_file" ]]; then
    log "${tty_tp}extracting${tty_reset} ${tty_ts}agentbox${tty_reset} archive ${tty_ts}$(display_home_path "${AGENTBOX_SOURCE_ARCHIVE_PATH}")${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    extract_agentbox_archive "${AGENTBOX_SOURCE_ARCHIVE_PATH}" "${BOOT_TMPDIR}/agentbox-source"
  elif [[ "${AGENTBOX_SOURCE_KIND}" == "local" ]]; then
    log "${tty_tp}cloning${tty_reset} ${tty_ts}agentbox${tty_reset} from local git repo ${tty_ts}$(display_home_path "${AGENTBOX_SOURCE_LOCAL_PATH}")${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    execute git clone "${AGENTBOX_SOURCE_LOCAL_PATH}" "${AGENTBOX_TARGET_PATH}"
  else
    log "${tty_tp}cloning${tty_reset} ${tty_ts}agentbox${tty_reset} from ${tty_ts}${AGENTBOX_REPO_HTTPS_URL}${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    execute git clone "${AGENTBOX_REPO_HTTPS_URL}" "${AGENTBOX_TARGET_PATH}"
  fi
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
      abort "extra Brewfile ${tty_ts}${brewfile}${tty_reset} must be a url or resolve to a local file relative to ${tty_ts}$(display_home_path "${INVOCATION_CWD}")${tty_reset} or ${tty_ts}$(agentbox_target_display)${tty_reset}."
    fi

    RESOLVED_EXTRA_BREWFILES+=("${resolved_brewfile}")
  done
}

discover_agentbox_payload() {
  local profile_image_source

  AGENTBOX_CORE_BREWFILE="${AGENTBOX_TARGET_PATH}/Brewfile"
  AGENTBOX_BIN_DIR="${AGENTBOX_TARGET_PATH}/bin"
  AGENTBOX_LAUNCHD_DIR="${AGENTBOX_TARGET_PATH}/launchd"
  AGENTBOX_ASSETS_DIR="${AGENTBOX_TARGET_PATH}/assets"
  AGENTBOX_HEALTH_SCRIPT_SOURCE="${AGENTBOX_BIN_DIR}/health.sh"
  AGENTBOX_HEALTH_PLIST_TEMPLATE="${AGENTBOX_LAUNCHD_DIR}/dev.tanaab.agentbox.health.plist.in"
  AGENTBOX_TAILSCALED_PLIST_TEMPLATE="${AGENTBOX_LAUNCHD_DIR}/dev.tanaab.agentbox.tailscaled.plist.in"
  AGENTBOX_OPENCLAW_GATEWAY_PLIST_TEMPLATE="${AGENTBOX_LAUNCHD_DIR}/dev.tanaab.agentbox.openclaw-gateway.plist.in"
  AGENTBOX_PROFILE_IMAGE_SOURCES=()
  AGENTBOX_PROFILE_IMAGE_SOURCE=""

  if [[ ! -f "${AGENTBOX_CORE_BREWFILE}" ]]; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required Brewfile ${tty_ts}$(agentbox_brewfile_display)${tty_reset}."
  fi

  if [[ ! -f "${AGENTBOX_HEALTH_SCRIPT_SOURCE}" ]]; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_HEALTH_SCRIPT_SOURCE}")${tty_reset}; use a current agentbox checkout or archive that includes bin/ and launchd/."
  fi

  if [[ ! -f "${AGENTBOX_HEALTH_PLIST_TEMPLATE}" ]]; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_HEALTH_PLIST_TEMPLATE}")${tty_reset}; use a current agentbox checkout or archive that includes bin/ and launchd/."
  fi

  if [[ ! -f "${AGENTBOX_TAILSCALED_PLIST_TEMPLATE}" ]]; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_TAILSCALED_PLIST_TEMPLATE}")${tty_reset}; use a current agentbox checkout or archive that includes bin/ and launchd/."
  fi

  if [[ ! -f "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_TEMPLATE}" ]]; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required runtime asset ${tty_ts}$(display_home_path "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_TEMPLATE}")${tty_reset}; use a current agentbox checkout or archive that includes bin/ and launchd/."
  fi

  for profile_image_source in "${AGENTBOX_ASSETS_DIR}"/profile*.png; do
    if [[ -f "${profile_image_source}" ]]; then
      AGENTBOX_PROFILE_IMAGE_SOURCES+=("${profile_image_source}")
    fi
  done

  if ! array_has_values AGENTBOX_PROFILE_IMAGE_SOURCES; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required runtime assets ${tty_ts}assets/profile*.png${tty_reset}; use a current agentbox checkout or archive that includes bundled profile images."
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
  sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
}

openclaw_autologin_configured() {
  [[ "$(autologin_user_value)" == "${OPENCLAW_USER}" ]]
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
use ${tty_bold}--skip-openclaw-autologin${tty_reset} only when autologin should be disabled; creating a new runner user still requires a password.
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
    log "${tty_tp}skipping${tty_reset} openclaw runner autologin because it is disabled"
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
    abort "failed to configure openclaw runner autologin for ${tty_ts}${OPENCLAW_USER}${tty_reset}; rerun with ${tty_bold}--skip-openclaw-autologin${tty_reset} if this mac should not use gui autologin."
  fi

  if ! openclaw_autologin_configured; then
    abort "openclaw runner autologin did not become active for ${tty_ts}${OPENCLAW_USER}${tty_reset}; rerun with ${tty_bold}--skip-openclaw-autologin${tty_reset} if this mac should not use gui autologin."
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
AGENTBOX_HEALTH_OPENCLAW_GATEWAY_LABEL=$(shell_quote "${AGENTBOX_OPENCLAW_GATEWAY_LABEL}")
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

openclaw_gateway_tmp_dir() {
  printf "%s/tmp" "$(openclaw_gateway_state_dir)"
}

openclaw_gateway_service_env_dir() {
  printf "%s/service-env" "$(openclaw_gateway_state_dir)"
}

openclaw_gateway_service_env_file_path() {
  printf "%s/%s.env" "$(openclaw_gateway_service_env_dir)" "${AGENTBOX_OPENCLAW_GATEWAY_LABEL}"
}

openclaw_gateway_service_env_wrapper_path() {
  printf "%s/%s-env-wrapper.sh" "$(openclaw_gateway_service_env_dir)" "${AGENTBOX_OPENCLAW_GATEWAY_LABEL}"
}

openclaw_gateway_service_version() {
  local openclaw_bin="${BREW_PREFIX_VALUE}/bin/openclaw"
  local version_output=""

  if [[ -x "${openclaw_bin}" ]]; then
    version_output="$("${openclaw_bin}" --version 2>/dev/null || true)"
    version_output="$(trim_whitespace "${version_output}")"
  fi

  if [[ "${version_output}" =~ ([0-9]+[.][0-9]+[.][^[:space:]]+) ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ -n "${version_output}" ]]; then
    printf "%s" "${version_output##* }"
    return 0
  fi

  printf "unknown"
}

prepare_openclaw_gateway_runtime_dirs() {
  local primary_group
  local service_env_dir
  local state_dir
  local tmp_dir

  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  state_dir="$(openclaw_gateway_state_dir)"
  tmp_dir="$(openclaw_gateway_tmp_dir)"
  service_env_dir="$(openclaw_gateway_service_env_dir)"

  execute sudo /usr/bin/install -d -o "${OPENCLAW_USER}" -g "${primary_group}" -m 700 "${state_dir}" "${tmp_dir}" "${service_env_dir}"
}

openclaw_gateway_node_extra_ca_certs() {
  printf "%s" "${NODE_EXTRA_CA_CERTS:-/etc/ssl/cert.pem}"
}

openclaw_gateway_node_use_system_ca() {
  printf "%s" "${NODE_USE_SYSTEM_CA:-1}"
}

openclaw_gateway_service_env_entry() {
  local key="$1"
  local value="${2:-}"

  if [[ -z "${value}" ]]; then
    return 0
  fi

  printf "export %s=" "${key}"
  shell_single_quote "${value}"
  printf "\n"
}

openclaw_gateway_service_env_content() {
  local home
  local health_command
  local path_value
  local state_dir
  local tmp_dir

  home="$(openclaw_runner_home_required)"
  health_command="${AGENTBOX_OPT_DIR}/bin/health.sh --report"
  path_value="$(openclaw_runner_path)"
  state_dir="$(openclaw_gateway_state_dir)"
  tmp_dir="$(openclaw_gateway_tmp_dir)"

  printf "# generated by agentbox. do not edit; use %s/.env for durable openclaw runtime env.\n" "${state_dir}"
  openclaw_gateway_service_env_entry "HOME" "${home}"
  openclaw_gateway_service_env_entry "USER" "${OPENCLAW_USER}"
  openclaw_gateway_service_env_entry "LOGNAME" "${OPENCLAW_USER}"
  openclaw_gateway_service_env_entry "PATH" "${path_value}"
  openclaw_gateway_service_env_entry "TMPDIR" "${tmp_dir}"
  openclaw_gateway_service_env_entry "NODE_EXTRA_CA_CERTS" "$(openclaw_gateway_node_extra_ca_certs)"
  openclaw_gateway_service_env_entry "NODE_USE_SYSTEM_CA" "$(openclaw_gateway_node_use_system_ca)"
  openclaw_gateway_service_env_entry "OPENCLAW_STATE_DIR" "${state_dir}"
  openclaw_gateway_service_env_entry "OPENCLAW_GATEWAY_PORT" "${OPENCLAW_GATEWAY_PORT}"
  openclaw_gateway_service_env_entry "OPENCLAW_LAUNCHD_LABEL" "${AGENTBOX_OPENCLAW_GATEWAY_LABEL}"
  openclaw_gateway_service_env_entry "OPENCLAW_SERVICE_MARKER" "openclaw"
  openclaw_gateway_service_env_entry "OPENCLAW_SERVICE_KIND" "gateway"
  openclaw_gateway_service_env_entry "OPENCLAW_SERVICE_VERSION" "$(openclaw_gateway_service_version)"
  openclaw_gateway_service_env_entry "AGENTBOX_MANAGED" "1"
  openclaw_gateway_service_env_entry "AGENTBOX_SERVICE_KIND" "openclaw-gateway"
  openclaw_gateway_service_env_entry "AGENTBOX_VERSION" "${SCRIPT_VERSION}"
  openclaw_gateway_service_env_entry "AGENTBOX_HEALTH_COMMAND" "${health_command}"
}

openclaw_gateway_service_env_wrapper_content() {
  cat <<'EOSERVICEENVWRAPPER'
#!/bin/sh
set -eu
env_file="$1"
shift
if [ -f "$env_file" ]; then
  . "$env_file"
fi
exec "$@"
EOSERVICEENVWRAPPER
}

render_agentbox_launchd_template() {
  local template_path="$1"
  local output_path="$2"
  local tailscaled_bin="${3:-}"
  local rendered
  local health_label
  local health_script_path
  local health_stdout_log
  local health_stderr_log
  local tailscaled_label
  local tailscaled_stdout_log
  local tailscaled_stderr_log
  local tailscaled_statedir
  local tailscaled_statedir_argument
  local openclaw_gateway_label
  local openclaw_gateway_bin
  local openclaw_gateway_user
  local openclaw_gateway_working_directory
  local openclaw_gateway_bind
  local openclaw_gateway_env_file
  local openclaw_gateway_env_wrapper
  local openclaw_gateway_tailscale_mode
  local openclaw_gateway_port
  local openclaw_gateway_stdout_log
  local openclaw_gateway_stderr_log

  if ! rendered="$(cat "${template_path}")"; then
    abort "failed to read agentbox launchd template ${tty_ts}$(display_home_path "${template_path}")${tty_reset}."
  fi

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
  openclaw_gateway_label="$(xml_escape "${AGENTBOX_OPENCLAW_GATEWAY_LABEL}")"
  openclaw_gateway_bin="$(xml_escape "${BREW_PREFIX_VALUE}/bin/openclaw")"
  openclaw_gateway_user="$(xml_escape "${OPENCLAW_USER}")"
  openclaw_gateway_working_directory="$(xml_escape "$(openclaw_gateway_state_dir)")"
  openclaw_gateway_bind="$(xml_escape "${OPENCLAW_GATEWAY_BIND_VALUE}")"
  openclaw_gateway_env_file="$(xml_escape "$(openclaw_gateway_service_env_file_path)")"
  openclaw_gateway_env_wrapper="$(xml_escape "$(openclaw_gateway_service_env_wrapper_path)")"
  openclaw_gateway_tailscale_mode="$(xml_escape "${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}")"
  openclaw_gateway_port="$(xml_escape "${OPENCLAW_GATEWAY_PORT}")"
  openclaw_gateway_stdout_log="$(xml_escape "${AGENTBOX_LOG_DIR}/openclaw-gateway.stdout.log")"
  openclaw_gateway_stderr_log="$(xml_escape "${AGENTBOX_LOG_DIR}/openclaw-gateway.stderr.log")"

  rendered="${rendered//__AGENTBOX_HEALTH_LABEL__/${health_label}}"
  rendered="${rendered//__AGENTBOX_HEALTH_SCRIPT_PATH__/${health_script_path}}"
  rendered="${rendered//__AGENTBOX_HEALTH_STDOUT_LOG__/${health_stdout_log}}"
  rendered="${rendered//__AGENTBOX_HEALTH_STDERR_LOG__/${health_stderr_log}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_LABEL__/${tailscaled_label}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_BIN__/${tailscaled_bin}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_STATEDIR_ARGUMENT__/${tailscaled_statedir_argument}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_STDOUT_LOG__/${tailscaled_stdout_log}}"
  rendered="${rendered//__AGENTBOX_TAILSCALED_STDERR_LOG__/${tailscaled_stderr_log}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_LABEL__/${openclaw_gateway_label}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_BIN__/${openclaw_gateway_bin}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_USER__/${openclaw_gateway_user}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_WORKING_DIRECTORY__/${openclaw_gateway_working_directory}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_BIND__/${openclaw_gateway_bind}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_ENV_FILE__/${openclaw_gateway_env_file}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_ENV_WRAPPER__/${openclaw_gateway_env_wrapper}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_TAILSCALE_MODE__/${openclaw_gateway_tailscale_mode}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_PORT__/${openclaw_gateway_port}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_STDOUT_LOG__/${openclaw_gateway_stdout_log}}"
  rendered="${rendered//__AGENTBOX_OPENCLAW_GATEWAY_STDERR_LOG__/${openclaw_gateway_stderr_log}}"

  if [[ "${rendered}" == *"__AGENTBOX_"* ]]; then
    abort "agentbox launchd template ${tty_ts}$(display_home_path "${template_path}")${tty_reset} contains unresolved placeholders."
  fi

  if ! printf "%s\n" "${rendered}" | sudo tee "${output_path}" >/dev/null; then
    abort "failed to write agentbox launchd daemon ${tty_ts}${output_path}${tty_reset}."
  fi

  execute sudo /usr/bin/plutil -lint "${output_path}"
}

write_agentbox_health_plist() {
  render_agentbox_launchd_template "${AGENTBOX_HEALTH_PLIST_TEMPLATE}" "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist"
  execute sudo chown root:wheel "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist"
  execute sudo chmod 644 "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist"
}

run_agentbox_launchd_health_setup() {
  if sudo launchctl print "system/${AGENTBOX_HEALTH_LABEL}" >/dev/null 2>&1; then
    log "${tty_tp}refreshing${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
  else
    log "${tty_tp}installing${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
  fi

  execute sudo mkdir -p "${AGENTBOX_OPT_DIR}/bin" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  execute sudo chown -R root:wheel "${AGENTBOX_OPT_DIR}" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  execute sudo chmod 755 "${AGENTBOX_OPT_DIR}" "${AGENTBOX_OPT_DIR}/bin" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  write_agentbox_health_state
  write_agentbox_health_script
  write_agentbox_health_plist

  sudo launchctl bootout system "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist" >/dev/null 2>&1 || true
  execute sudo launchctl bootstrap system "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist"
  execute sudo launchctl enable "system/${AGENTBOX_HEALTH_LABEL}"
  execute sudo launchctl kickstart -k "system/${AGENTBOX_HEALTH_LABEL}"
}

run_agentbox_post_bootstrap_summary() {
  log
  log "${tty_bold}agentbox post-bootstrap summary${tty_reset}"
  sudo "${AGENTBOX_OPT_DIR}/bin/health.sh" --report || true
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

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    abort "required command not found: $1"
  fi
}

cleanup() {
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
      warn "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} because \`\$CI\` is set."
      NONINTERACTIVE=1
    elif ! interactive_tty_available; then
      if [[ -z "${INTERACTIVE-}" ]]; then
        warn "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} because no interactive terminal is available."
        NONINTERACTIVE=1
      else
        abort "cannot run interactive mode because no interactive terminal is available."
      fi
    elif [[ ! -t 0 ]]; then
      debug "${tty_tp}using${tty_reset} ${tty_ts}/dev/tty${tty_reset} for interactive input because \`stdin\` is not a tty."
    fi
  else
    log "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} ${tty_dim}because \$NONINTERACTIVE is set${tty_reset}"
  fi
}

check_sudo_access() {
  local phase="${1:-initial}"
  local sudo_failure

  if ! command -v sudo >/dev/null 2>&1; then
    abort "sudo is required for agentbox bootstrap, but the sudo command was not found."
  fi

  if [[ -n "${CI-}" || -n "${NONINTERACTIVE-}" ]]; then
    if sudo -n -v; then
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

  if sudo -v; then
    debug "${tty_tp}verified${tty_reset}" sudo access "${phase}"
    return 0
  fi

  abort "sudo access is required before agentbox can install packages or configure services."
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
    BOOTBOX_QUIET
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

  bootbox_command+=("BOOTBOX_QUIET=1")
  bootbox_display_command+=("BOOTBOX_QUIET=1")

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

plan_agentbox_fetch() {
  local target_display
  target_display="$(agentbox_target_display)"

  if [[ -e "${AGENTBOX_TARGET_PATH}" ]]; then
    if force_enabled; then
      plan_action "${tty_tp}replace${tty_reset} existing ${tty_ts}agentbox${tty_reset} checkout at ${tty_ts}${target_display}${tty_reset} because ${tty_bold}--force${tty_reset} is set"
    else
      plan_action "${tty_tp}skip${tty_reset} fetching ${tty_ts}agentbox${tty_reset} because ${tty_ts}${target_display}${tty_reset} already exists and ${tty_bold}--force${tty_reset} is not set"
      return 0
    fi
  fi

  if [[ "${AGENTBOX_SOURCE_KIND}" == "version" ]]; then
    plan_action "${tty_tp}extract${tty_reset} ${tty_ts}agentbox${tty_reset} release ${tty_ts}${AGENTBOX_VERSION_TAG}${tty_reset} to ${tty_ts}${target_display}${tty_reset}"
  elif [[ "${AGENTBOX_SOURCE_KIND}" == "archive_url" ]]; then
    plan_action "${tty_tp}extract${tty_reset} ${tty_ts}agentbox${tty_reset} archive ${tty_ts}${AGENTBOX_SOURCE_ARCHIVE_URL}${tty_reset} to ${tty_ts}${target_display}${tty_reset}"
  elif [[ "${AGENTBOX_SOURCE_KIND}" == "archive_file" ]]; then
    plan_action "${tty_tp}extract${tty_reset} ${tty_ts}agentbox${tty_reset} archive ${tty_ts}$(display_home_path "${AGENTBOX_SOURCE_ARCHIVE_PATH}")${tty_reset} to ${tty_ts}${target_display}${tty_reset}"
  elif [[ "${AGENTBOX_SOURCE_KIND}" == "local" ]]; then
    plan_action "${tty_tp}clone${tty_reset} ${tty_ts}agentbox${tty_reset} from local git repo ${tty_ts}$(display_home_path "${AGENTBOX_SOURCE_LOCAL_PATH}")${tty_reset} to ${tty_ts}${target_display}${tty_reset}"
  else
    plan_action "${tty_tp}clone${tty_reset} ${tty_ts}agentbox${tty_reset} from public https default branch to ${tty_ts}${target_display}${tty_reset}"
  fi
}

plan_wrapper_execution() {
  if core_remediation_needed; then
    plan_action "${tty_tp}ensure${tty_reset} ${tty_ts}homebrew${tty_reset} is installed"
    plan_action "${tty_tp}install${tty_reset} ${tty_ts}bootbox core packages${tty_reset}"
  fi

  plan_agentbox_fetch
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
    plan_action "${tty_tp}ensure${tty_reset} openclaw runner autologin is configured for ${tty_ts}${OPENCLAW_USER}${tty_reset}"
  else
    plan_action "${tty_tp}skip${tty_reset} openclaw runner autologin because ${tty_bold}--skip-openclaw-autologin${tty_reset} is set or ${tty_bold}AGENTBOX_OPENCLAW_AUTOLOGIN${tty_reset} is falsey"
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
    plan_action "${tty_tp}configure or verify${tty_reset} ${tty_ts}tailscaled${tty_reset} as an agentbox system launchd daemon, tailscale hostname ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}, tailscale serve prerequisites, and scoped magicdns resolver"
  fi
  plan_action "${tty_tp}onboard${tty_reset} openclaw gateway config in ${tty_ts}$(openclaw_onboarding_mode_display)${tty_reset} mode for runner ${tty_ts}${OPENCLAW_USER}${tty_reset} using model auth choice ${tty_ts}${OPENCLAW_AUTH_CHOICE}${tty_reset}, loopback bind, tailscale exposure ${tty_ts}${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}${tty_reset}, and port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}"
  plan_action "${tty_tp}install or refresh${tty_reset} openclaw gateway launchd daemon ${tty_ts}${AGENTBOX_OPENCLAW_GATEWAY_LABEL}${tty_reset}"
  plan_action "${tty_tp}verify${tty_reset} openclaw gateway readiness and configured tailscale exposure"
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

brew_prefix_permissions_ok() {
  local current_group

  if [[ -z "${BREW_PREFIX_VALUE}" || ! -d "${BREW_PREFIX_VALUE}" ]]; then
    return 1
  fi

  current_group="$(stat -f "%Sg" "${BREW_PREFIX_VALUE}" 2>/dev/null || true)"
  [[ "${current_group}" == "${BREWGROUP_VALUE}" ]] && path_group_rwx "${BREW_PREFIX_VALUE}"
}

run_agentbox_brewgroup_setup() {
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

  if brew_prefix_permissions_ok; then
    log "${tty_tp}skipping${tty_reset} homebrew prefix permissions; ${tty_ts}${BREW_PREFIX_VALUE}${tty_reset} is already group-writable by ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}setting${tty_reset} homebrew prefix ${tty_ts}${BREW_PREFIX_VALUE}${tty_reset} group write access for ${tty_ts}${BREWGROUP_VALUE}${tty_reset}"
  execute sudo find -x "${BREW_PREFIX_VALUE}" -exec chgrp -h "${BREWGROUP_VALUE}" {} +
  execute sudo find -x "${BREW_PREFIX_VALUE}" ! -type l -exec chmod g+rwX {} +

  if ! brew_prefix_permissions_ok; then
    abort "homebrew prefix ${tty_ts}${BREW_PREFIX_VALUE}${tty_reset} is still not group-writable by ${tty_ts}${BREWGROUP_VALUE}${tty_reset} after remediation."
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
  execute sudo chown root:wheel "${AGENTBOX_TAILSCALED_PLIST_PATH}"
  execute sudo chmod 644 "${AGENTBOX_TAILSCALED_PLIST_PATH}"
}

verify_agentbox_tailscaled_launchd_setup() {
  local admin_uid=""

  admin_uid="$(id -u "${ADMIN_USER}" 2>/dev/null || true)"

  if ! agentbox_tailscaled_launchd_loaded; then
    abort "agentbox tailscaled launchd daemon is not loaded in the system launchd domain."
  fi

  if sudo launchctl print "system/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
    abort "legacy homebrew tailscale launchd daemon is still loaded in the system launchd domain."
  fi

  if [[ -n "${admin_uid}" ]] && launchctl print "gui/${admin_uid}/${HOMEBREW_TAILSCALE_LABEL}" >/dev/null 2>&1; then
    abort "legacy homebrew tailscale launchd agent is still loaded in the invoking user's launchd domain."
  fi
}

agentbox_tailscaled_launchd_loaded() {
  sudo launchctl print "system/${AGENTBOX_TAILSCALED_LABEL}" >/dev/null 2>&1
}

run_agentbox_tailscaled_launchd_setup() {
  local tailscaled_bin=""

  tailscaled_bin="$(tailscaled_bin_path)" || {
    abort "tailscaled binary was not found after installing the agentbox brewfiles."
  }

  execute sudo mkdir -p "${AGENTBOX_LOG_DIR}"
  execute sudo chown root:wheel "${AGENTBOX_LOG_DIR}"
  execute sudo chmod 755 "${AGENTBOX_LOG_DIR}"
  remove_homebrew_tailscale_launchd_services
  prepare_tailscaled_statedir
  write_agentbox_tailscaled_plist "${tailscaled_bin}"

  if agentbox_tailscaled_launchd_loaded; then
    log "${tty_tp}skipping${tty_reset} ${tty_ts}tailscaled${tty_reset} restart; agentbox system launchd daemon is already loaded"
    verify_agentbox_tailscaled_launchd_setup
    return 0
  fi

  sudo launchctl bootout system "${AGENTBOX_TAILSCALED_PLIST_PATH}" >/dev/null 2>&1 || true
  execute sudo launchctl bootstrap system "${AGENTBOX_TAILSCALED_PLIST_PATH}"
  execute sudo launchctl enable "system/${AGENTBOX_TAILSCALED_LABEL}"
  execute sudo launchctl kickstart -k "system/${AGENTBOX_TAILSCALED_LABEL}"
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
        warn "tailscale is already joined as ${current_hostname}, but backend state is ${backend_state:-unknown}; skipping reauth."
      fi

      configure_tailscale_operator_user
      configure_tailscale_magicdns_resolver "${status_json}"
      verify_tailscale_serve_prerequisites "${status_json}"
      show_tailscale_status_summary
      return 0
    fi

    warn "tailscale is already joined as ${current_hostname}; expected ${TAILSCALE_HOSTNAME_VALUE}. skipping reauth for this run."
    configure_tailscale_operator_user
    configure_tailscale_magicdns_resolver "${status_json}"
    verify_tailscale_serve_prerequisites "${status_json}"
    show_tailscale_status_summary
    return 0
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
  status_json="$(capture_tailscale_status_json || true)"
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

  env_args=("HOME=${home}" "USER=${OPENCLAW_USER}" "LOGNAME=${OPENCLAW_USER}" "PATH=${path_value}")
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

execute_as_openclaw_runner() {
  if ! run_as_openclaw_runner "$@"; then
    abort "$(printf "failed during openclaw runner command: %s" "$(shell_join "$@")")"
  fi
}

run_openclaw_gateway_onboarding() {
  local openclaw_bin="$1"
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
    --no-install-daemon
    --skip-health
    --suppress-gateway-token-output
  )

  if noninteractive_mode_enabled; then
    openclaw_args+=(--non-interactive --accept-risk --json)
  else
    if [[ ! -t 0 ]]; then
      runner_stdin_path="$(interactive_tty_input)"
    fi
    if [[ ! -t 1 && -w /dev/tty ]]; then
      runner_stdout_path="/dev/tty"
    fi
  fi

  log "${tty_tp}configuring${tty_reset} openclaw gateway for runner ${tty_ts}${OPENCLAW_USER}${tty_reset} in ${tty_ts}$(openclaw_onboarding_mode_display)${tty_reset} mode with loopback bind, tailscale exposure ${tty_ts}${OPENCLAW_GATEWAY_TAILSCALE_MODE_VALUE}${tty_reset}, and port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}"
  OPENCLAW_RUNNER_EXTRA_ENV_NAMES="${onboarding_env_names}" \
    OPENCLAW_RUNNER_STDIN_PATH="${runner_stdin_path}" \
    OPENCLAW_RUNNER_STDOUT_PATH="${runner_stdout_path}" \
    execute_as_openclaw_runner "${openclaw_bin}" "${openclaw_args[@]}"
}

write_openclaw_gateway_service_env_files() {
  local env_file
  local primary_group
  local wrapper_file

  primary_group="$(user_primary_group "${OPENCLAW_USER}")"
  env_file="$(openclaw_gateway_service_env_file_path)"
  wrapper_file="$(openclaw_gateway_service_env_wrapper_path)"

  if ! openclaw_gateway_service_env_content | sudo tee "${env_file}" >/dev/null; then
    abort "failed to write openclaw gateway service environment file ${tty_ts}${env_file}${tty_reset}."
  fi
  execute sudo chown "${OPENCLAW_USER}:${primary_group}" "${env_file}"
  execute sudo chmod 600 "${env_file}"

  if ! openclaw_gateway_service_env_wrapper_content | sudo tee "${wrapper_file}" >/dev/null; then
    abort "failed to write openclaw gateway service environment wrapper ${tty_ts}${wrapper_file}${tty_reset}."
  fi
  execute sudo chown "${OPENCLAW_USER}:${primary_group}" "${wrapper_file}"
  execute sudo chmod 700 "${wrapper_file}"
}

write_agentbox_openclaw_gateway_plist() {
  openclaw_runner_home_required >/dev/null
  render_agentbox_launchd_template "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_TEMPLATE}" "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_PATH}"
  execute sudo chown root:wheel "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_PATH}"
  execute sudo chmod 644 "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_PATH}"
}

prepare_openclaw_gateway_log_file() {
  local path="$1"

  execute sudo /usr/bin/install -o "${OPENCLAW_USER}" -m 600 /dev/null "${path}"
  execute sudo chown "${OPENCLAW_USER}" "${path}"
  execute sudo chmod 600 "${path}"
}

prepare_openclaw_gateway_logs() {
  prepare_openclaw_gateway_log_file "${AGENTBOX_LOG_DIR}/openclaw-gateway.stdout.log"
  prepare_openclaw_gateway_log_file "${AGENTBOX_LOG_DIR}/openclaw-gateway.stderr.log"
}

agentbox_openclaw_gateway_launchd_loaded() {
  sudo launchctl print "system/${AGENTBOX_OPENCLAW_GATEWAY_LABEL}" >/dev/null 2>&1
}

verify_agentbox_openclaw_gateway_launchd_setup() {
  if ! agentbox_openclaw_gateway_launchd_loaded; then
    abort "agentbox openclaw gateway launchd daemon is not loaded in the system launchd domain."
  fi
}

run_agentbox_openclaw_gateway_launchd_setup() {
  execute sudo mkdir -p "${AGENTBOX_LOG_DIR}"
  execute sudo chown root:wheel "${AGENTBOX_LOG_DIR}"
  execute sudo chmod 755 "${AGENTBOX_LOG_DIR}"
  prepare_openclaw_gateway_runtime_dirs
  prepare_openclaw_gateway_logs
  write_openclaw_gateway_service_env_files
  write_agentbox_openclaw_gateway_plist

  sudo launchctl bootout system "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_PATH}" >/dev/null 2>&1 || true
  execute sudo launchctl enable "system/${AGENTBOX_OPENCLAW_GATEWAY_LABEL}"
  execute sudo launchctl bootstrap system "${AGENTBOX_OPENCLAW_GATEWAY_PLIST_PATH}"
  verify_agentbox_openclaw_gateway_launchd_setup
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

  launchd_output="$(sudo launchctl print "system/${AGENTBOX_OPENCLAW_GATEWAY_LABEL}" 2>&1 || true)"
  print_diagnostic_block "agentbox openclaw gateway launchd daemon state:" "${launchd_output}"

  print_openclaw_gateway_log_tail "openclaw gateway stderr" "${AGENTBOX_LOG_DIR}/openclaw-gateway.stderr.log"
  print_openclaw_gateway_log_tail "openclaw gateway stdout" "${AGENTBOX_LOG_DIR}/openclaw-gateway.stdout.log"
}

wait_for_openclaw_gateway_status() {
  local openclaw_bin="$1"
  local attempts="0"
  local output=""

  while [[ "${attempts}" -lt 30 ]]; do
    attempts=$((attempts + 1))

    if openclaw_gateway_status_ready "${openclaw_bin}"; then
      log "${tty_tp}verified${tty_reset} openclaw gateway status for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}"
      return 0
    fi

    sleep 2
  done

  output="$(run_as_openclaw_runner "${openclaw_bin}" gateway status --require-rpc --timeout 10000 2>&1 || true)"
  debug "${tty_tp}openclaw gateway status output${tty_reset}" "${output}"
  print_openclaw_gateway_failure_diagnostics "${output}"
  abort "openclaw gateway status did not become ready for runner ${tty_ts}${OPENCLAW_USER}${tty_reset}; inspect ${tty_ts}${AGENTBOX_LOG_DIR}/openclaw-gateway.stderr.log${tty_reset}."
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
  abort "openclaw gateway tailscale serve route did not become ready for port ${tty_ts}${OPENCLAW_GATEWAY_PORT}${tty_reset}; inspect ${tty_ts}${AGENTBOX_LOG_DIR}/openclaw-gateway.stderr.log${tty_reset}."
}

run_agentbox_openclaw_gateway_setup() {
  local openclaw_bin

  check_sudo_access "before openclaw gateway setup"
  resolve_brew_prefix
  openclaw_bin="$(openclaw_bin_path)"
  run_openclaw_gateway_onboarding "${openclaw_bin}"
  log "${tty_tp}installing${tty_reset} openclaw gateway launchd daemon ${tty_ts}${AGENTBOX_OPENCLAW_GATEWAY_LABEL}${tty_reset}"
  run_agentbox_openclaw_gateway_launchd_setup
  wait_for_openclaw_gateway_status "${openclaw_bin}"
  wait_for_openclaw_gateway_tailscale_serve_route "${openclaw_bin}"
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  validate_platform
  apply_noninteractive_mode
  prepare_agentbox_source
  validate_inputs_before_sudo
  check_sudo_access
  validate_inputs
  warn_if_xcode_clt_missing

  debug "${tty_tp}running${tty_reset}" "${SCRIPT_NAME}" script version: "${SCRIPT_VERSION}"
  debug raw CI="${CI:-}"
  debug raw NONINTERACTIVE="${NONINTERACTIVE:-}"
  debug raw DEBUG="${DEBUG:-}"
  debug raw FORCE="${FORCE:-}"
  debug raw AGENTBOX_VERSION="$(agentbox_version_display)"
  debug raw AGENTBOX_SOURCE="$(agentbox_source_display)"
  debug raw AGENTBOX_TARGET="$(agentbox_target_display)"
  debug raw AGENTBOX_EXTRA_BREWFILES="$(extra_brewfiles_display)"
  debug raw AGENTBOX_HOSTNAME="${AGENTBOX_HOSTNAME_VALUE}"
  debug raw AGENTBOX_BREWGROUP="$(brewgroup_display)"
  debug raw AGENTBOX_OPENCLAW_IDENTITY="${OPENCLAW_FULL_NAME} <${OPENCLAW_USER}>"
  debug raw AGENTBOX_OPENCLAW_PASSWORD="$(openclaw_password_display)"
  debug raw AGENTBOX_OPENCLAW_AUTOLOGIN="$(openclaw_autologin_display)"
  debug raw OPENCLAW_ONBOARDING_MODE="$(openclaw_onboarding_mode_display)"
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
  run_bootbox_check_core || true
  debug raw CORE_NEEDS_REMEDIATION="${CORE_NEEDS_REMEDIATION}"
  plan_wrapper_execution

  if [[ -z "${NONINTERACTIVE-}" ]] && have_planned_actions; then
    show_planned_actions
    wait_for_user
  fi

  ensure_bootbox_core_requirements
  fetch_agentbox_source
  discover_agentbox_payload
  resolve_extra_brewfiles
  debug raw AGENTBOX_CORE_BREWFILE="$(agentbox_brewfile_display)"
  debug raw AGENTBOX_RESOLVED_EXTRA_BREWFILES="$(array_join "," RESOLVED_EXTRA_BREWFILES)"
  run_agentbox_hostname_setup
  run_agentbox_macos_settings
  run_bootbox_for_agentbox_brewfile
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
