#!/bin/bash
set -euo pipefail

openclaw_bin="${AGENTBOX_OPENCLAW_BIN:?AGENTBOX_OPENCLAW_BIN is required}"
launchctl_bin="${AGENTBOX_LAUNCHCTL_BIN:-/bin/launchctl}"
gateway_label="${AGENTBOX_OPENCLAW_GATEWAY_LABEL:-ai.openclaw.gateway}"
state_dir="${AGENTBOX_FINALIZER_STATE_DIR:-${HOME}/.agentbox}"
state_file="${state_dir}/openclaw-gateway-finalizer-state"
finalizer_plist="${HOME}/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist"
step="starting"
max_attempts="${AGENTBOX_FINALIZER_MAX_ATTEMPTS:-45}"
retry_delay="${AGENTBOX_FINALIZER_RETRY_DELAY:-2}"

write_state() {
  local status="$1"
  local exit_code="${2:-0}"
  local tmp="${state_file}.tmp.$$"

  /bin/mkdir -p "${state_dir}"
  /bin/chmod 700 "${state_dir}"
  {
    printf 'status=%s\n' "${status}"
    printf 'step=%s\n' "${step}"
    printf 'updated_at=%s\n' "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'exit_code=%s\n' "${exit_code}"
  } > "${tmp}"
  /bin/chmod 600 "${tmp}"
  /bin/mv -f "${tmp}" "${state_file}"
}

finish() {
  local exit_code="$?"

  trap - EXIT
  if [[ "${exit_code}" -ne 0 ]]; then
    write_state failed "${exit_code}" || true
  fi
  exit "${exit_code}"
}

gateway_job_loaded() {
  "${launchctl_bin}" print "gui/${UID}/${gateway_label}" >/dev/null 2>&1
}

gateway_rpc_healthy() {
  "${openclaw_bin}" gateway status --require-rpc --timeout 10000 >/dev/null 2>&1
}

/bin/mkdir -p "${state_dir}"
/bin/chmod 700 "${state_dir}"
trap finish EXIT
trap 'exit 1' HUP INT TERM

write_state installing
step="validating-configuration"
"${openclaw_bin}" config validate --json >/dev/null

step="installing-native-launchagent"
"${openclaw_bin}" gateway install --force

step="waiting-for-launchagent-and-rpc"
attempts=0
while [[ "${attempts}" -lt "${max_attempts}" ]]; do
  attempts=$((attempts + 1))
  if gateway_job_loaded && gateway_rpc_healthy; then
    break
  fi
  /bin/sleep "${retry_delay}"
done

gateway_job_loaded
gateway_rpc_healthy

step="complete"
write_state healthy
/bin/rm -f "${finalizer_plist}"
