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
REQUIRED_CURL_VERSION="7.41.0"
BOOTBOX_URL="https://bootbox.tanaab.sh/bootbox.sh"
DEFAULT_AGENTBOX_HOSTNAME="TANAABAGENTBOX1"
DEFAULT_TAILSCALE_TAGS="tag:agentbox"
AGENTBOX_OPT_DIR="/opt/tanaab/agentbox"
AGENTBOX_LOG_DIR="/var/log/tanaab/agentbox"
AGENTBOX_STATE_DIR="/var/db/tanaab/agentbox"
AGENTBOX_HEALTH_LABEL="dev.tanaab.agentbox.health"
AGENTBOX_REPO_HTTPS_URL="https://github.com/tanaabased/agentbox.git"
AGENTBOX_REPO_ARCHIVE_BASE_URL="https://github.com/tanaabased/agentbox/archive/refs/tags"

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

  if [[ "${#values[@]}" -eq 0 ]]; then
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
TAILSCALE_TAGS="${AGENTBOX_TAILSCALE_TAGS:-${DEFAULT_TAILSCALE_TAGS}}"
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
  local tailscale_authkey_display="none"
  local authorized_keys_display="none"

  if debug_enabled; then
    debug_display="on"
  fi

  if force_enabled; then
    force_display="on"
  fi

  tailscale_authkey_display="$(mask_secret_for_display "${TAILSCALE_AUTHKEY:-}")"
  if [[ "${#AUTHORIZED_KEY_SPECS[@]}" -gt 0 ]]; then
    authorized_keys_display="${#AUTHORIZED_KEY_SPECS[@]} provided"
  fi

  cat <<EOS
Usage: ${tty_dim}[NONINTERACTIVE=1] [CI=1]${tty_reset} ${tty_bold}${SCRIPT_NAME}${tty_reset} ${tty_dim}[options]${tty_reset}

${tty_tp}Options:${tty_reset}
  --agentbox-version  installs a tagged release, accepts 1.2.3 or v1.2.3 ${tty_dim}[default: $(agentbox_version_display)]${tty_reset}
  --authorized-key    adds a raw public key or public-key file path for SSH ${tty_dim}[default: ${authorized_keys_display}]${tty_reset}
  --tailscale-authkey sets a raw one-time or preauthorized Tailscale auth key ${tty_dim}[default: ${tailscale_authkey_display}]${tty_reset}
  --hostname          sets the system hostname and Tailscale name source ${tty_dim}[default: ${AGENTBOX_HOSTNAME_VALUE}]${tty_reset}
  --version           shows version of this script
  --debug             shows debug messages ${tty_dim}[default: ${debug_display}]${tty_reset}
  --force             forces supported replacement operations ${tty_dim}[default: ${force_display}]${tty_reset}
  -h, --help          displays this help message
  -y, --yes           runs with all defaults and no prompts, sets NONINTERACTIVE=1

${tty_tp}Environment Variables:${tty_reset}
  AGENTBOX_VERSION               tagged release to install, accepts 1.2.3 or v1.2.3
  AGENTBOX_AUTHORIZED_KEY        raw public key or public-key file path for SSH
  AGENTBOX_TAILSCALE_AUTHKEY     raw Tailscale auth key
  AGENTBOX_HOSTNAME              system hostname and Tailscale name source
  AGENTBOX_TAILSCALE_TAGS        comma-separated Tailscale tags to advertise ${tty_dim}[default: ${TAILSCALE_TAGS:-none}]${tty_reset}
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
  log "${tty_tp}setting${tty_reset} macOS system identity to ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
  execute sudo scutil --set ComputerName "${AGENTBOX_HOSTNAME_VALUE}"
  execute sudo scutil --set HostName "${AGENTBOX_HOSTNAME_VALUE}"
  execute sudo scutil --set LocalHostName "${AGENTBOX_HOSTNAME_VALUE}"
}

run_agentbox_macos_settings() {
  log "${tty_tp}applying${tty_reset} headless macOS power and firewall settings"

  execute sudo pmset -a sleep 0
  execute sudo pmset -a disksleep 0
  execute sudo pmset -a displaysleep 0
  if ! sudo pmset -a powernap 0; then
    warn "could not disable powernap on this Mac; continuing."
  fi

  execute sudo pmset -a autorestart 1
  execute sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  execute sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
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

  for existing in "${AUTHORIZED_KEY_LINES[@]}"; do
    if [[ "${existing}" == "${line}" ]]; then
      return 0
    fi
  done

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

  abort "authorized key value must be a raw public key line or a readable public-key file path."
}

resolve_authorized_key_specs() {
  local spec

  AUTHORIZED_KEY_LINES=()
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

  execute sudo chown "${user}:staff" "${authorized_keys}"
  execute sudo chmod 600 "${authorized_keys}"
  log "${tty_tp}installed${tty_reset} ${installed_count} new SSH authorized key entries for ${tty_ts}${user}${tty_reset}"
}

run_agentbox_ssh_setup() {
  log "${tty_tp}enabling${tty_reset} classic SSH for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
  execute sudo systemsetup -setremotelogin on
  if [[ "${#AUTHORIZED_KEY_LINES[@]}" -gt 0 ]]; then
    install_authorized_keys_for_user "${ADMIN_USER}"
    warn "SSH password-login hardening is deferred until key-based SSH has been verified."
  else
    log "${tty_tp}skipping${tty_reset} SSH authorized key install because no keys were provided"
    warn "classic SSH is enabled, but key-based access was not configured by this bootstrap run."
  fi
}

