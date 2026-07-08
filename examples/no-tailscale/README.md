# No Tailscale Example

This example runs the real `boot.sh` setup with Tailscale setup disabled, then verifies the
resulting GitHub-hosted macOS runner state. It is intended for CI by default because it mutates
system settings, Homebrew state, SSH, and launchd.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should generate a public key fixture for authorized-key installation
mkdir -p "$TMPDIR"
rm -f "$TMPDIR/id_agentbox_no_tailscale" "$TMPDIR/id_agentbox_no_tailscale.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-no-tailscale@example.test" -f "$TMPDIR/id_agentbox_no_tailscale" >/dev/null

# should prepare extra brewfile fixtures
printf 'brew "hello"\n' > "$TMPDIR/Brewfile.extra-local"
printf 'brew "tree"\n' > "$TMPDIR/Brewfile.extra-url"

# should run boot.sh successfully with tailscale setup disabled
boot.sh \
  --force \
  --debug \
  --hostname "TANAABAGENTBOX-NOTAILSCALE" \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --brewfile "$TMPDIR/Brewfile.extra-local" \
  --brewfile "file://$TMPDIR/Brewfile.extra-url" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-password "NoTailscaleOpenClawPass1!" \
  --skip-openclaw-autologin \
  --authorized-key "file:$TMPDIR/id_agentbox_no_tailscale.pub"
```

## Testing

```bash
# should install homebrew
command -v brew >/dev/null

# should install base required commands
command -v git >/dev/null
command -v jq >/dev/null

# should install the tailscale formula
test -x "$(brew --prefix)/bin/tailscale"

# should materialize agentbox from the local workflow checkout
test -d "$HOME/tanaab/agentbox/.git"
test -f "$HOME/tanaab/agentbox/boot.sh"
test "$(git -C "$HOME/tanaab/agentbox" config --get remote.origin.url)" = "$GITHUB_WORKSPACE"

# should satisfy the agentbox brewfile
brew bundle check --file "$HOME/tanaab/agentbox/Brewfile" --no-upgrade

# should satisfy the extra brewfiles
brew bundle check --file "$TMPDIR/Brewfile.extra-local" --no-upgrade
brew bundle check --file "$TMPDIR/Brewfile.extra-url" --no-upgrade
command -v hello >/dev/null
command -v tree >/dev/null

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

# should create the openclaw runner account
id -u openclaw >/dev/null
dscl . -read /Users/openclaw RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "A Tanaab-based Claw"
test -d /Users/openclaw
test "$(stat -f "%Su" /Users/openclaw)" = "openclaw"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should keep openclaw runner autologin skipped
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"

# should install the authorized key for the admin user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_no_tailscale.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should install the authorized key for the openclaw runner user
sudo test -f /Users/openclaw/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_no_tailscale.pub")" /Users/openclaw/.ssh/authorized_keys
test "$(sudo stat -f "%Lp" /Users/openclaw/.ssh)" = "700"
test "$(sudo stat -f "%Lp" /Users/openclaw/.ssh/authorized_keys)" = "600"

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-NOTAILSCALE"

# should report macOS identity health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "macos_identity_ok=1"

# should report ssh hardening for allowed users
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_hardening_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_allowed_users=$(id -un) openclaw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group=com.apple.access_ssh"
if sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group_exists_ok=1"; then
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=1"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=1"
else
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=skipped"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=skipped"
fi

# should report disabled brewgroup state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_enabled=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_expected=off"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_admin_user_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_openclaw_user_ok=skipped"

# should report disabled trusted brewgroup state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_enabled=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_expected=off"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_nested_ok=skipped"

# should report skipped homebrew prefix health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_rwx_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_ok=skipped"
test "$(sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup)" = "off"

# should report homebrew command health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "homebrew_login_path_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_cli_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "node_cli_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ripgrep_ok=1"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=openclaw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=A Tanaab-based Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report skipped tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_launchd_absent_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_user_launchd_absent_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=skipped"

# should report launchd health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "health_launchd_loaded_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check

# should allow admin ssh login with the generated private key
ssh \
  -F /dev/null \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=VERBOSE \
  -i "$TMPDIR/id_agentbox_no_tailscale" \
  "$(id -un)@localhost" true

# should allow openclaw ssh login with the generated private key
ssh \
  -F /dev/null \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=VERBOSE \
  -i "$TMPDIR/id_agentbox_no_tailscale" \
  "openclaw@localhost" true

# should keep tailscaled stopped
if pgrep -x tailscaled >/dev/null; then exit 1; fi

# should keep tailscale unjoined
if tailscale status --json 2>/dev/null | jq -e '((.Self.HostName // "") != "") or (((.Self.TailscaleIPs // []) | length) > 0)'; then exit 1; fi
if tailscale ip -4 2>/dev/null | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"; then exit 1; fi
```
