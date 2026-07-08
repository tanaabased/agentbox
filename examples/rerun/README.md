# Rerun Example

This example verifies that a Tailscale-joined agentbox host can run `boot.sh` again without a
Tailscale auth key. It is intended for CI by default because it mutates system settings, Homebrew
state, SSH, launchd, OpenClaw, and Tailscale.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should have a tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should run boot.sh successfully with a tailscale auth key
boot.sh \
  --force \
  --hostname "TANAABAGENTBOX-RERUN$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --openclaw-identity "Rita Rerun Claw <rita>" \
  --openclaw-password "RitaRerunClawPass1!" \
  --openclaw-auth-choice skip \
  --openclaw-gateway-port 18789

# should rerun boot.sh successfully without a tailscale auth key
AGENTBOX_TAILSCALE_AUTHKEY="" boot.sh \
  --force \
  --hostname "TANAABAGENTBOX-RERUN$GITHUB_RUN_ID" \
  --openclaw-identity "Rita Rerun Claw <rita>" \
  --openclaw-password "RitaRerunClawPass1!" \
  --openclaw-auth-choice skip \
  --openclaw-gateway-port 18789
```

## Testing

```bash
# should keep the openclaw runner account
id -u rita >/dev/null
dscl . -read /Users/rita RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "Rita Rerun Claw"
test -d /Users/rita
test "$(stat -f "%Su" /Users/rita)" = "rita"

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-RERUN$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_tailscale_hostname=AGENTBOX-RERUN$GITHUB_RUN_ID"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=rita"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Rita Rerun Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report openclaw gateway health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=serve"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_port=18789"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_ok=1"

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
