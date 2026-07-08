# Tailscale Example

This example verifies the explicit disabled-Tailscale path while keeping the Tailscale formula
available for later use. It is intended for CI by default because it mutates system settings,
Homebrew state, SSH, launchd, and OpenClaw.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should run agentbox successfully with tailscale disabled
AGENTBOX_TAILSCALE_AUTHKEY=off agentbox \
  --force \
  --hostname "TANAABAGENTBOXTAILSCALE" \
  --brewgroup off \
  --openclaw-identity "Tess Tailscale Claw <tess>" \
  --openclaw-password "TessTailscaleClawPass1!"
```

## Testing

```bash
# should install tailscale
test -x "$(brew --prefix)/bin/tailscale"

# should leave tailscaled stopped
if pgrep -x tailscaled >/dev/null; then exit 1; fi

# should leave tailscale unjoined
if status_json="$(tailscale status --json 2>/dev/null)" &&
  printf "%s\n" "$status_json" | jq -e '((.Self.HostName // "") != "") or (((.Self.TailscaleIPs // []) | length) > 0)'
then
  exit 1
fi
if tailscale ip -4 2>/dev/null | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"; then exit 1; fi

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOXTAILSCALE"

# should report skipped tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=skipped"

# should report loopback openclaw gateway exposure
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=off"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
