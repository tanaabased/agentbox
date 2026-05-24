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

# should set macOS system identity from the canonical hostname
test "$(scutil --get ComputerName)" = "TANAABAGENTBOX-TEST$GITHUB_RUN_ID"
test "$(scutil --get HostName)" = "TANAABAGENTBOX-TEST$GITHUB_RUN_ID"
test "$(scutil --get LocalHostName)" = "TANAABAGENTBOX-TEST$GITHUB_RUN_ID"

# should enable headless time and recovery settings
sudo systemsetup -getusingnetworktime | grep -F "Network Time: On"
sudo systemsetup -getrestartfreeze | grep -E ": On$"

# should derive the Tailscale hostname from the TANAAB-prefixed canonical hostname
tailscale status --json | jq -e --arg host "AGENTBOX-TEST$GITHUB_RUN_ID" '.Self.HostName == $host'

# should enable classic SSH
sudo systemsetup -getremotelogin | grep -F "Remote Login: On"

# should install both option-provided public keys for the runner user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_options_file.pub")" "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_options_raw.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should harden SSH to key-only login for the runner user
sudo /usr/sbin/sshd -T | grep -F "passwordauthentication no"
sudo /usr/sbin/sshd -T | grep -F "kbdinteractiveauthentication no"
sudo /usr/sbin/sshd -T | grep -F "permitrootlogin no"
sudo /usr/sbin/sshd -T | grep -F "pubkeyauthentication yes"
sudo /usr/sbin/sshd -T | grep -F "allowusers $(id -un)"

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

# should run tailscaled as a service and remain joined to Tailscale
sudo brew services info tailscale >/dev/null
pgrep -x tailscaled >/dev/null
tailscale status >/dev/null
tailscale ip -4 | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"

# should install the launchd health check
test -x /opt/tanaab/agentbox/bin/health.sh
grep -F "root_disk_available_kb=" /opt/tanaab/agentbox/bin/health.sh
test -f /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist
sudo launchctl print system/dev.tanaab.agentbox.health >/dev/null
```

## Destroy tests

```bash
# should remove agentbox runner state and example fixtures
../../scripts/cleanup-agentbox-runner.sh \
  --authorized-key-file "$TMPDIR/id_agentbox_options_file.pub" \
  --authorized-key-file "$TMPDIR/id_agentbox_options_raw.pub" \
  --remove-tmpdir
```
