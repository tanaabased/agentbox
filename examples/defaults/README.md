# Defaults Example

This example runs the real `agentbox` setup with default agentbox-owned settings, then verifies the
resulting GitHub-hosted macOS runner state. It is intended for CI by default because it mutates
system settings, Homebrew state, SSH, launchd, OpenClaw, and Tailscale.

The example passes a unique hostname because Tailscale hostnames register outside the ephemeral VM
and can collide across PR runs. Other OpenClaw and Homebrew settings stay on defaults, except for the
CI-safe autologin opt-out.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should have a tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should run agentbox successfully
set -o pipefail
agentbox \
  --force \
  --hostname "TANAABAGENTBOX-DEF$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --openclaw-autologin off \
  --openclaw-password "DefaultOpenClawPass1!" \
  2>&1 | tee "$TMPDIR/defaults.log"
```

## Testing

```bash
# should print only the concise health success status without debug mode
grep -F "agentbox setup succeeded" "$TMPDIR/defaults.log"
! grep -F "agentbox_ok=" "$TMPDIR/defaults.log"
! grep -F "debug agentbox health report" "$TMPDIR/defaults.log"

# should print the runner graphical session dashboard command
grep -F "open the openclaw dashboard from the openclaw graphical session:" "$TMPDIR/defaults.log"
grep -Fx "  openclaw dashboard" "$TMPDIR/defaults.log"

# should install homebrew
command -v brew >/dev/null

# should install base required commands
command -v git >/dev/null
command -v jq >/dev/null

# should install tailscale
test -x "$(brew --prefix)/bin/tailscale"

# should use the workflow payload
test "$AGENTBOX_PAYLOAD_DIR" = "$GITHUB_WORKSPACE"
test -f "$AGENTBOX_PAYLOAD_DIR/macos.sh"

# should report homebrew prefix health after agentbox reconciliation
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix=$(brew --prefix)"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_rwx_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_recursive_access_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -Fx "brew_prefix_recursive_drift_path="
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -Fx "brew_prefix_recursive_drift_reason="
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_ok=1"
test "$(sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup)" = "brewer"

# should satisfy the agentbox brewfile
brew bundle check --file "$AGENTBOX_PAYLOAD_DIR/Brewfile" --no-upgrade

# should install openclaw cli through homebrew
test -x "$(brew --prefix)/bin/openclaw"

# should install node through homebrew
test -x "$(brew --prefix)/bin/node"

# should install ripgrep through homebrew
test -x "$(brew --prefix)/bin/rg"

# should write homebrew login shell PATH entries
grep -Fx "$(brew --prefix)/bin" /etc/paths.d/00-agentbox-homebrew
grep -Fx "$(brew --prefix)/sbin" /etc/paths.d/00-agentbox-homebrew

# should expose homebrew commands in bash login shells
env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" /bin/bash -lc 'command -v openclaw' | grep -Fx "$(brew --prefix)/bin/openclaw"
env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" /bin/bash -lc 'command -v node' | grep -Fx "$(brew --prefix)/bin/node"
env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" /bin/bash -lc 'command -v rg' | grep -Fx "$(brew --prefix)/bin/rg"

# should create the default openclaw runner account
id -u openclaw >/dev/null
dscl . -read /Users/openclaw RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "A Tanaab-based Claw"
test -d /Users/openclaw
test "$(stat -f "%Su" /Users/openclaw)" = "openclaw"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should configure Main and the global UI fallback with the managed identity
sudo jq -e '[.agents.list[] | select(.default == true)] | length == 1 and .[0].id == "main"' /Users/openclaw/.openclaw/openclaw.json
test "$(sudo jq -r '.agents.list[] | select(.id == "main") | .identity.name' /Users/openclaw/.openclaw/openclaw.json)" = "MODEL L3-37"
test "$(sudo jq -r '.ui.assistant.name' /Users/openclaw/.openclaw/openclaw.json)" = "MODEL L3-37"
sudo jq -r '.agents.list[] | select(.id == "main") | .identity.avatar | sub("^data:image/png;base64,"; "")' /Users/openclaw/.openclaw/openclaw.json | /usr/bin/base64 -D | cmp - "$AGENTBOX_PAYLOAD_DIR/assets/default_avatar.png"
sudo jq -r '.ui.assistant.avatar | sub("^data:image/png;base64,"; "")' /Users/openclaw/.openclaw/openclaw.json | /usr/bin/base64 -D | cmp - "$AGENTBOX_PAYLOAD_DIR/assets/default_avatar.png"

