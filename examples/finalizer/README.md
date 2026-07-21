# Finalizer Example

This non-mutating example verifies the one-time Aqua finalizer with hermetic OpenClaw and launchctl
fixtures. It exercises the finalizer executable without changing the host login session or launchd
state.

## Setup

```bash
# should have the finalizer and fixtures available
test -x "$AGENTBOX_PAYLOAD_DIR/libexec/agentbox-openclaw-finalize.sh"
test -x "$AGENTBOX_PAYLOAD_DIR/examples/finalizer/run-case.sh"
test -x "$AGENTBOX_PAYLOAD_DIR/examples/finalizer/fixtures/openclaw"
test -x "$AGENTBOX_PAYLOAD_DIR/examples/finalizer/fixtures/launchctl"
```

## Testing

```bash
# should install verify record completion and remove its plist
case_root="$TMPDIR/finalizer-success"
"$AGENTBOX_PAYLOAD_DIR/examples/finalizer/run-case.sh" "$case_root"
grep -Fx "status=healthy" "$case_root/home/.agentbox/openclaw-gateway-finalizer-state"
test ! -e "$case_root/home/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist"
test "$(wc -l < "$case_root/install.log" | tr -d ' ')" -eq 1

# should retain retry state and its plist after a failed install
case_root="$TMPDIR/finalizer-failure"
set +e
TEST_OPENCLAW_INSTALL_FAIL=1 "$AGENTBOX_PAYLOAD_DIR/examples/finalizer/run-case.sh" "$case_root"
command_status="$?"
set -e
test "$command_status" -eq 7
grep -Fx "status=failed" "$case_root/home/.agentbox/openclaw-gateway-finalizer-state"
grep -Fx "exit_code=7" "$case_root/home/.agentbox/openclaw-gateway-finalizer-state"
test -f "$case_root/home/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist"

# should complete on a later retry
case_root="$TMPDIR/finalizer-retry"
set +e
TEST_OPENCLAW_INSTALL_FAIL=1 "$AGENTBOX_PAYLOAD_DIR/examples/finalizer/run-case.sh" "$case_root"
first_status="$?"
set -e
test "$first_status" -eq 7
"$AGENTBOX_PAYLOAD_DIR/examples/finalizer/run-case.sh" "$case_root"
grep -Fx "status=healthy" "$case_root/home/.agentbox/openclaw-gateway-finalizer-state"
test ! -e "$case_root/home/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist"
test "$(wc -l < "$case_root/install.log" | tr -d ' ')" -eq 2

# should fail when install succeeds but launchd and RPC never become healthy
case_root="$TMPDIR/finalizer-post-install-failure"
set +e
TEST_OPENCLAW_POST_INSTALL_HEALTH_FAIL=1 "$AGENTBOX_PAYLOAD_DIR/examples/finalizer/run-case.sh" "$case_root"
command_status="$?"
set -e
test "$command_status" -ne 0
grep -Fx "status=failed" "$case_root/home/.agentbox/openclaw-gateway-finalizer-state"
test -f "$case_root/home/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist"
test "$(wc -l < "$case_root/install.log" | tr -d ' ')" -eq 1
```
