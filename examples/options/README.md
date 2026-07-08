# Options Example

This example runs the real `boot.sh` setup using CLI options, then verifies the resulting
GitHub-hosted macOS runner state. It is intended for CI by default because it mutates system
settings, Homebrew state, SSH, launchd, and Tailscale.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should have a tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should generate public key fixtures for authorized-key installation
mkdir -p "$TMPDIR"
rm -f "$TMPDIR/id_agentbox_options_file" "$TMPDIR/id_agentbox_options_file.pub"
rm -f "$TMPDIR/id_agentbox_options_raw" "$TMPDIR/id_agentbox_options_raw.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-options-file@example.test" -f "$TMPDIR/id_agentbox_options_file" >/dev/null
ssh-keygen -t ed25519 -N "" -C "agentbox-options-raw@example.test" -f "$TMPDIR/id_agentbox_options_raw" >/dev/null

# should run boot.sh successfully
boot.sh \
  --force \
  --debug \
  --hostname "TANAABAGENTBOX-OPT$GITHUB_RUN_ID" \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --brewgroup "bobsbrewcrew:staff" \
  --openclaw-identity "Bob Options Claw <bob>" \
  --openclaw-password "BobOptionsClawPass1!" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --authorized-key "file:$TMPDIR/id_agentbox_options_file.pub" \
  --authorized-key "$(cat "$TMPDIR/id_agentbox_options_raw.pub")"

# should rerun successfully without a tailscale auth key when already joined
AGENTBOX_TAILSCALE_AUTHKEY="" boot.sh \
  --force \
  --debug \
  --hostname "TANAABAGENTBOX-OPT$GITHUB_RUN_ID" \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --brewgroup "bobsbrewcrew:staff" \
  --openclaw-identity "Bob Options Claw <bob>" \
  --openclaw-password "BobOptionsClawPass1!" \
  --authorized-key "file:$TMPDIR/id_agentbox_options_file.pub" \
  --authorized-key "$(cat "$TMPDIR/id_agentbox_options_raw.pub")"
```

## Testing

```bash
# should install homebrew
command -v brew >/dev/null

# should install base required commands
command -v git >/dev/null
command -v jq >/dev/null

# should install tailscale
test -x "$(brew --prefix)/bin/tailscale"

# should materialize agentbox from the local workflow checkout
test -d "$HOME/tanaab/agentbox/.git"
test -f "$HOME/tanaab/agentbox/boot.sh"
test "$(git -C "$HOME/tanaab/agentbox" config --get remote.origin.url)" = "$GITHUB_WORKSPACE"

# should satisfy the agentbox brewfile
brew bundle check --file "$HOME/tanaab/agentbox/Brewfile" --no-upgrade

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

# should create the brewgroup
dscl . -read "/Groups/bobsbrewcrew" >/dev/null

# should add bootstrap users to the brewgroup
dscl . -read "/Groups/bobsbrewcrew" GroupMembership | tr " " "\n" | grep -Fx "$(id -un)"
dscl . -read "/Groups/bobsbrewcrew" GroupMembership | tr " " "\n" | grep -Fx bob

# should make the homebrew prefix writable by the brewgroup
brew_prefix="$(brew --prefix)"
test "$(stat -f "%Sg" "$brew_prefix")" = "bobsbrewcrew"
brew_prefix_mode="$(stat -f "%Lp" "$brew_prefix")"
test "$((8#$brew_prefix_mode & 8#070))" = "$((8#070))"

# should give a future staff user inherited membership in the brewgroup
sudo dscl . -delete /Users/brewhelper >/dev/null 2>&1 || true
test_user_uid="$(dscl . -list /Users UniqueID | awk '$2 ~ /^[0-9]+$/ { used[$2] = 1 } END { for (uid = 701; uid < 1000; uid++) { if (!(uid in used)) { print uid; exit } } }')"
test -n "$test_user_uid"
sudo dscl . -create /Users/brewhelper
sudo dscl . -create /Users/brewhelper UserShell /usr/bin/false
sudo dscl . -create /Users/brewhelper RealName "Brew Helper"
sudo dscl . -create /Users/brewhelper UniqueID "$test_user_uid"
sudo dscl . -create /Users/brewhelper PrimaryGroupID 20
sudo dseditgroup -o checkmember -m brewhelper "bobsbrewcrew"

# should create the openclaw runner account
id -u bob >/dev/null
dscl . -read /Users/bob RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "Bob Options Claw"
test -d /Users/bob
test "$(stat -f "%Su" /Users/bob)" = "bob"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should configure openclaw runner autologin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_user=bob"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=1"

# should install both authorized keys for the admin user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_options_file.pub")" "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_options_raw.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should install both authorized keys for the openclaw runner user
sudo test -f /Users/bob/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_options_file.pub")" /Users/bob/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_options_raw.pub")" /Users/bob/.ssh/authorized_keys
test "$(sudo stat -f "%Lp" /Users/bob/.ssh)" = "700"
test "$(sudo stat -f "%Lp" /Users/bob/.ssh/authorized_keys)" = "600"

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-OPT$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_tailscale_hostname=AGENTBOX-OPT$GITHUB_RUN_ID"

# should report brewgroup state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_expected=bobsbrewcrew"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_admin_user_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_openclaw_user_ok=1"

# should report trusted brewgroup health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_expected=staff"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_nested_ok=1"

# should report homebrew prefix health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix=$(brew --prefix)"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_rwx_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_ok=1"
test "$(sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup)" = "bobsbrewcrew"

# should report homebrew command health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "homebrew_login_path_file_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_cli_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "node_cli_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ripgrep_ok=1"

# should report macOS identity health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "macos_identity_ok=1"

# should report ssh hardening for allowed users
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_allowed_users=$(id -un) bob"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group=com.apple.access_ssh"
if sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group_exists_ok=1"; then
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=1"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=1"
else
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=skipped"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=skipped"
fi
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_hardening_ok=1"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=bob"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Bob Options Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_exists_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_home_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_user_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=1"

# should report launchd health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "health_launchd_loaded_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check

# should allow admin ssh login with the file private key
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
  -i "$TMPDIR/id_agentbox_options_file" \
  "$(id -un)@localhost" true

# should allow admin ssh login with the raw private key
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
  -i "$TMPDIR/id_agentbox_options_raw" \
  "$(id -un)@localhost" true

# should allow openclaw ssh login with the file private key
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
  -i "$TMPDIR/id_agentbox_options_file" \
  bob@localhost true

```
