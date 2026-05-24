# Version Example

This example verifies that `boot.sh` can replace a default HTTPS checkout with a released
`agentbox` archive. It is intentionally not part of the PR examples matrix until the repository has
a real published tag to fetch through `--agentbox-version`.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a Tailscale auth key from the workflow secret
test -n "$AGENTBOX_TAILSCALE_AUTHKEY"

# should have a real published agentbox version tag to test
test -n "$AGENTBOX_EXAMPLE_VERSION_TAG"

# should prepare a clean agentbox target and runner state
../../scripts/cleanup-agentbox-runner.sh
mkdir -p "$TMPDIR"

# should generate a public key fixture for version authorized-key installation
rm -f "$TMPDIR/id_agentbox_version" "$TMPDIR/id_agentbox_version.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-version@example.test" -f "$TMPDIR/id_agentbox_version" >/dev/null

# should run boot.sh successfully using the default HTTPS source
boot.sh \
  --hostname "TANAABAGENTBOXVER$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --authorized-key "file:$TMPDIR/id_agentbox_version.pub"
test -f "$HOME/tanaab/agentbox/Brewfile"
command -v tailscale >/dev/null
test "$(git -C "$HOME/tanaab/agentbox" remote get-url origin)" = "https://github.com/tanaabased/agentbox.git"
sudo tailscale logout >/dev/null 2>&1 || true

# should run boot.sh successfully using a released version archive and replace the checkout
boot.sh \
  --force \
  --debug \
  --agentbox-version "$AGENTBOX_EXAMPLE_VERSION_TAG" \
  --hostname "TANAABAGENTBOXVER$GITHUB_RUN_ID" \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --authorized-key "file:$TMPDIR/id_agentbox_version.pub"
test -f "$HOME/tanaab/agentbox/Brewfile"
command -v tailscale >/dev/null
```

## Testing

```bash
# should extract the version archive in place
test -f "$HOME/tanaab/agentbox/boot.sh"
test -f "$HOME/tanaab/agentbox/Brewfile"
! test -d "$HOME/tanaab/agentbox/.git"

# should satisfy the agentbox Brewfile from the version archive
brew bundle check --file "$HOME/tanaab/agentbox/Brewfile" --no-upgrade

# should set macOS system identity from the canonical hostname
test "$(scutil --get ComputerName)" = "TANAABAGENTBOXVER$GITHUB_RUN_ID"
test "$(scutil --get HostName)" = "TANAABAGENTBOXVER$GITHUB_RUN_ID"
test "$(scutil --get LocalHostName)" = "TANAABAGENTBOXVER$GITHUB_RUN_ID"

# should derive the Tailscale hostname from the TANAAB-prefixed canonical hostname
tailscale status --json | jq -e --arg host "AGENTBOXVER$GITHUB_RUN_ID" '.Self.HostName == $host'

# should enable classic SSH and install the provided public key
sudo systemsetup -getremotelogin | grep -F "Remote Login: On"
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_version.pub")" "$HOME/.ssh/authorized_keys"

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
  -i "$TMPDIR/id_agentbox_version" \
  "$(id -un)@localhost" true

# should run tailscaled as a service and join Tailscale
sudo brew services info tailscale >/dev/null
pgrep -x tailscaled >/dev/null
tailscale status >/dev/null
tailscale ip -4 | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"

# should install the launchd health check
test -x /opt/tanaab/agentbox/bin/health.sh
test -f /Library/LaunchDaemons/dev.tanaab.agentbox.health.plist
sudo launchctl print system/dev.tanaab.agentbox.health >/dev/null
```

## Destroy tests

```bash
# should remove agentbox runner state and example fixtures
../../scripts/cleanup-agentbox-runner.sh \
  --authorized-key-file "$TMPDIR/id_agentbox_version.pub" \
  --remove-tmpdir
```