# should install the inert managed Main workspace and ownership records
test "$(sudo jq -r '.agents.list[] | select(.id == "main") | .workspace' /Users/openclaw/.openclaw/openclaw.json)" = "/Users/openclaw/.openclaw/workspace-agentbox-main"
sudo jq -e '.agents.list[] | select(.id == "main") | (.tools == {allow: ["agents_list"]}) and (.subagents == {allowAgents: ["*"]})' /Users/openclaw/.openclaw/openclaw.json
sudo jq -e '.owner == "@tanaab/agentbox" and .agentId == "main"' /Users/openclaw/.openclaw/workspace-agentbox-main/.agentbox-managed.json
sudo jq -e '.owner == "@tanaab/agentbox" and .agentId == "main" and (.managedFileSha256["SOUL.md"] | length == 64)' /var/db/tanaab/agentbox/openclaw-main.json
sudo grep -F "Do not perform the user's requested work" /Users/openclaw/.openclaw/workspace-agentbox-main/SOUL.md

# should report managed Main health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_default_agent=main"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_default_agent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_main_workspace_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_main_routing_policy_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_main_ownership_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_main_identity_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_ui_assistant_identity_ok=1"

# should use native user LaunchAgent mode without changing CI autologin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-DEF$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_tailscale_hostname=AGENTBOX-DEF$GITHUB_RUN_ID"

# should report the installed agentbox version
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -E '^agentbox_version=.+$'

# should report default brewgroup state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_expected=brewer"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_admin_user_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_openclaw_user_ok=1"

# should report disabled trusted brewgroup state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_enabled=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_expected=off"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_nested_ok=skipped"

# should report homebrew command health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "homebrew_login_path_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_cli_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "node_cli_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ripgrep_ok=1"

# should report macos identity health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "macos_identity_ok=1"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=openclaw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=A Tanaab-based Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_exists_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_home_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report staged first-login gateway activation
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_auth_choice=skip"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=serve"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_port=18789"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_finalizer_installed=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_finalizer_state=pending_first_login"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_finalizer_permissions_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_activation_ok=0"
sudo test -x /Users/openclaw/.local/libexec/agentbox-openclaw-finalize
sudo test -f /Users/openclaw/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist
sudo /usr/libexec/PlistBuddy -c "Print :LimitLoadToSessionType" /Users/openclaw/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist | grep -Fx Aqua

# should stage a private agentbox-managed gateway environment
test "$(sudo stat -f "%Su:%Sg:%Lp" /Users/openclaw/.openclaw/.env)" = "openclaw:$(id -gn openclaw):600"
sudo grep -Fx "OPENCLAW_MDNS_HOSTNAME=\"TANAABAGENTBOX-DEF$GITHUB_RUN_ID\"" /Users/openclaw/.openclaw/.env
sudo grep -Fx 'AGENTBOX_MANAGED="1"' /Users/openclaw/.openclaw/.env
sudo grep -Fx 'AGENTBOX_SERVICE_KIND="openclaw-gateway"' /Users/openclaw/.openclaw/.env
sudo grep -Fx 'AGENTBOX_HEALTH_COMMAND="/opt/tanaab/agentbox/bin/health.sh --report"' /Users/openclaw/.openclaw/.env
test "$(sudo stat -f "%Su:%Sg:%Lp" /Users/openclaw/Library/Logs/openclaw/gateway.log)" = "openclaw:$(id -gn openclaw):600"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_agentbox_managed=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_mdns_hostname_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_agent_environment_ok=1"

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_running_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_user_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_official_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_state_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_backend_state=Running"

# should render the tailscaled launchd daemon state directory
sudo /usr/libexec/PlistBuddy -c "Print :AgentboxVersion" /Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist | grep -E '^.+$'
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:1" /Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist | grep -Fx -- "--statedir=/var/db/tanaab/agentbox/tailscale"
sudo test -d /var/db/tanaab/agentbox/tailscale
sudo test -s /var/db/tanaab/agentbox/tailscale/tailscaled.state
test "$(sudo stat -f "%Su:%Sg:%Lp" /var/db/tanaab/agentbox/tailscale)" = "root:wheel:700"

