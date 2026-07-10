# Defaults Example

This example runs the real `agentbox` setup with default agentbox-owned settings, then verifies the
resulting GitHub-hosted macOS runner state. It is intended for CI by default because it mutates
system settings, Homebrew state, SSH, launchd, OpenClaw, and Tailscale.

The example passes a unique hostname because Tailscale hostnames register outside the ephemeral VM
and can collide across PR runs. Other OpenClaw, Homebrew, and service-mode settings stay on
defaults.

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
  --openclaw-password "DefaultOpenClawPass1!" \
  2>&1 | tee "$TMPDIR/defaults.log"
```

## Testing

```bash
# should print only the concise health success status without debug mode
grep -F "agentbox setup succeeded" "$TMPDIR/defaults.log"
! grep -F "agentbox_ok=" "$TMPDIR/defaults.log"
! grep -F "debug agentbox health report" "$TMPDIR/defaults.log"

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

# should use default system openclaw service mode
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_service_mode=system"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"
sudo test ! -e /Users/openclaw/Library/LaunchAgents/ai.openclaw.gateway.plist

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

# should report homebrew prefix health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix=$(brew --prefix)"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_rwx_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_ok=1"
test "$(sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup)" = "brewer"

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

# should report default openclaw gateway health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_auth_choice=skip"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_service_mode=system"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=serve"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_port=18789"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_launchd_running_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_log_permissions_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_status_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_ok=1"

# should render the managed openclaw gateway service environment
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/bin/sh"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:1" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway-env-wrapper.sh"
sudo /usr/libexec/PlistBuddy -c "Print :ProgramArguments:2" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -Fx "/Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env"
sudo /usr/libexec/PlistBuddy -c "Print :AgentboxVersion" /Library/LaunchDaemons/dev.tanaab.agentbox.openclaw-gateway.plist | grep -E '^.+$'
sudo stat -f "%Su:%Sg:%Lp" /Users/openclaw/.openclaw/service-env | tee /dev/stderr | grep -Fx "openclaw:$(id -gn openclaw):700"
sudo stat -f "%Su:%Sg:%Lp" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env | tee /dev/stderr | grep -Fx "openclaw:$(id -gn openclaw):600"
sudo stat -f "%Su:%Sg:%Lp" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway-env-wrapper.sh | tee /dev/stderr | grep -Fx "openclaw:$(id -gn openclaw):700"
sudo grep -F "generated by agentbox. do not edit" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export HOME='/Users/openclaw'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export USER='openclaw'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export LOGNAME='openclaw'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export PATH='$(brew --prefix)/bin:$(brew --prefix)/sbin:/usr/bin:/bin:/usr/sbin:/sbin'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export TMPDIR='/Users/openclaw/.openclaw/tmp'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export NODE_EXTRA_CA_CERTS='/etc/ssl/cert.pem'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export NODE_USE_SYSTEM_CA='1'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_STATE_DIR='/Users/openclaw/.openclaw'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_MDNS_HOSTNAME='TANAABAGENTBOX-DEF$GITHUB_RUN_ID'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_GATEWAY_PORT='18789'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_LAUNCHD_LABEL='dev.tanaab.agentbox.openclaw-gateway'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_SERVICE_MARKER='openclaw'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export OPENCLAW_SERVICE_KIND='gateway'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -E "^export OPENCLAW_SERVICE_VERSION='[^']+'$" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo stat -f "%Su:%Sg:%Lp" /Users/openclaw/.openclaw/tmp | tee /dev/stderr | grep -Fx "openclaw:$(id -gn openclaw):700"

# should render the managed openclaw gateway agentbox metadata
sudo grep -F "export AGENTBOX_MANAGED='1'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export AGENTBOX_SERVICE_KIND='openclaw-gateway'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -F "export AGENTBOX_HEALTH_COMMAND='/opt/tanaab/agentbox/bin/health.sh --report'" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env
sudo grep -E "^export AGENTBOX_VERSION='[^']+'$" /Users/openclaw/.openclaw/service-env/dev.tanaab.agentbox.openclaw-gateway.env

# should keep private openclaw gateway logs owned by the runner
sudo stat -f "%Su:%Sg:%Lp" /var/log/tanaab/agentbox | tee /dev/stderr | grep -Fx "root:wheel:755"
sudo stat -f "%Su:%Sg:%Lp" /var/log/tanaab/agentbox/openclaw-gateway.stdout.log | tee /dev/stderr | grep -Fx "openclaw:$(id -gn openclaw):600"
sudo stat -f "%Su:%Sg:%Lp" /var/log/tanaab/agentbox/openclaw-gateway.stderr.log | tee /dev/stderr | grep -Fx "openclaw:$(id -gn openclaw):600"

# should restart the default openclaw gateway from its final filesystem state
sudo launchctl kickstart -k system/dev.tanaab.agentbox.openclaw-gateway
curl \
  --fail \
  --silent \
  --show-error \
  --ipv4 \
  --connect-timeout 10 \
  --max-time 90 \
  --retry 30 \
  --retry-all-errors \
  --retry-delay 2 \
  --retry-max-time 90 \
  "http://127.0.0.1:18789/readyz" | tee /dev/stderr

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_running_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_user_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_official_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_state_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=1"

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

# should report the openclaw gateway tailscale serve route
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_serve_route_ok=1"

# should report the openclaw gateway tailscale serve metadata
set -o pipefail
tailscale_bin="$(brew --prefix tailscale)/bin/tailscale"
sudo "$tailscale_bin" serve status --json | tee /dev/stderr | jq -e --arg port "18789" '
  (.TCP["443"].HTTPS == true)
  and any((.Web // {}) | to_entries[]?;
    (.key | endswith(":443"))
    and ((.value.Handlers["/"].Proxy // "")
      | test("^https?://(127[.]0[.]0[.]1|localhost|\\[::1\\]):" + $port + "$"))
  )
'

# should report launchd health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "health_launchd_loaded_ok=1"
sudo /usr/libexec/PlistBuddy -c "Print :AgentboxVersion" /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist | grep -E '^.+$'

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
