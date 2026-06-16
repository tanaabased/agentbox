# Options Example

This example runs the real `boot.sh` setup using CLI options, then verifies the resulting
GitHub-hosted macOS runner state. It is intended for CI by default because it mutates system
settings, Homebrew state, SSH, launchd, and Tailscale.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a Tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should prepare a clean agentbox target and runner state
../../scripts/cleanup-agentbox-runner.sh
mkdir -p "$TMPDIR"

# should fail without a Tailscale auth key before the first join
if AGENTBOX_TAILSCALE_AUTHKEY="" boot.sh \
  --force \
  --brewgroup off \
  --hostname "TANAABAGENTBOX-TEST$GITHUB_RUN_ID"; then
  exit 1
fi

# should generate public key fixtures for option authorized-key installation
rm -f "$TMPDIR/id_agentbox_options_file" "$TMPDIR/id_agentbox_options_file.pub"
rm -f "$TMPDIR/id_agentbox_options_raw" "$TMPDIR/id_agentbox_options_raw.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-options-file@example.test" -f "$TMPDIR/id_agentbox_options_file" >/dev/null
ssh-keygen -t ed25519 -N "" -C "agentbox-options-raw@example.test" -f "$TMPDIR/id_agentbox_options_raw" >/dev/null

# should run boot.sh successfully using options
boot.sh \
  --force \
  --debug \
  --hostname "TANAABAGENTBOX-TEST$GITHUB_RUN_ID" \
  --brewgroup "agentboxbrewopt$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --authorized-key "file:$TMPDIR/id_agentbox_options_file.pub" \
  --authorized-key "$(cat "$TMPDIR/id_agentbox_options_raw.pub")"
test -f "$HOME/tanaab/agentbox/Brewfile"
command -v tailscale >/dev/null

# should rerun successfully without a Tailscale auth key when already joined
AGENTBOX_TAILSCALE_AUTHKEY="" boot.sh \
  --force \
  --debug \
  --hostname "TANAABAGENTBOX-TEST$GITHUB_RUN_ID" \
  --brewgroup "agentboxbrewopt$GITHUB_RUN_ID" \
  --authorized-key "file:$TMPDIR/id_agentbox_options_file.pub" \
  --authorized-key "$(cat "$TMPDIR/id_agentbox_options_raw.pub")"
```

## Testing

```bash
# should install homebrew and required commands
command -v brew >/dev/null
command -v git >/dev/null
command -v jq >/dev/null
command -v tailscale >/dev/null

# should materialize agentbox from the public HTTPS default branch
test -d "$HOME/tanaab/agentbox/.git"
test -f "$HOME/tanaab/agentbox/boot.sh"
test -f "$HOME/tanaab/agentbox/Brewfile"
test "$(git -C "$HOME/tanaab/agentbox" config --get remote.origin.url)" = "https://github.com/tanaabased/agentbox.git"

# should satisfy the agentbox Brewfile
brew bundle check --file "$HOME/tanaab/agentbox/Brewfile" --no-upgrade

# should make the Homebrew prefix writable by the configured brewgroup
dscl . -read "/Groups/agentboxbrewopt$GITHUB_RUN_ID" >/dev/null
brew_prefix="$(brew --prefix)"
test "$(stat -f "%Sg" "$brew_prefix")" = "agentboxbrewopt$GITHUB_RUN_ID"
brew_prefix_mode="$(stat -f "%Lp" "$brew_prefix")"
test "$((8#$brew_prefix_mode & 8#070))" = "$((8#070))"

# should install both option-provided public keys for the runner user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_options_file.pub")" "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_options_raw.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should report healthy macOS, SSH, launchd, and Tailscale state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOX-TEST$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_tailscale_hostname=AGENTBOX-TEST$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_expected=agentboxbrewopt$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix=$(brew --prefix)"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_rwx_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "macos_identity_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_hardening_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_homebrew_user_launchd_absent_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "health_launchd_loaded_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
test "$(sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup)" = "agentboxbrewopt$GITHUB_RUN_ID"
sudo /opt/tanaab/agentbox/bin/health.sh --check

# should allow key-based SSH login with both generated private keys
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
  -o LogLevel=ERROR \
  -i "$TMPDIR/id_agentbox_options_file" \
  "$(id -un)@localhost" true
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
  -o LogLevel=ERROR \
  -i "$TMPDIR/id_agentbox_options_raw" \
  "$(id -un)@localhost" true

# should install the launchd health check tool
test -x /opt/tanaab/agentbox/bin/health.sh
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "root_disk_available_kb="
```

## Destroy tests

```bash
# should remove agentbox runner state and example fixtures
../../scripts/cleanup-agentbox-runner.sh \
  --authorized-key-file "$TMPDIR/id_agentbox_options_file.pub" \
  --authorized-key-file "$TMPDIR/id_agentbox_options_raw.pub" \
  --brewgroup "agentboxbrewopt$GITHUB_RUN_ID" \
  --remove-tmpdir
```