write_agentbox_health_script() {
  if ! sudo tee "${AGENTBOX_OPT_DIR}/bin/health.sh" >/dev/null <<'EOHEALTH'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'uptime=%s\n' "$(uptime)"
  printf 'tailscale_ip=%s\n' "$(tailscale ip -4 2>/dev/null || true)"
  printf '%s\n' '---'
} >> /var/log/tanaab/agentbox/health.log
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
  log "${tty_tp}installing${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
  execute sudo mkdir -p "${AGENTBOX_OPT_DIR}/bin" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  execute sudo chown -R root:wheel "${AGENTBOX_OPT_DIR}" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
  execute sudo chmod 755 "${AGENTBOX_OPT_DIR}" "${AGENTBOX_OPT_DIR}/bin" "${AGENTBOX_LOG_DIR}" "${AGENTBOX_STATE_DIR}"
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
  hostname || true
  scutil --get ComputerName || true
  scutil --get HostName || true
  scutil --get LocalHostName || true
  pmset -g || true
  sudo systemsetup -getremotelogin || true
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate || true
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode || true
  tailscale status || true
  tailscale ip -4 || true
  sudo launchctl print "system/${AGENTBOX_HEALTH_LABEL}" 2>/dev/null || true
}

plan_action() {
  PLANNED_ACTIONS+=("$1")
}

have_planned_actions() {
  [[ "${#PLANNED_ACTIONS[@]}" -gt 0 ]]
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

  if [[ -z "${TAILSCALE_AUTHKEY}" ]]; then
    abort_multi "$(cat <<EOABORT
you must provide a Tailscale auth key before using this wrapper.
set ${tty_bold}AGENTBOX_TAILSCALE_AUTHKEY${tty_reset}, or pass ${tty_bold}--tailscale-authkey${tty_reset}. Prefer the environment variable to avoid shell-history exposure.
EOABORT
)"
  fi

  resolve_authorized_key_specs

  if ! hostname_valid "${AGENTBOX_HOSTNAME_VALUE}"; then
    abort "hostname ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} must be DNS-safe."
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
  plan_action "${tty_tp}set${tty_reset} macOS ComputerName, HostName, and LocalHostName to ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset}"
  plan_action "${tty_tp}apply${tty_reset} headless power and firewall settings"
  plan_action "${tty_tp}run${tty_reset} ${tty_ts}bootbox${tty_reset} against the ${tty_ts}agentbox${tty_reset} Brewfile"
  plan_action "${tty_tp}enable${tty_reset} classic SSH for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
  if [[ "${#AUTHORIZED_KEY_LINES[@]}" -gt 0 ]]; then
    plan_action "${tty_tp}install${tty_reset} ${tty_ts}${#AUTHORIZED_KEY_LINES[@]}${tty_reset} authorized key entries for invoking admin user ${tty_ts}${ADMIN_USER}${tty_reset}"
  fi
  plan_action "${tty_tp}configure${tty_reset} ${tty_ts}tailscaled${tty_reset} as a launchd service and join Tailscale as ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset} from hostname ${tty_ts}${AGENTBOX_HOSTNAME_VALUE}${tty_reset} using masked auth key $(mask_secret_for_display "${TAILSCALE_AUTHKEY}")"
  plan_action "${tty_tp}install${tty_reset} launchd health check ${tty_ts}${AGENTBOX_HEALTH_LABEL}${tty_reset}"
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

run_agentbox_tailscale_setup() {
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

  check_sudo_access "before Tailscale service setup"
  require_command brew
  require_command tailscale

  if [[ -n "${TAILSCALE_TAGS}" ]]; then
    tailscale_args+=("--advertise-tags=${TAILSCALE_TAGS}")
    tailscale_display_args+=("--advertise-tags=${TAILSCALE_TAGS}")
  fi

  log "${tty_tp}starting${tty_reset} ${tty_ts}tailscaled${tty_reset} as a system launchd service"
  execute sudo brew services start tailscale

  log "${tty_tp}joining${tty_reset} ${tty_ts}tailscale${tty_reset} as ${tty_ts}${TAILSCALE_HOSTNAME_VALUE}${tty_reset}"
  debug "${tty_tp}running${tty_reset}" sudo tailscale "${tailscale_display_args[@]}"
  if ! sudo tailscale "${tailscale_args[@]}"; then
    abort "agentbox Tailscale setup failed."
  fi

  log "${tty_tp}tailscale status:${tty_reset}"
  debug "${tty_tp}running${tty_reset}" tailscale status
  tailscale status || true
  debug "${tty_tp}running${tty_reset}" tailscale ip -4
  tailscale ip -4 || true
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
  debug raw AGENTBOX_AUTHORIZED_KEY_COUNT="${#AUTHORIZED_KEY_LINES[@]}"
  debug raw TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME_VALUE}"
  debug raw AGENTBOX_TAILSCALE_TAGS="${TAILSCALE_TAGS}"
  debug raw AGENTBOX_TAILSCALE_AUTHKEY="$(mask_secret_for_display "${TAILSCALE_AUTHKEY}")"
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
