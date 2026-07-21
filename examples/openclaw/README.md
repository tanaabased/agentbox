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
  --openclaw-autologin off \
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

# should report custom openclaw gateway configuration staged for first login
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_auth_choice=openai-api-key"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_service_mode=user"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=serve"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_port=18888"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_finalizer_installed=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_admin_app_attach_only_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_admin_app_gateway_config_expected=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_admin_app_gateway_config_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_auth_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_activation_ok=0"

# should configure permanent openclaw fallback gateway branding
test "$(sudo jq -r '.ui.assistant.name' /Users/openclaw/.openclaw/openclaw.json)" = "MODEL L3-37"
test "$(sudo jq -r '.ui.seamColor' /Users/openclaw/.openclaw/openclaw.json)" = "#00c88a"
sudo jq -r '.ui.assistant.avatar | select(startswith("data:image/png;base64,")) | sub("^data:image/png;base64,"; "")' /Users/openclaw/.openclaw/openclaw.json | /usr/bin/base64 -D | cmp - "$AGENTBOX_PAYLOAD_DIR/assets/default_avatar.png"

# should allow verified tailscale identities for openclaw gateway authentication
test "$(sudo jq -r '.gateway.auth.allowTailscale' /Users/openclaw/.openclaw/openclaw.json)" = "true"

# should configure the invoking admin openclaw app for the managed gateway
test "$(stat -f "%Su:%Sg:%Lp" "$HOME/.openclaw")" = "$(id -un):$(id -gn):700"
test "$(stat -f "%Su:%Sg:%Lp" "$HOME/.openclaw/disable-launchagent")" = "$(id -un):$(id -gn):600"
test "$(stat -f "%Su:%Sg:%Lp" "$HOME/.openclaw/openclaw.json")" = "$(id -un):$(id -gn):600"
test "$(openclaw config get gateway.mode)" = "local"
test "$(openclaw config get gateway.port)" = "18888"
test "$(openclaw config get gateway.auth.mode)" = "token"
test "$(sudo jq -ce '.gateway.auth.token' /Users/openclaw/.openclaw/openclaw.json | /usr/bin/shasum -a 256 | awk '{print $1}')" = "$(jq -ce '.gateway.auth.token' "$HOME/.openclaw/openclaw.json" | /usr/bin/shasum -a 256 | awk '{print $1}')"

# should remove an invoking-admin gateway and stage only the runtime finalizer
test ! -e "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
if launchctl print "gui/$UID/ai.openclaw.gateway" >/dev/null 2>&1; then exit 1; fi
sudo test -f /Users/openclaw/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist

# should verify openclaw app token synchronization without logging token material
grep -F "verified openclaw app gateway token synchronization" "$TMPDIR/openclaw.log"
grep -F "by sha256 equality" "$TMPDIR/openclaw.log"

# should not print the openai api key
! grep -F -- "$OPENAI_API_KEY" "$TMPDIR/openclaw.log"

# should mask the openclaw runner password in debug output
grep -F "AGENTBOX_OPENCLAW_PASSWORD=provided" "$TMPDIR/openclaw.log"
! grep -F "OpenClawGatewayPass1!" "$TMPDIR/openclaw.log"

# should run openclaw onboarding non-interactively in CI
grep -F -- "--non-interactive" "$TMPDIR/openclaw.log"
grep -F -- "--accept-risk" "$TMPDIR/openclaw.log"
grep -F -- "--json" "$TMPDIR/openclaw.log"
grep -F -- "--no-install-daemon" "$TMPDIR/openclaw.log"
grep -F -- "--skip-health" "$TMPDIR/openclaw.log"

# should print the detailed health report in debug mode
grep -F "debug agentbox health report" "$TMPDIR/openclaw.log"
grep -F "openclaw_gateway_state=pending_first_login" "$TMPDIR/openclaw.log"

# should print the concise health success status
grep -F "agentbox setup succeeded" "$TMPDIR/openclaw.log"
! grep -F "agentbox post-bootstrap summary" "$TMPDIR/openclaw.log"

# should render the Aqua-only finalizer without provider secrets
sudo /usr/libexec/PlistBuddy -c "Print :LimitLoadToSessionType" /Users/openclaw/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist | grep -Fx Aqua
sudo /usr/libexec/PlistBuddy -c "Print :RunAtLoad" /Users/openclaw/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist | grep -Fx true
! sudo grep -F "OPENAI_API_KEY" /Users/openclaw/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist

# should report the openclaw gateway tailscale prerequisites while its route is pending
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_magicdns_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_magicdns_resolver_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_https_certificates_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_serve_route_ok=0"

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

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_backend_state=Running"

# should keep strict health pending until the runtime user logs in
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=0"
if sudo /opt/tanaab/agentbox/bin/health.sh --check; then exit 1; fi
```
