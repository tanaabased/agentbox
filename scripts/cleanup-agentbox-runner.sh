#!/usr/bin/env bash
set -euo pipefail

AUTHORIZED_KEY_FILES=()
BREWGROUPS=()
USERS=()
REMOVE_TMPDIR="0"

abort() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOUSAGE'
Usage: cleanup-agentbox-runner.sh [--authorized-key-file <path>]... [--brewgroup <group>]... [--user <name>]... [--remove-tmpdir]
EOUSAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --authorized-key-file)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        abort "--authorized-key-file requires a path."
      fi
      AUTHORIZED_KEY_FILES+=("$2")
      shift 2
      ;;
    --authorized-key-file=*)
      if [[ -z "${1#*=}" ]]; then
        abort "--authorized-key-file requires a path."
      fi
      AUTHORIZED_KEY_FILES+=("${1#*=}")
      shift
      ;;
    --brewgroup)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        abort "--brewgroup requires a group name."
      fi
      BREWGROUPS+=("$2")
      shift 2
      ;;
    --brewgroup=*)
      if [[ -z "${1#*=}" ]]; then
        abort "--brewgroup requires a group name."
      fi
      BREWGROUPS+=("${1#*=}")
      shift
      ;;
    --user)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        abort "--user requires a user name."
      fi
      USERS+=("$2")
      shift 2
      ;;
    --user=*)
      if [[ -z "${1#*=}" ]]; then
        abort "--user requires a user name."
      fi
      USERS+=("${1#*=}")
      shift
      ;;
    --remove-tmpdir)
      REMOVE_TMPDIR="1"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      abort "unrecognized option $1."
      ;;
  esac
done

remove_authorized_key_file() {
  local key_file="$1"
  local key_line
  local authorized_keys="${HOME}/.ssh/authorized_keys"
  local clean_file

  if [[ ! -f "${key_file}" || ! -f "${authorized_keys}" ]]; then
    return 0
  fi

  clean_file="$(mktemp "${TMPDIR:-/tmp}/agentbox-authorized-keys.XXXXXX")"
  while IFS= read -r key_line || [[ -n "${key_line}" ]]; do
    if [[ -z "${key_line}" || "${key_line}" == \#* ]]; then
      continue
    fi

    grep -vxF -- "${key_line}" "${authorized_keys}" > "${clean_file}" || true
    cp "${clean_file}" "${authorized_keys}"
  done < "${key_file}"

  rm -f "${clean_file}"
}

remove_brewgroup() {
  local group="$1"

  if [[ -z "${group}" || "${group}" == "brewer" ]]; then
    return 0
  fi

  if dscl . -read "/Groups/${group}" >/dev/null 2>&1; then
    sudo dscl . -delete "/Groups/${group}" >/dev/null 2>&1 || true
  fi
}

user_exists() {
  dscl . -read "/Users/$1" >/dev/null 2>&1 || id -u "$1" >/dev/null 2>&1
}

user_home_dir() {
  dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '/NFSHomeDirectory:/ {print $2; exit}'
}

remove_user() {
  local user="$1"
  local home=""

  if [[ -z "${user}" || "${user}" == "$(id -un)" || "${user}" == "root" ]]; then
    return 0
  fi

  home="$(user_home_dir "${user}")"
  sudo sysadminctl -deleteUser "${user}" >/dev/null 2>&1 || true
  sudo dscl . -delete "/Users/${user}" >/dev/null 2>&1 || true
  sudo dscacheutil -flushcache >/dev/null 2>&1 || true

  if [[ -n "${home}" && "${home}" == "/Users/${user}" && -d "${home}" ]]; then
    sudo rm -rf "${home}" >/dev/null 2>&1 || true
  fi

  if [[ -d "/Users/${user}" ]]; then
    sudo rm -rf "/Users/${user}" >/dev/null 2>&1 || true
  fi

  if user_exists "${user}"; then
    abort "failed to remove user ${user}."
  fi
}

if [[ "${#AUTHORIZED_KEY_FILES[@]}" -gt 0 ]]; then
  for authorized_key_file in "${AUTHORIZED_KEY_FILES[@]}"; do
    remove_authorized_key_file "${authorized_key_file}"
  done
fi

if [[ "${#USERS[@]}" -gt 0 ]]; then
  for user in "${USERS[@]}"; do
    remove_user "${user}"
  done
fi

if [[ "${#BREWGROUPS[@]}" -gt 0 ]]; then
  for brewgroup in "${BREWGROUPS[@]}"; do
    remove_brewgroup "${brewgroup}"
  done
fi

sudo launchctl bootout system /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist >/dev/null 2>&1 || true
sudo launchctl bootout system /Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist >/dev/null 2>&1 || true
sudo launchctl bootout system /Library/LaunchDaemons/homebrew.mxcl.tailscale.plist >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/homebrew.mxcl.tailscale" >/dev/null 2>&1 || true
sudo sysadminctl -autologin off >/dev/null 2>&1 || true
sudo rm -f /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist
sudo rm -f /Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist
sudo rm -f /Library/LaunchDaemons/homebrew.mxcl.tailscale.plist
sudo rm -f "${HOME}/Library/LaunchAgents/homebrew.mxcl.tailscale.plist"
sudo rm -rf /opt/tanaab/agentbox /var/log/tanaab/agentbox /var/db/tanaab/agentbox
sudo rm -f /etc/paths.d/00-agentbox-homebrew
sudo rm -f /etc/ssh/sshd_config.d/agentbox.conf
sudo launchctl kickstart -k system/com.openssh.sshd >/dev/null 2>&1 || true

if command -v tailscale >/dev/null 2>&1; then
  sudo tailscale logout >/dev/null 2>&1 || true
fi

rm -rf "${HOME}/tanaab/agentbox"

if [[ "${REMOVE_TMPDIR}" == "1" && -n "${TMPDIR:-}" && "${TMPDIR}" != "/" ]]; then
  rm -rf "${TMPDIR}"
fi
