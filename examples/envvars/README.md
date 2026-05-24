# Envvars Example

This example runs the real `boot.sh` setup using environment variables, then verifies the resulting
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

# should generate a public key fixture for envvar authorized-key installation
rm -f "$TMPDIR/id_agentbox_envvars" "$TMPDIR/id_agentbox_envvars.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-envvars@example.test" -f "$TMPDIR/id_agentbox_envvars" >/dev/null

# should run boot.sh successfully using envvars
AGENTBOX_DEBUG=1 \
AGENTBOX_FORCE=1 \
AGENTBOX_HOSTNAME="TANAABAGENTBOXENV$GITHUB_RUN_ID" \
AGENTBOX_AUTHORIZED_KEY="$(cat "$TMPDIR/id_agentbox_envvars.pub")" \
boot.sh
test -f "$HOME/tanaab/agentbox/Brewfile"
command -v tailscale >/dev/null
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
test "$(scutil --get ComputerName)" = "TANAABAGENTBOXENV$GITHUB_RUN_ID"
test "$(scutil --get HostName)" = "TANAABAGENTBOXENV$GITHUB_RUN_ID"
test "$(scutil --get LocalHostName)" = "TANAABAGENTBOXENV$GITHUB_RUN_ID"

# should derive the Tailscale hostname from the TANAAB-prefixed canonical hostname
tailscale status --json | jq -e --arg host "AGENTBOXENV$GITHUB_RUN_ID" '.Self.HostName == $host'

# should enable classic SSH
sudo systemsetup -getremotelogin | grep -F "Remote Login: On"

# should install the envvar-provided public key for the runner user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_envvars.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

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
  --authorized-key-file "$TMPDIR/id_agentbox_envvars.pub" \
  --remove-tmpdir
```
