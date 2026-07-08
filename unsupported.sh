#!/bin/sh
set -u

PUBLIC_ORIGIN="https://agentbox.tanaab.sh"
MACOS_SCRIPT_URL="${PUBLIC_ORIGIN}/macos.sh"
REPO_URL="https://github.com/tanaabased/agentbox"

color_enabled() {
  if [ -n "${NO_COLOR:-}" ]; then
    return 1
  fi

  [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]
}

if color_enabled; then
  tty_bold="$(printf '\033[1m')"
  tty_dim="$(printf '\033[2m')"
  tty_reset="$(printf '\033[0m')"
  tty_yellow="$(printf '\033[33m')"
  tty_tp="$(printf '\033[38;2;0;200;138m')"
  tty_ts="$(printf '\033[38;2;219;39;119m')"
else
  tty_bold=""
  tty_dim=""
  tty_reset=""
  tty_yellow=""
  tty_tp=""
  tty_ts=""
fi

detect_platform() {
  kernel="$(uname -s 2>/dev/null || printf unknown)"
  machine="$(uname -m 2>/dev/null || printf unknown)"

  case "${kernel}" in
    Darwin)
      printf "macOS/Darwin %s" "${machine}"
      ;;
    Linux)
      printf "Linux %s" "${machine}"
      ;;
    CYGWIN* | MINGW* | MSYS*)
      printf "Windows shell %s %s" "${kernel}" "${machine}"
      ;;
    *)
      if [ -n "${OS:-}" ]; then
        printf "%s %s %s" "${OS}" "${kernel}" "${machine}"
      else
        printf "%s %s" "${kernel}" "${machine}"
      fi
      ;;
  esac
}

platform="$(detect_platform)"

printf "\n%s" "${tty_tp}"
cat <<'ART'
                         _   _
  __ _  __ _  ___ _ __ | |_| |__   _____  __
 / _` |/ _` |/ _ \ '_ \| __| '_ \ / _ \ \/ /
| (_| | (_| |  __/ | | | |_| |_) | (_) >  <
 \__,_|\__, |\___|_| |_|\__|_.__/ \___/_/\_\
       |___/
ART
printf "%s\n" "${tty_reset}"

printf "%sunsupported platform%s\n\n" "${tty_yellow}" "${tty_reset}"
printf "agentbox currently supports %smacOS 26.x%s bootstrap only.\n" "${tty_bold}" "${tty_reset}"
printf "detected: %s%s%s\n\n" "${tty_ts}" "${platform}" "${tty_reset}"
printf "Use the macOS entrypoint on a supported Mac:\n"
printf "  %scurl -fsSL %s | bash%s\n\n" "${tty_dim}" "${MACOS_SCRIPT_URL}" "${tty_reset}"
printf "Project docs:\n"
printf "  %s%s%s\n" "${tty_dim}" "${REPO_URL}" "${tty_reset}"

exit 2
