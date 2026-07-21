#!/bin/bash
set -euo pipefail

case_root="${1:?case root is required}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
home="${case_root}/home"
state_dir="${home}/.agentbox"
finalizer_plist="${home}/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist"

/bin/mkdir -p "$(dirname "${finalizer_plist}")" "${state_dir}"
if [[ ! -e "${finalizer_plist}" ]]; then
  printf '%s\n' finalizer > "${finalizer_plist}"
fi

env \
  HOME="${home}" \
  USER=openclaw \
  LOGNAME=openclaw \
  OPENCLAW_HOME="${home}" \
  OPENCLAW_STATE_DIR="${home}/.openclaw" \
  AGENTBOX_OPENCLAW_BIN="${script_dir}/fixtures/openclaw" \
  AGENTBOX_LAUNCHCTL_BIN="${script_dir}/fixtures/launchctl" \
  AGENTBOX_FINALIZER_STATE_DIR="${state_dir}" \
  AGENTBOX_FINALIZER_MAX_ATTEMPTS=1 \
  AGENTBOX_FINALIZER_RETRY_DELAY=0 \
  TEST_OPENCLAW_INSTALLED="${case_root}/installed" \
  TEST_OPENCLAW_INSTALL_LOG="${case_root}/install.log" \
  "${repo_root}/libexec/agentbox-openclaw-finalize.sh"