# should install the tailnet magicdns resolver
set -o pipefail
tailnet_suffix="$(tailscale status --json --peers=false | tee /dev/stderr | jq -r '.CurrentTailnet.MagicDNSSuffix // ""' | sed 's/[.]$//')"
test -n "$tailnet_suffix"
sudo test -f "/etc/resolver/$tailnet_suffix"
sudo grep -Fx "# Managed by agentbox." "/etc/resolver/$tailnet_suffix"
sudo grep -E '^[[:space:]]*nameserver[[:space:]]+100[.]100[.]100[.]100([[:space:]]|$)' "/etc/resolver/$tailnet_suffix"

# should resolve and ping the local tailscale magicdns name
set -o pipefail
gateway_dns_name="$(tailscale status --json --peers=false | tee /dev/stderr | jq -r '.Self.DNSName // ""' | sed 's/[.]$//')"
test -n "$gateway_dns_name"
dscacheutil -q host -a name "$gateway_dns_name" | tee /dev/stderr | grep -E '^[[:space:]]*ip_address:[[:space:]]+100[.]'
tailscale ping --c 1 --timeout 10s "$gateway_dns_name"
ping -c 1 -W 5000 "$gateway_dns_name"

# should report the openclaw runner as the tailscale operator
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_operator_user=openclaw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_operator_ok=1"

# should report tailscale serve prerequisites
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_magicdns_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_magicdns_resolver_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_https_certificates_enabled=1"

# should leave the gateway route pending with first-login activation
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_serve_route_ok=0"

# should report launchd health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "health_launchd_loaded_ok=1"
sudo /usr/libexec/PlistBuddy -c "Print :AgentboxVersion" /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist | grep -E '^.+$'

# should publish the latest health report for administrators without sudo
for attempt in $(seq 1 60); do
  if test -r /var/db/tanaab/agentbox/health-report; then break; fi
  sleep 2
done
test -r /var/db/tanaab/agentbox/health-report
test "$(stat -f "%Su:%Sg:%Lp" /var/db/tanaab/agentbox/health-report)" = "root:admin:640"
grep -E '^timestamp=.+$' /var/db/tanaab/agentbox/health-report
grep -E '^agentbox_version=.+$' /var/db/tanaab/agentbox/health-report
tail -n 1 /var/db/tanaab/agentbox/health-report | grep -E '^agentbox_ok=[01]$'
if sudo -u openclaw test -r /var/db/tanaab/agentbox/health-report; then exit 1; fi

# should manually publish tailscale health under the launchd path
before_report_inode="$(stat -f "%i" /var/db/tanaab/agentbox/health-report)"
sudo /usr/bin/env PATH=/usr/bin:/bin:/usr/sbin:/sbin /opt/tanaab/agentbox/bin/health.sh
after_report_inode="$(stat -f "%i" /var/db/tanaab/agentbox/health-report)"
test "$after_report_inode" != "$before_report_inode"
grep -Fx "tailscale_backend_state=Running" /var/db/tanaab/agentbox/health-report
grep -Fx "tailscale_operator_user=openclaw" /var/db/tanaab/agentbox/health-report
grep -Fx "tailscale_operator_ok=1" /var/db/tanaab/agentbox/health-report
grep -Fx "tailscale_magicdns_enabled=1" /var/db/tanaab/agentbox/health-report
grep -Fx "tailscale_magicdns_resolver_ok=1" /var/db/tanaab/agentbox/health-report
grep -Fx "tailscale_https_certificates_enabled=1" /var/db/tanaab/agentbox/health-report

# should diagnose pending first-login health from the published report without sudo
"$AGENTBOX_PAYLOAD_DIR/scripts/check-plugin-runtime.sh"
set +e
doctor_output="$(bun "$AGENTBOX_PAYLOAD_DIR/skills/agentbox-doctor/scripts/check-host.js")"
doctor_status="$?"
set -e
printf '%s\n' "$doctor_output"
test "$doctor_status" -eq 1
printf '%s\n' "$doctor_output" | jq -e '.status == "unhealthy" and .source.healthReport == "/var/db/tanaab/agentbox/health-report" and .source.healthAgeSeconds >= 0 and .source.healthAgeSeconds <= 900 and (.issues | any(.key == "openclaw_gateway_activation_ok"))'

# should keep strict health pending until the runtime user logs in
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=0"
if sudo /opt/tanaab/agentbox/bin/health.sh --check; then exit 1; fi
```
