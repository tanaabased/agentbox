# Rerun Example

This example verifies that a Tailscale-joined agentbox host can run `agentbox` again without a
Tailscale auth key. It is intended for CI by default because it mutates system settings, Homebrew
state, SSH, launchd, OpenClaw, and Tailscale.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should have a tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should run agentbox successfully with a tailscale auth key
agentbox \
  --force \
  --hostname "TANAABAGENTBOX-RERUN$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --openclaw-autologin off \
  --openclaw-identity "Rita Rerun Claw <rita>" \
  --openclaw-password "RitaRerunClawPass1!" \
  --openclaw-auth-choice skip \
  --openclaw-gateway-port 18789

# should register a conflicting official tailscale launchd job before rerun
sudo /usr/bin/plutil -create xml1 /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo /usr/bin/plutil -insert Label -string com.tailscale.tailscaled /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo /usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/true"]' /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo chown root:wheel /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo chmod 644 /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo launchctl print system/com.tailscale.tailscaled >/dev/null

# should seed the runtime native Gateway service environment before rerun
sudo mkdir -p /Users/rita/.openclaw/service-env
printf '%s\n' "export NATIVE_GATEWAY_VALUE='preserve-me'" | sudo tee /Users/rita/.openclaw/service-env/ai.openclaw.gateway.env >/dev/null
printf '%s\n' '#!/bin/sh' '# native-preserve-me' 'exit 0' | sudo tee /Users/rita/.openclaw/service-env/ai.openclaw.gateway-env-wrapper.sh >/dev/null
sudo chmod 600 /Users/rita/.openclaw/service-env/ai.openclaw.gateway.env
sudo chmod 700 /Users/rita/.openclaw/service-env/ai.openclaw.gateway-env-wrapper.sh

# should seed stale managed values beside an unrelated runtime environment value
printf '%s\n' 'PROVIDER_FIXTURE="keep-me"' 'OPENCLAW_MDNS_HOSTNAME="stale"' 'AGENTBOX_MANAGED="0"' 'AGENTBOX_SERVICE_KIND="stale"' | sudo tee /Users/rita/.openclaw/.env >/dev/null
sudo chown "rita:$(id -gn rita)" /Users/rita/.openclaw/.env
sudo chmod 600 /Users/rita/.openclaw/.env

# should register stale invoking admin openclaw app state before rerun
mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/plutil -create xml1 "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
/usr/bin/plutil -insert Label -string ai.openclaw.gateway "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
/usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/true"]' "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
launchctl print "gui/$UID/ai.openclaw.gateway" >/dev/null
openclaw config set gateway.port 19999 --strict-json
openclaw config set gateway.auth.token stale-agentbox-app-token
mkdir -p "$HOME/.openclaw/service-env"
printf '%s\n' "export ADMIN_NATIVE_GATEWAY_VALUE='remove-me'" > "$HOME/.openclaw/service-env/ai.openclaw.gateway.env"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$HOME/.openclaw/service-env/ai.openclaw.gateway-env-wrapper.sh"
chmod 600 "$HOME/.openclaw/service-env/ai.openclaw.gateway.env"
chmod 700 "$HOME/.openclaw/service-env/ai.openclaw.gateway-env-wrapper.sh"

# should register stale openclaw gateway tailscale authentication state before rerun
sudo -u rita env HOME=/Users/rita OPENCLAW_STATE_DIR=/Users/rita/.openclaw "$(brew --prefix)/bin/openclaw" config set gateway.auth.allowTailscale false --strict-json

# should stop the existing tailscale identity before rerun
sudo tailscale down
sudo tailscale status --json | tee /dev/stderr | jq -e '.BackendState == "Stopped"'

# should rerun agentbox successfully without a tailscale auth key
set -o pipefail
AGENTBOX_TAILSCALE_AUTHKEY="" agentbox \
  --debug \
  --force \
  --hostname "TANAABAGENTBOX-RERUN$GITHUB_RUN_ID" \
  --openclaw-autologin off \
  --openclaw-identity "Rita Rerun Claw <rita>" \
  --openclaw-password "RitaRerunClawPass1!" \
  --openclaw-auth-choice skip \
  --openclaw-gateway-port 18789 \
  2>&1 | tee "$TMPDIR/rerun.log"
```

## Testing

```bash
# should reconcile existing openclaw gateway configuration non-interactively
grep -F "reconciling existing openclaw gateway configuration non-interactively" "$TMPDIR/rerun.log"
grep -F -- "--non-interactive" "$TMPDIR/rerun.log"
grep -F -- "--accept-risk" "$TMPDIR/rerun.log"
grep -F -- "--json" "$TMPDIR/rerun.log"

# should keep the openclaw runner account
id -u rita >/dev/null
dscl . -read /Users/rita RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "Rita Rerun Claw"
test -d /Users/rita
test "$(stat -f "%Su" /Users/rita)" = "rita"

