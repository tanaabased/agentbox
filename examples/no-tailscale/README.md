# No Tailscale Example

This example runs the real `boot.sh` setup with Tailscale setup disabled, then verifies the
resulting GitHub-hosted macOS runner state. It is intended for CI by default because it mutates
system settings, Homebrew state, SSH, and launchd.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should prepare a clean agentbox target and runner state
../../scripts/cleanup-agentbox-runner.sh
mkdir -p "$TMPDIR"

# should generate a public key fixture for authorized-key installation
rm -f "$TMPDIR/id_agentbox_no_tailscale" "$TMPDIR/id_agentbox_no_tailscale.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-no-tailscale@example.test" -f "$TMPDIR/id_agentbox_no_tailscale" >/dev/null

# should run boot.sh successfully with Tailscale setup disabled
boot.sh \
  --force \
  --debug \
  --hostname "TANAABAGENTBOX-NOTS$GITHUB_RUN_ID" \
  --tailscale-authkey off \
  --authorized-key "file:$TMPDIR/id_agentbox_no_tailscale.pub"
test -f "$HOME/tanaab/agentbox/Brewfile"
command -v tailscale >/dev/null
```

## Testing

```bash
# should install homebrew and required commands, including the Tailscale formula
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
test "$(scutil --get ComputerName)" = "TANAABAGENTBOX-NOTS$GITHUB_RUN_ID"
test "$(scutil --get HostName)" = "TANAABAGENTBOX-NOTS$GITHUB_RUN_ID"
test "$(scutil --get LocalHostName)" = "TANAABAGENTBOX-NOTS$GITHUB_RUN_ID"

# should enable classic SSH
sudo systemsetup -getremotelogin | grep -F "Remote Login: On"

# should install the provided public key for the runner user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_no_tailscale.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should harden SSH to key-only login for the runner user
sudo /usr/sbin/sshd -T | grep -F "passwordauthentication no"
sudo /usr/sbin/sshd -T | grep -F "kbdinteractiveauthentication no"
sudo /usr/sbin/sshd -T | grep -F "permitrootlogin no"
sudo /usr/sbin/sshd -T | grep -F "pubkeyauthentication yes"
sudo /usr/sbin/sshd -T | grep -F "allowusers $(id -un)"

# should allow key-based SSH login with the generated private key
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
  -i "$TMPDIR/id_agentbox_no_tailscale" \
  "$(id -un)@localhost" true

# should install the launchd health check
test -x /opt/tanaab/agentbox/bin/health.sh
if grep -F "tailscale" /opt/tanaab/agentbox/bin/health.sh; then exit 1; fi
test -f /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist
sudo launchctl print system/dev.tanaab.agentbox.health >/dev/null

# should not start tailscaled or join Tailscale
if pgrep -x tailscaled >/dev/null; then exit 1; fi
if tailscale status --json 2>/dev/null | jq -e '((.Self.HostName // "") != "") or (((.Self.TailscaleIPs // []) | length) > 0)'; then exit 1; fi
if tailscale ip -4 2>/dev/null | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"; then exit 1; fi
```

## Destroy tests

```bash
# should remove agentbox runner state and example fixtures
../../scripts/cleanup-agentbox-runner.sh \
  --authorized-key-file "$TMPDIR/id_agentbox_no_tailscale.pub" \
  --remove-tmpdir
```
