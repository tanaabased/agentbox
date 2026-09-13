#!/bin/bash
set -euo pipefail

# Exercise the shipped functions without rerunning the host bootstrap or health dispatcher.
# Import only complete, named top-level definitions; fail if a source refactor removes one.
import_functions() {
  local source_path="$1"
  local names="$2"
  local definitions=""
  definitions="$(awk -v names="${names}" '
    BEGIN { count = split(names, requested, " "); for (i = 1; i <= count; i++) wanted[requested[i] "() {"] = 1 }
    !active && ($0 in wanted) { active = 1; found++ }
    active { print }
    active && /^}$/ { active = 0 }
    END { if (active || found != count) exit 1 }
  ' "${source_path}")"
  eval "${definitions}"
}

if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  printf '%s\n' 'resolver fixtures require an ephemeral GitHub Actions runner.' >&2
  exit 1
fi
if pgrep -x tailscaled >/dev/null; then
  printf '%s\n' 'resolver fixtures require tailscaled to be stopped.' >&2
  exit 1
fi

action="${1:?action is required}"
fixture="${2:?fixture is required}"
case "${fixture}" in
  created | repaired | preserved | conflict) ;;
  *) exit 2 ;;
esac
status_json="$(jq -nc --arg suffix "${fixture}.agentbox-resolver.invalid" '{CurrentTailnet: {MagicDNSSuffix: $suffix}}')"

# Globals below are consumed by the imported production functions.
# shellcheck disable=SC2034
case "${action}" in
  reconcile)
    import_functions "$(command -v agentbox)" \
      "abort value_enabled shell_join debug_enabled debug log warn execute sudo json_value tailscale_magicdns_suffix_value tailscale_magicdns_suffix_valid configure_tailscale_magicdns_resolver"
    SUDO_BIN=/usr/bin/sudo
    SUDO_SESSION_ACTIVE=1
    DEBUG=0
    tty_tp="" tty_ts="" tty_reset="" tty_yellow=""
    configure_tailscale_magicdns_resolver "${status_json}"
    ;;
  health)
    import_functions /opt/tanaab/agentbox/bin/health.sh \
      "tailscale_magicdns_suffix_value tailscale_magicdns_suffix_valid tailscale_magicdns_resolver_path_value tailscale_magicdns_resolver_ok_value"
    JQ_BIN="$(command -v jq)"
    printf 'resolver_ok=%s\n' "$(tailscale_magicdns_resolver_ok_value "${status_json}")"
    ;;
  *) exit 2 ;;
esac
