# OpenClaw Example

This example runs the real `agentbox` setup with OpenClaw gateway options, then verifies the
resulting GitHub-hosted macOS runner state. It is intended for CI by default because it mutates
system settings, Homebrew state, SSH, launchd, OpenClaw, and Tailscale.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should have a tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should have an openai api key from the workflow secret
test -n "$OPENAI_API_KEY"

# should run agentbox successfully with custom openclaw gateway options
set -o pipefail
OPENAI_API_KEY="$OPENAI_API_KEY" agentbox \
  --debug \
  --force \
  --hostname "TANAABAGENTBOX-OC$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --openclaw-password "OpenClawGatewayPass1!" \
  --openclaw-auth-choice openai-api-key \
  --openclaw-auth-env OPENAI_API_KEY \
  --openclaw-gateway-port 18888 \
  2>&1 | tee "$TMPDIR/openclaw.log"
```

## Testing

```bash
# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-OC$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_tailscale_hostname=AGENTBOX-OC$GITHUB_RUN_ID"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=openclaw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=A Tanaab-based Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report custom openclaw gateway health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_auth_choice=openai-api-key"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_service_mode=system"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=serve"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_port=18888"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_status_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_ok=1"

# should not print the openai api key
! grep -F -- "$OPENAI_API_KEY" "$TMPDIR/openclaw.log"

# should run openclaw onboarding non-interactively in CI
grep -F -- "--non-interactive" "$TMPDIR/openclaw.log"
grep -F -- "--accept-risk" "$TMPDIR/openclaw.log"
grep -F -- "--json" "$TMPDIR/openclaw.log"

# should render the openclaw gateway launchd daemon arguments
sudo /usr/libexec/PlistBuddy -c "Print :WorkingDirectory" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/Users/openclaw/.openclaw"
sudo /usr/libexec/PlistBuddy -c "Print :AgentboxVersion" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -E '^.+$'
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/bin/sh"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:1" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway-env-wrapper.sh"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:2" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:4" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "gateway"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:6" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "18888"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:8" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "loopback"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:10" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "serve"

# should render the managed openclaw gateway service environment
sudo stat -f "%Su" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env | grep -Fx "openclaw"
sudo stat -f "%Lp" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env | grep -Fx "600"
sudo stat -f "%Lp" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway-env-wrapper.sh | grep -Fx "700"
sudo grep -F "generated by agentbox. do not edit" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_STATE_DIR='/Users/openclaw/.openclaw'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export NODE_EXTRA_CA_CERTS='/etc/ssl/cert.pem'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export NODE_USE_SYSTEM_CA='1'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export AGENTBOX_HEALTH_COMMAND='/opt/tanaab/agentbox/bin/health.sh --report'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
! sudo grep -F "OPENAI_API_KEY" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env

# should report the openclaw gateway tailscale serve prerequisites and route
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_magicdns_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_https_certificates_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_serve_route_ok=1"

# should reach the openclaw gateway ready endpoint through tailscale magicdns over https
skip
# gateway_dns_name="$(tailscale status --json --peers=false | tee /dev/stderr | jq -r '.Self.DNSName // ""' | sed 's/[.]$//')"
# test -n "$gateway_dns_name"
# curl \
#   --fail \
#   --silent \
#   --show-error \
#   --http1.1 \
#   --ipv4 \
#   --connect-timeout 10 \
#   --max-time 30 \
#   --retry 5 \
#   --retry-delay 2 \
#   --retry-all-errors \
#   --retry-max-time 90 \
#   "https://$gateway_dns_name/readyz" | tee /dev/stderr

# should reach the openclaw gateway ready endpoint through tailscale magicdns over http
gateway_dns_name="$(tailscale status --json --peers=false | tee /dev/stderr | jq -r '.Self.DNSName // ""' | sed 's/[.]$//')"
test -n "$gateway_dns_name"
sudo tailscale serve --bg --http=80 --yes http://127.0.0.1:18888
curl \
  --fail \
  --silent \
  --show-error \
  --http1.1 \
  --ipv4 \
  --connect-timeout 10 \
  --max-time 30 \
  --retry 5 \
  --retry-delay 2 \
  --retry-all-errors \
  --retry-max-time 90 \
  "http://$gateway_dns_name/readyz" | tee /dev/stderr

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
