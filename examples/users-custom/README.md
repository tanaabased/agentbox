# Users Custom Example

This example verifies OpenClaw runner behavior for a newly created custom macOS user. It is
intended for CI by default because it mutates local users, Homebrew state, SSH, OpenClaw, and
launchd.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should run boot.sh successfully with a new custom openclaw runner
boot.sh \
  --force \
  --hostname "TANAABAGENTBOXUSERSCUSTOM" \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-identity "Luna Fresh Claw <luna>" \
  --openclaw-password "LunaFreshClawPass1!" \
  --openclaw-auth-choice skip \
  --skip-openclaw-autologin
```

## Testing

```bash
# should create the openclaw runner account
id -u luna >/dev/null
dscl . -read /Users/luna RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "Luna Fresh Claw"
test -d /Users/luna
test "$(stat -f "%Su" /Users/luna)" = "luna"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should keep openclaw runner autologin skipped
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=luna"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Luna Fresh Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_exists_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_home_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