# should restore permanent openclaw fallback gateway branding on rerun
test "$(sudo jq -r '.ui.assistant.name' /Users/rita/.openclaw/openclaw.json)" = "MODEL L3-37"
test "$(sudo jq -r '.ui.seamColor' /Users/rita/.openclaw/openclaw.json)" = "#00c88a"
sudo jq -r '.ui.assistant.avatar | select(startswith("data:image/png;base64,")) | sub("^data:image/png;base64,"; "")' /Users/rita/.openclaw/openclaw.json | /usr/bin/base64 -D | cmp - "$AGENTBOX_PAYLOAD_DIR/assets/default_avatar.png"

# should restore openclaw gateway tailscale identity authentication on rerun
test "$(sudo jq -r '.gateway.auth.allowTailscale' /Users/rita/.openclaw/openclaw.json)" = "true"

# should repair the invoking admin openclaw app configuration on rerun
test "$(stat -f "%Su:%Sg:%Lp" "$HOME/.openclaw")" = "$(id -un):$(id -gn):700"
test "$(stat -f "%Su:%Sg:%Lp" "$HOME/.openclaw/disable-launchagent")" = "$(id -un):$(id -gn):600"
test "$(stat -f "%Su:%Sg:%Lp" "$HOME/.openclaw/openclaw.json")" = "$(id -un):$(id -gn):600"
test "$(openclaw config get gateway.mode)" = "local"
test "$(openclaw config get gateway.port)" = "18789"
test "$(openclaw config get gateway.auth.mode)" = "token"
test "$(sudo jq -ce '.gateway.auth.token' /Users/rita/.openclaw/openclaw.json | /usr/bin/shasum -a 256 | awk '{print $1}')" = "$(jq -ce '.gateway.auth.token' "$HOME/.openclaw/openclaw.json" | /usr/bin/shasum -a 256 | awk '{print $1}')"

# should remove the stale invoking admin openclaw launch agent on rerun
test ! -e "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
if launchctl print "gui/$UID/ai.openclaw.gateway" >/dev/null 2>&1; then exit 1; fi
test ! -e "$HOME/.openclaw/service-env/ai.openclaw.gateway.env"
test ! -e "$HOME/.openclaw/service-env/ai.openclaw.gateway-env-wrapper.sh"
find "$HOME" -maxdepth 1 -type d -name '.openclaw.agentbox-backup-*' | grep -F .openclaw.agentbox-backup-

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-RERUN$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_tailscale_hostname=AGENTBOX-RERUN$GITHUB_RUN_ID"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=rita"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Rita Rerun Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report reconciled Gateway configuration pending the next runtime-user login
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=serve"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_port=18789"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_duplicate_admin_gateway_detected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_admin_app_attach_only_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_admin_app_gateway_config_expected=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_admin_app_gateway_config_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_auth_ok=1"
sudo grep -Fx "export NATIVE_GATEWAY_VALUE='preserve-me'" /Users/rita/.openclaw/service-env/ai.openclaw.gateway.env
sudo grep -Fx '# native-preserve-me' /Users/rita/.openclaw/service-env/ai.openclaw.gateway-env-wrapper.sh

# should stage the reconciled gateway as agentbox-managed
test "$(sudo stat -f "%Su:%Sg:%Lp" /Users/rita/.openclaw/.env)" = "rita:$(id -gn rita):600"
sudo grep -Fx 'PROVIDER_FIXTURE="keep-me"' /Users/rita/.openclaw/.env
sudo grep -Fx "OPENCLAW_MDNS_HOSTNAME=\"TANAABAGENTBOX-RERUN$GITHUB_RUN_ID\"" /Users/rita/.openclaw/.env
sudo grep -Fx 'AGENTBOX_MANAGED="1"' /Users/rita/.openclaw/.env
sudo grep -Fx 'AGENTBOX_SERVICE_KIND="openclaw-gateway"' /Users/rita/.openclaw/.env
test "$(sudo grep -c '^OPENCLAW_MDNS_HOSTNAME=' /Users/rita/.openclaw/.env)" -eq 1
test "$(sudo grep -c '^AGENTBOX_MANAGED=' /Users/rita/.openclaw/.env)" -eq 1
! grep -F 'PROVIDER_FIXTURE="keep-me"' "$TMPDIR/rerun.log"
test "$(sudo stat -f "%Su:%Sg:%Lp" /Users/rita/Library/Logs/openclaw/gateway.log)" = "rita:$(id -gn rita):600"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_agentbox_managed=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_mdns_hostname_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_agent_environment_ok=1"

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_running_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_official_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_state_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_backend_state=Running"
sudo test ! -e /Library/LaunchDaemons/com.tailscale.tailscaled.plist
if sudo launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then exit 1; fi

# should keep strict health pending until the runtime user logs in
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=0"
if sudo /opt/tanaab/agentbox/bin/health.sh --check; then exit 1; fi
```
