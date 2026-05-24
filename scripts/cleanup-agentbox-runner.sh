#!/usr/bin/env bash
set -euo pipefail

AUTHORIZED_KEY_FILES=()
REMOVE_TMPDIR="0"

abort() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOUSAGE'
Usage: cleanup-agentbox-runner.sh [--authorized-key-file <path>]... [--remove-tmpdir]
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

if [[ "${#AUTHORIZED_KEY_FILES[@]}" -gt 0 ]]; then
  for authorized_key_file in "${AUTHORIZED_KEY_FILES[@]}"; do
    remove_authorized_key_file "${authorized_key_file}"
  done
fi

sudo launchctl bootout system /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist >/dev/null 2>&1 || true
sudo rm -f /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist
sudo rm -rf /opt/tanaab/agentbox /var/log/tanaab/agentbox /var/db/tanaab/agentbox

if command -v tailscale >/dev/null 2>&1; then
  sudo tailscale logout >/dev/null 2>&1 || true
fi

if command -v brew >/dev/null 2>&1; then
  sudo brew services stop tailscale >/dev/null 2>&1 || true
fi

rm -rf "${HOME}/tanaab/agentbox"

if [[ "${REMOVE_TMPDIR}" == "1" && -n "${TMPDIR:-}" && "${TMPDIR}" != "/" ]]; then
  rm -rf "${TMPDIR}"
fi
