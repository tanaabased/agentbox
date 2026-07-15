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

# should preserve an openclaw log marker while repairing root-owned gateway logs
sudo -u rita /bin/sh -c 'printf "%s\n" "agentbox-rerun-log-marker" >> /var/log/tanaab/agentbox/openclaw-gateway.stdout.log'
sudo chown root:wheel /var/log/tanaab/agentbox/openclaw-gateway.stdout.log /var/log/tanaab/agentbox/openclaw-gateway.stderr.log
sudo chmod 600 /var/log/tanaab/agentbox/openclaw-gateway.stdout.log /var/log/tanaab/agentbox/openclaw-gateway.stderr.log

# should register stale invoking admin openclaw app state before rerun
mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/plutil -create xml1 "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
/usr/bin/plutil -insert Label -string ai.openclaw.gateway "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
/usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/true"]' "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
launchctl print "gui/$UID/ai.openclaw.gateway" >/dev/null
openclaw config set gateway.port 19999 --strict-json
openclaw config set gateway.auth.token stale-agentbox-app-token

# should stop the existing tailscale identity before rerun
sudo tailscale down
sudo tailscale status --json | tee /dev/stderr | jq -e '.BackendState == "Stopped"'

# should rerun agentbox successfully without a tailscale auth key
set -o pipefail
AGENTBOX_TAILSCALE_AUTHKEY="" agentbox \
  --debug \
  --force \
  --hostname "TANAABAGENTBOX-RERUN$GITHUB_RUN_ID" \
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
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_launchd_running_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_log_permissions_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_ok=1"
sudo stat -f "%Su:%Sg:%Lp" /var/log/tanaab/agentbox | tee /dev/stderr | grep -Fx "root:wheel:755"
sudo stat -f "%Su:%Sg:%Lp" /var/log/tanaab/agentbox/openclaw-gateway.stdout.log | tee /dev/stderr | grep -Fx "rita:$(id -gn rita):600"
sudo stat -f "%Su:%Sg:%Lp" /var/log/tanaab/agentbox/openclaw-gateway.stderr.log | tee /dev/stderr | grep -Fx "rita:$(id -gn rita):600"
sudo grep -Fx "agentbox-rerun-log-marker" /var/log/tanaab/agentbox/openclaw-gateway.stdout.log

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_running_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_official_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_state_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_backend_state=Running"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=1"
sudo test ! -e /Library/LaunchDaemons/com.tailscale.tailscaled.plist
if sudo launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then exit 1; fi

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
