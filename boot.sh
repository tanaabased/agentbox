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
AGENTBOX_OPT_DIR="/opt/tanaab/agentbox"
AGENTBOX_LOG_DIR="/var/log/tanaab/agentbox"
AGENTBOX_STATE_DIR="/var/db/tanaab/agentbox"
AGENTBOX_HEALTH_STATE_PATH="${AGENTBOX_STATE_DIR}/health.env"
AGENTBOX_HEALTH_LABEL="dev.tanaab.agentbox.health"
AGENTBOX_REPO_HTTPS_URL="https://github.com/tanaabased/agentbox.git"
AGENTBOX_REPO_ARCHIVE_BASE_URL="https://github.com/tanaabased/agentbox/archive/refs/tags"
SSHD_BIN="/usr/sbin/sshd"
SSHD_CONFIG_PATH="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_AGENTBOX_CONFIG_PATH="${SSHD_CONFIG_DIR}/agentbox.conf"

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
  local first="1"

  for arg in "$@"; do
    if [[ "${first}" == "1" ]]; then
      first="0"
    else
      printf " "
    fi

    printf "%q" "${arg}"
  done
}

shell_quote() {
  printf "%q" "$1"
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

DEBUG="${AGENTBOX_DEBUG:-${DEBUG:-${RUNNER_DEBUG:-}}}"
FORCE="${AGENTBOX_FORCE:-}"
AGENTBOX_VERSION_VALUE="${AGENTBOX_VERSION:-}"
AGENTBOX_HOSTNAME_VALUE="${AGENTBOX_HOSTNAME:-${DEFAULT_AGENTBOX_HOSTNAME}}"
TAILSCALE_AUTHKEY="${AGENTBOX_TAILSCALE_AUTHKEY:-}"
ADMIN_USER=""
AUTHORIZED_KEY_CLI_SEEN="0"
declare -a PLANNED_ACTIONS=()
declare -a AUTHORIZED_KEY_SPECS=()
declare -a AUTHORIZED_KEY_LINES=()
BOOT_TMPDIR=""
BOOTBOX_SCRIPT_PATH=""
CORE_NEEDS_REMEDIATION="0"
CURL=""
DETECTED_ARCH=""
DETECTED_OS=""
ARCH=""
OS=""
AGENTBOX_VERSION_TAG=""
AGENTBOX_TARGET_PATH=""
AGENTBOX_BREWFILE=""
TAILSCALE_HOSTNAME_VALUE=""

if [[ -n "${AGENTBOX_AUTHORIZED_KEY:-}" ]]; then
  append_array_value AUTHORIZED_KEY_SPECS "${AGENTBOX_AUTHORIZED_KEY}"
fi

if [[ -n "${AGENTBOX_AUTHORIZED_KEYS:-}" ]]; then
  append_csv_to_array AUTHORIZED_KEY_SPECS "${AGENTBOX_AUTHORIZED_KEYS}"
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

tailscale_authkey_display() {
  if tailscale_setup_disabled; then
    printf "disabled"
    return 0
  fi

  mask_secret_for_display "${TAILSCALE_AUTHKEY:-}"
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
  [[ "${1:-}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
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

hostname_valid() {
  [[ "${1:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
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

usage() {
  local debug_display="off"
  local force_display="off"
  local tailscale_authkey_display_value="none"
  local authorized_keys_display="none"

  if debug_enabled; then
    debug_display="on"
  fi

  if force_enabled; then
    force_display="on"
  fi

  tailscale_authkey_display_value="$(tailscale_authkey_display)"
  if array_has_values AUTHORIZED_KEY_SPECS; then
    authorized_keys_display="$(array_count AUTHORIZED_KEY_SPECS) provided"
  fi

  cat <<EOS
Usage: ${tty_dim}[NONINTERACTIVE=1] [CI=1]${tty_reset} ${tty_bold}${SCRIPT_NAME}${tty_reset} ${tty_dim}[options]${tty_reset}

${tty_tp}Options:${tty_reset}
  --agentbox-version  installs a tagged release, accepts 1.2.3 or v1.2.3 ${tty_dim}[default: $(agentbox_version_display)]${tty_reset}
  --authorized-key    adds an SSH public key or public-key file path ${tty_dim}[default: ${authorized_keys_display}]${tty_reset}
  --tailscale-authkey uses a Tailscale auth key to join; falsey disables setup ${tty_dim}[default: ${tailscale_authkey_display_value}]${tty_reset}
  --hostname          sets the system hostname and Tailscale name source ${tty_dim}[default: ${AGENTBOX_HOSTNAME_VALUE}]${tty_reset}
  --version           shows version of this script
  --debug             shows debug messages ${tty_dim}[default: ${debug_display}]${tty_reset}
  --force             forces supported replacement operations ${tty_dim}[default: ${force_display}]${tty_reset}
  -h, --help          displays this help message
  -y, --yes           runs with all defaults and no prompts, sets NONINTERACTIVE=1

${tty_tp}Environment Variables:${tty_reset}
  AGENTBOX_VERSION               tagged release to install, accepts 1.2.3 or v1.2.3
  AGENTBOX_AUTHORIZED_KEY        SSH public key or public-key file path
  AGENTBOX_TAILSCALE_AUTHKEY     Tailscale auth key for joining; falsey disables setup
  AGENTBOX_HOSTNAME              system hostname and Tailscale name source
  AGENTBOX_FORCE                 set truthy to force supported operations
  AGENTBOX_DEBUG                 set truthy to show debug messages
  NONINTERACTIVE                 installs without prompting for user input
  CI                             installs in CI mode (e.g. does not prompt for user input)
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

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --debug)
        DEBUG="1"
        shift
        ;;
      --force)
        FORCE="1"
        shift
        ;;
      -h | --help)
        usage
        ;;
      --version)
        show_version
        ;;
      -y | --yes)
        NONINTERACTIVE="1"
        shift
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
  display_home_path "${AGENTBOX_BREWFILE}"
}

prepare_agentbox_source() {
  AGENTBOX_TARGET_PATH="${HOME}/tanaab/agentbox"
  AGENTBOX_VERSION_TAG=""

  if [[ -n "${AGENTBOX_VERSION_VALUE}" ]]; then
    if ! is_semver_value "${AGENTBOX_VERSION_VALUE}"; then
      abort "agentbox version ${tty_ts}${AGENTBOX_VERSION_VALUE}${tty_reset} must use 1.2.3 or v1.2.3 format."
    fi

    AGENTBOX_VERSION_TAG="$(normalize_release_tag "${AGENTBOX_VERSION_VALUE}")"
  fi
}

agentbox_source_display() {
  if [[ -n "${AGENTBOX_VERSION_TAG}" ]]; then
    printf "%s" "${AGENTBOX_VERSION_TAG}"
  else
    printf "default branch over HTTPS"
  fi
}

repo_archive_url() {
  local tag="$1"

  printf "%s/%s.tar.gz" "${AGENTBOX_REPO_ARCHIVE_BASE_URL}" "${tag}"
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

fetch_agentbox_source() {
  local archive_path
  local archive_url

  if ! repo_prepare_target "${AGENTBOX_TARGET_PATH}"; then
    warn "${tty_tp}skipping${tty_reset} agentbox fetch because ${tty_ts}$(agentbox_target_display)${tty_reset} already exists and ${tty_bold}--force${tty_reset} is not set."
    return 0
  fi

  if [[ -n "${AGENTBOX_VERSION_TAG}" ]]; then
    archive_url="$(repo_archive_url "${AGENTBOX_VERSION_TAG}")"
    archive_path="${BOOT_TMPDIR}/agentbox-${AGENTBOX_VERSION_TAG}.tar.gz"
    log "${tty_tp}extracting${tty_reset} ${tty_ts}agentbox${tty_reset} release ${tty_ts}${AGENTBOX_VERSION_TAG}${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    execute mkdir -p "${AGENTBOX_TARGET_PATH}"
    execute "${CURL}" -fsSL "${archive_url}" -o "${archive_path}"
    execute tar -xzf "${archive_path}" -C "${AGENTBOX_TARGET_PATH}" --strip-components=1
  else
    log "${tty_tp}cloning${tty_reset} ${tty_ts}agentbox${tty_reset} from ${tty_ts}${AGENTBOX_REPO_HTTPS_URL}${tty_reset} to ${tty_ts}$(agentbox_target_display)${tty_reset}"
    execute git clone "${AGENTBOX_REPO_HTTPS_URL}" "${AGENTBOX_TARGET_PATH}"
  fi
}

discover_agentbox_payload() {
  AGENTBOX_BREWFILE="${AGENTBOX_TARGET_PATH}/Brewfile"

  if [[ ! -f "${AGENTBOX_BREWFILE}" ]]; then
    abort "agentbox checkout at ${tty_ts}$(agentbox_target_display)${tty_reset} is missing required Brewfile ${tty_ts}$(agentbox_brewfile_display)${tty_reset}."
  fi
}

warn_if_xcode_clt_missing() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "Xcode Command Line Tools may need to be installed before developer tools work correctly."
  fi
}

run_agentbox_hostname_setup() {
  if macos_identity_matches; then
    log "${tty_tp}skipping${tty_reset} macOS system identity; already set to ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
    return 0
  fi

  log "${tty_tp}setting${tty_reset} macOS system identity to ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
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
      warn "could not set pmset ${key}=${desired} on this Mac; continuing."
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

firewall_stealth_enabled() {
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null | grep -qi "enabled"
}

run_agentbox_macos_settings() {
  log "${tty_tp}applying${tty_reset} headless macOS power, time, recovery, and firewall settings"

  ensure_pmset_setting sleep 0
  ensure_pmset_setting disksleep 0
  ensure_pmset_setting displaysleep 0
  ensure_pmset_setting powernap 0 1
  ensure_pmset_setting autorestart 1
  ensure_systemsetup_enabled -getusingnetworktime -setusingnetworktime "network time"
  ensure_systemsetup_enabled -getrestartfreeze -setrestartfreeze "restart after freeze"

  if firewall_global_enabled; then
    log "${tty_tp}skipping${tty_reset} firewall global state; already enabled"
  else
    execute sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  fi

  if firewall_stealth_enabled; then
    log "${tty_tp}skipping${tty_reset} firewall stealth mode; already enabled"
  else
    execute sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
  fi
}

user_home_dir() {
  local user="$1"

  dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | awk '/NFSHomeDirectory:/ {print $2; exit}'
}

expand_user_path() {
  local path="$1"

  case "${path}" in
    \~)
      printf "%s" "${HOME}"
      ;;
    \~/*)
      printf "%s/%s" "${HOME}" "${path#"~/"}"
      ;;
    *)
      printf "%s" "${path}"
      ;;
  esac
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
    path="$(expand_user_path "${value#file:}")"
    resolve_authorized_key_file "${value}" "${path}"
    return 0
  fi

  path="$(expand_user_path "${value}")"
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
    abort "could not determine home directory for admin user ${tty_ts}${user}${tty_reset}."
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
  log "${tty_tp}installed${tty_reset} ${installed_count} new SSH authorized key entries for ${tty_ts}${user}${tty_reset}"
}

remote_login_enabled() {
  sudo systemsetup -getremotelogin 2>/dev/null | grep -Fq "Remote Login: On"
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
  local user="$1"
  local config

  config="$(sudo "${SSHD_BIN}" -T 2>/dev/null)" || return 1
  printf "%s\n" "${config}" | grep -Fxq "passwordauthentication no" || return 1
  printf "%s\n" "${config}" | grep -Fxq "kbdinteractiveauthentication no" || return 1
  printf "%s\n" "${config}" | grep -Fxq "permitrootlogin no" || return 1
  printf "%s\n" "${config}" | grep -Fxq "pubkeyauthentication yes" || return 1
  printf "%s\n" "${config}" | grep -Fxq "allowusers ${user}" || return 1
}

harden_sshd_for_user() {
  local user="$1"
  local backup_path=""

  if [[ ! -x "${SSHD_BIN}" ]]; then
    abort "sshd binary not found at ${tty_ts}${SSHD_BIN}${tty_reset}."
  fi

  if ! sshd_config_drop_in_supported; then
    abort "sshd config drop-ins are not enabled in ${tty_ts}${SSHD_CONFIG_PATH}${tty_reset}; cannot safely install agentbox SSH hardening."
  fi

  if sudo test -e "${SSHD_AGENTBOX_CONFIG_PATH}"; then
    backup_path="${BOOT_TMPDIR}/agentbox.sshd_config.backup"
    execute sudo cp "${SSHD_AGENTBOX_CONFIG_PATH}" "${backup_path}"
  fi

  log "${tty_tp}hardening${tty_reset} SSH for key-only access by ${tty_ts}${user}${tty_reset}"
  execute sudo mkdir -p "${SSHD_CONFIG_DIR}"
  if ! sudo tee "${SSHD_AGENTBOX_CONFIG_PATH}" >/dev/null <<EOSSHD
# Managed by agentbox.
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers ${user}
EOSSHD
  then
    abort "failed to write agentbox sshd config."
  fi

  execute sudo chown root:wheel "${SSHD_AGENTBOX_CONFIG_PATH}"
  execute sudo chmod 644 "${SSHD_AGENTBOX_CONFIG_PATH}"

  if ! sudo "${SSHD_BIN}" -t || ! sshd_effective_config_hardened "${user}"; then
    restore_agentbox_sshd_config "${backup_path}"
    abort "agentbox sshd hardening config failed validation or did not become effective; changes were rolled back."
  fi

  execute sudo launchctl kickstart -k system/com.openssh.sshd
}

run_agentbox_ssh_setup() {
  if remote_login_enabled; then
    log "${tty_tp}skipping${tty_reset} classic SSH enablement; Remote Login is already on"
  else
    log "${tty_tp}enabling${tty_reset} classic SSH for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
    execute sudo systemsetup -setremotelogin on
  fi

  if array_has_values AUTHORIZED_KEY_LINES; then
    install_authorized_keys_for_user "${ADMIN_USER}"
    harden_sshd_for_user "${ADMIN_USER}"
  else
    log "${tty_tp}skipping${tty_reset} SSH authorized key install because no keys were provided"
    warn "classic SSH is enabled, but key-based access and password-login hardening were not configured by this bootstrap run."
  fi
}

write_agentbox_health_state() {
  local tailscale_enabled="1"
  local ssh_hardening_expected="0"

  if tailscale_setup_disabled; then
    tailscale_enabled="0"
  fi

  if array_has_values AUTHORIZED_KEY_LINES; then
    ssh_hardening_expected="1"
  fi

  if ! sudo tee "${AGENTBOX_HEALTH_STATE_PATH}" >/dev/null <<EOHEALTHSTATE
# Managed by agentbox.
AGENTBOX_HEALTH_EXPECTED_HOSTNAME=$(shell_quote "${AGENTBOX_HOSTNAME_VALUE}")
AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME=$(shell_quote "${TAILSCALE_HOSTNAME_VALUE}")
AGENTBOX_HEALTH_TAILSCALE_ENABLED=${tailscale_enabled}
AGENTBOX_HEALTH_ADMIN_USER=$(shell_quote "${ADMIN_USER}")
AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED=${ssh_hardening_expected}
EOHEALTHSTATE
  then
    abort "failed to write agentbox health state."
  fi

  execute sudo chown root:wheel "${AGENTBOX_HEALTH_STATE_PATH}"
  execute sudo chmod 600 "${AGENTBOX_HEALTH_STATE_PATH}"
}

write_agentbox_health_script() {
  if ! sudo tee "${AGENTBOX_OPT_DIR}/bin/health.sh" >/dev/null <<'EOHEALTH'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/var/db/tanaab/agentbox/health.env"
LOG_FILE="/var/log/tanaab/agentbox/health.log"
HEALTH_LABEL="dev.tanaab.agentbox.health"
SSHD_BIN="/usr/sbin/sshd"
SOCKETFILTERFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

AGENTBOX_HEALTH_EXPECTED_HOSTNAME=""
AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME=""
AGENTBOX_HEALTH_TAILSCALE_ENABLED="0"
AGENTBOX_HEALTH_ADMIN_USER=""
AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED="0"

if [[ -r "${STATE_FILE}" ]]; then
  # shellcheck source=/dev/null
  . "${STATE_FILE}"
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

generate_report() {
  local failures="0"
  local computer_name=""
  local host_name=""
  local local_host_name=""
  local sleep_value=""
  local disksleep_value=""
  local displaysleep_value=""
  local autorestart_value=""
  local power_ok="0"
  local network_time_ok=""
  local restart_freeze_ok=""
  local firewall_global_ok=""
  local firewall_stealth_ok=""
  local remote_login_ok=""
  local ssh_hardening_ok="skipped"
  local health_launchd_loaded_ok="0"
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

  if [[ "${sleep_value}" == "0" && "${disksleep_value}" == "0" && "${displaysleep_value}" == "0" && "${autorestart_value}" == "1" ]]; then
    power_ok="1"
  fi

  if launchctl print "system/${HEALTH_LABEL}" >/dev/null 2>&1; then
    health_launchd_loaded_ok="1"
  fi

  print_kv timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
  mark_required headless_power_ok "${power_ok}"
  mark_required network_time_ok "${network_time_ok}"
  mark_required restart_freeze_ok "${restart_freeze_ok}"
  mark_required firewall_global_ok "${firewall_global_ok}"
  mark_required firewall_stealth_ok "${firewall_stealth_ok}"
  mark_required remote_login_ok "${remote_login_ok}"

  print_kv ssh_hardening_expected "${AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED}"
  print_kv admin_user "${AGENTBOX_HEALTH_ADMIN_USER}"
  if [[ "${AGENTBOX_HEALTH_SSH_HARDENING_EXPECTED}" == "1" ]]; then
    ssh_hardening_ok="$(sshd_hardened_value "${AGENTBOX_HEALTH_ADMIN_USER}")"
    mark_required ssh_hardening_ok "${ssh_hardening_ok}"
  else
    print_kv ssh_hardening_ok "${ssh_hardening_ok}"
  fi

  print_kv tailscale_expected "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}"
  print_kv expected_tailscale_hostname "${AGENTBOX_HEALTH_EXPECTED_TAILSCALE_HOSTNAME}"
  if [[ "${AGENTBOX_HEALTH_TAILSCALE_ENABLED}" == "1" ]]; then
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
    mark_required tailscale_ok "${tailscale_ok}"
  else
    print_kv tailscale_ok "${tailscale_ok}"
  fi

  mark_required health_launchd_loaded_ok "${health_launchd_loaded_ok}"
  print_kv root_disk_available_kb "$(root_disk_available_kb)"
  print_kv uptime "$(uptime)"
  print_kv gatekeeper_status "$(gatekeeper_status)"
  print_kv filevault_status "$(filevault_status)"

  if [[ "${failures}" -eq 0 ]]; then
    print_kv posture_ok 1
    return 0
  fi

  print_kv posture_ok 0
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
  *)
    printf 'Usage: health.sh [--report|--check]\n' >&2
    exit 2
    ;;
esac
EOHEALTH
  then
    abort "failed to write agentbox health script."
  fi

  execute sudo chown root:wheel "${AGENTBOX_OPT_DIR}/bin/health.sh"
  execute sudo chmod 755 "${AGENTBOX_OPT_DIR}/bin/health.sh"
}

write_agentbox_health_plist() {
  if ! sudo tee "/Library/LaunchDaemons/${AGENTBOX_HEALTH_LABEL}.plist" >/dev/null <<EOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${AGENTBOX_HEALTH_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
      <string>${AGENTBOX_OPT_DIR}/bin/health.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>300</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${AGENTBOX_LOG_DIR}/health.stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${AGENTBOX_LOG_DIR}/health.stderr.log</string>
  </dict>
</plist>
EOPLIST
  then
    abort "failed to write agentbox health LaunchDaemon."
  fi

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
  local save_state
  save_state="$(/bin/stty -g)"
  /bin/stty raw -echo
  IFS='' read -r -n 1 -d '' "$@"
  /bin/stty "${save_state}"
}

wait_for_user() {
  local c

  trap 'stty sane; tput sgr0; echo; exit 1' SIGINT

  echo
  echo "press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
  getc c
  if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]; then
    exit 1
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
    abort "you must install cURL ${REQUIRED_CURL_VERSION} or higher before using this wrapper."
  fi

  if [[ "${OS}" != "macos" ]]; then
    abort_multi "$(cat <<EOABORT
this script only supports ${tty_ts}macOS${tty_reset}; ${tty_red}${OS}${tty_reset} is not supported.
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
your macOS version ${tty_red}${macos_version}${tty_reset} is ${tty_bold}too old${tty_reset}; minimum supported version is ${tty_ts}${MACOS_OLDEST_SUPPORTED}${tty_reset}.
check the project README for current support details: ${tty_underline}${tty_magenta}https://github.com/tanaabased/agentbox${tty_reset}
EOABORT
)"
  fi

  if version_compare "${macos_version}" "${MACOS_UNSUPPORTED_AT_OR_AFTER}"; then
    if unsupported_macos_allowed; then
      warn "macOS ${macos_version} is outside the validated support range ${MACOS_SUPPORTED_RANGE}; continuing because AGENTBOX_ALLOW_UNSUPPORTED_MACOS is truthy."
    else
      abort_multi "$(cat <<EOABORT
your macOS version ${tty_red}${macos_version}${tty_reset} is newer than the validated support range ${tty_ts}${MACOS_SUPPORTED_RANGE}${tty_reset}.
agentbox stops before machine mutation on unvalidated major macOS versions.
to intentionally test anyway, set ${tty_bold}AGENTBOX_ALLOW_UNSUPPORTED_MACOS=1${tty_reset} and rerun.
EOABORT
)"
    fi
  fi
}

validate_inputs() {
  TAILSCALE_AUTHKEY="$(trim_whitespace "${TAILSCALE_AUTHKEY}")"
  ADMIN_USER="$(id -un 2>/dev/null || true)"

  if [[ -z "${ADMIN_USER}" ]]; then
    abort "the current admin user could not be inferred."
  fi

  if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    abort "current admin user ${tty_ts}${ADMIN_USER}${tty_reset} does not exist on this Mac."
  fi

  resolve_authorized_key_specs

  if ! hostname_valid "${AGENTBOX_HOSTNAME_VALUE}"; then
    abort "hostname ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} must be DNS-safe."
  fi

  if tailscale_setup_disabled; then
    TAILSCALE_HOSTNAME_VALUE=""
    return 0
  fi

  TAILSCALE_HOSTNAME_VALUE="$(derive_tailscale_hostname "${AGENTBOX_HOSTNAME_VALUE}")"
  if [[ -z "${TAILSCALE_HOSTNAME_VALUE}" ]]; then
    abort "hostname ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} derives an empty Tailscale hostname after stripping the leading TANAAB prefix."
  fi

  if ! hostname_valid "${TAILSCALE_HOSTNAME_VALUE}"; then
    abort "derived Tailscale hostname ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset} from ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} must be DNS-safe."
  fi
}

apply_noninteractive_mode() {
  # shellcheck disable=SC2016
  if [[ -z "${NONINTERACTIVE-}" ]]; then
    if [[ -n "${CI-}" ]]; then
      warn "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} because \`\$CI\` is set."
      NONINTERACTIVE=1
    elif [[ ! -t 0 ]]; then
      if [[ -z "${INTERACTIVE-}" ]]; then
        warn "${tty_tp}running${tty_reset} in ${tty_ts}non-interactive mode${tty_reset} because \`stdin\` is not a TTY."
        NONINTERACTIVE=1
      else
        warn "${tty_tp}running${tty_reset} in ${tty_ts}interactive mode${tty_reset} despite \`stdin\` not being a TTY because \`\$INTERACTIVE\` is set."
      fi
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
    TANAAB_BREWFILE
    TANAAB_BREWFILES
    TANAAB_DOTPKG
    TANAAB_DOTPKGS
    TANAAB_SSH_KEY
    TANAAB_SSH_KEYS
    TANAAB_FORCE
    TANAAB_DEBUG
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

  if [[ -n "${NONINTERACTIVE-}" ]]; then
    bootbox_command+=("NONINTERACTIVE=${NONINTERACTIVE}")
    bootbox_display_command+=("NONINTERACTIVE=${NONINTERACTIVE}")
  fi

  bootbox_command+=(/bin/bash "${BOOTBOX_SCRIPT_PATH}")
  bootbox_display_command+=(/bin/bash "${BOOTBOX_SCRIPT_PATH}")
  bootbox_command+=("$@")
  bootbox_display_command+=("$@")

  debug "${tty_tp}delegating${tty_reset}" to "${tty_ts}bootbox${tty_reset}" from "${tty_ts}${BOOT_TMPDIR}${tty_reset}" with "$(shell_join "${bootbox_display_command[@]}")"
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

  if [[ -n "${AGENTBOX_VERSION_TAG}" ]]; then
    plan_action "${tty_tp}extract${tty_reset} ${tty_ts}agentbox${tty_reset} release ${tty_ts}${AGENTBOX_VERSION_TAG}${tty_reset} to ${tty_ts}${target_display}${tty_reset}"
  else
    plan_action "${tty_tp}clone${tty_reset} ${tty_ts}agentbox${tty_reset} from public HTTPS default branch to ${tty_ts}${target_display}${tty_reset}"
  fi
}

plan_wrapper_execution() {
  if core_remediation_needed; then
    plan_action "${tty_tp}ensure${tty_reset} ${tty_ts}homebrew${tty_reset} is installed"
    plan_action "${tty_tp}install${tty_reset} ${tty_ts}bootbox core packages${tty_reset}"
  fi

  plan_agentbox_fetch
  plan_action "${tty_tp}ensure${tty_reset} macOS ComputerName, HostName, and LocalHostName are ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
  plan_action "${tty_tp}ensure${tty_reset} headless power, time, recovery, and firewall settings"
  plan_action "${tty_tp}run${tty_reset} ${tty_ts}bootbox${tty_reset} against the ${tty_ts}agentbox${tty_reset} Brewfile"
  plan_action "${tty_tp}ensure${tty_reset} classic SSH is enabled for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
  if array_has_values AUTHORIZED_KEY_LINES; then
    plan_action "${tty_tp}install${tty_reset} ${tty_ts}$(array_count AUTHORIZED_KEY_LINES)${tty_reset} authorized key entries for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
    plan_action "${tty_tp}harden${tty_reset} SSH to key-only access for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
  fi
  if tailscale_setup_disabled; then
    plan_action "${tty_tp}skip${tty_reset} Tailscale setup because the auth-key input is disabled"
  else
    plan_action "${tty_tp}configure or verify${tty_reset} ${tty_ts}tailscaled${tty_reset} as a launchd service and Tailscale hostname ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}"
  fi
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
  debug "${tty_tp}checking${tty_reset}" "${tty_ts}bootbox core requirements${tty_reset}" from "${tty_ts}${BOOT_TMPDIR}${tty_reset}"
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
  bootbox_run_or_abort agentbox "bootbox failed while applying agentbox Brewfile ${tty_ts}$(agentbox_brewfile_display)${tty_reset}." \
    --brewfile "${AGENTBOX_BREWFILE}"
}

abort_missing_tailscale_authkey() {
  abort_multi "$(cat <<EOABORT
you must provide a Tailscale auth key before this Mac can join Tailscale.
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
    log "${tty_tp}skipping${tty_reset} Tailscale setup because the auth-key input is disabled"
    return 0
  fi

  check_sudo_access "before Tailscale service setup"
  require_command brew
  require_command tailscale
  require_command jq

  log "${tty_tp}starting${tty_reset} ${tty_ts}tailscaled${tty_reset} as a system launchd service"
  execute sudo brew services start tailscale

  status_json="$(capture_tailscale_status_json || true)"
  if [[ -n "${status_json}" ]] && tailscale_status_has_identity "${status_json}"; then
    current_hostname="$(json_value "${status_json}" '.Self.HostName // empty' || true)"
    backend_state="$(json_value "${status_json}" '.BackendState // empty' || true)"
    tailnet_name="$(json_value "${status_json}" '.CurrentTailnet.Name // .CurrentTailnet.MagicDNSSuffix // empty' || true)"

    if [[ -n "${tailnet_name}" ]]; then
      log "${tty_tp}detected${tty_reset} Tailscale tailnet ${tty_ts}${tailnet_name}${tty_reset}"
    fi

    if [[ "${current_hostname}" == "${TAILSCALE_HOSTNAME_VALUE}" ]]; then
      if [[ "${backend_state}" == "Running" ]]; then
        log "${tty_tp}skipping${tty_reset} Tailscale join; already joined as ${tty_ts}${current_hostname}${tty_reset}"
      else
        warn "Tailscale is already joined as ${current_hostname}, but backend state is ${backend_state:-unknown}; skipping reauth."
      fi

      show_tailscale_status_summary
      return 0
    fi

    warn "Tailscale is already joined as ${current_hostname}; expected ${TAILSCALE_HOSTNAME_VALUE}. skipping reauth for this run."
    show_tailscale_status_summary
    return 0
  fi

  if [[ -z "${TAILSCALE_AUTHKEY}" ]]; then
    abort_missing_tailscale_authkey
  fi

  log "${tty_tp}joining${tty_reset} ${tty_ts}tailscale${tty_reset} as ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}"
  debug "${tty_tp}running${tty_reset}" sudo tailscale "${tailscale_display_args[@]}"
  if ! sudo tailscale "${tailscale_args[@]}"; then
    abort "agentbox Tailscale setup failed."
  fi

  show_tailscale_status_summary
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  validate_platform
  apply_noninteractive_mode
  check_sudo_access
  prepare_agentbox_source
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
  debug raw AGENTBOX_HOSTNAME="${AGENTBOX_HOSTNAME_VALUE}"
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
  debug raw AGENTBOX_BREWFILE="$(agentbox_brewfile_display)"
  run_agentbox_hostname_setup
  run_agentbox_macos_settings
  run_bootbox_for_agentbox_brewfile
  run_agentbox_ssh_setup
  run_agentbox_tailscale_setup
  run_agentbox_launchd_health_setup
  run_agentbox_post_bootstrap_summary
}

main "$@"
