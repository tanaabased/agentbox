# Users Custom Example

This example verifies OpenClaw runner behavior for a newly created custom macOS user. It is
intended for CI by default because it mutates local users, Homebrew state, SSH, OpenClaw, and
launchd.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should run agentbox successfully with a new custom openclaw runner
set -o pipefail
agentbox \
  --force \
  --hostname "TANAABAGENTBOXUSERSCUSTOM" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-autologin off \
  --openclaw-identity "Luna Fresh Claw <luna>" \
  --openclaw-password "LunaFreshClawPass1!" \
  --openclaw-auth-choice skip \
  2>&1 | tee "$TMPDIR/users-custom.log"
```

## Testing

```bash
# should create the openclaw runner account
id -u luna >/dev/null
dscl . -read /Users/luna RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "Luna Fresh Claw"
test -d /Users/luna
test "$(stat -f "%Su" /Users/luna)" = "luna"

# should print the custom runner graphical session dashboard command
grep -F "open the openclaw dashboard from the luna graphical session:" "$TMPDIR/users-custom.log"
grep -Fx "  openclaw dashboard" "$TMPDIR/users-custom.log"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should use native user LaunchAgent mode without changing CI autologin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=luna"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Luna Fresh Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_exists_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_home_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should stage activation until the runtime user logs in
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"
```
