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

# should install the provided public key for the runner user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_no_tailscale.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should report healthy macOS, SSH, launchd, and skipped Tailscale posture
health_report="$(sudo /opt/tanaab/agentbox/bin/health.sh --check)"
printf "%s\n" "$health_report" | grep -F "posture_ok=1"
printf "%s\n" "$health_report" | grep -F "expected_hostname=TANAABAGENTBOX-NOTS$GITHUB_RUN_ID"
printf "%s\n" "$health_report" | grep -F "macos_identity_ok=1"
printf "%s\n" "$health_report" | grep -F "ssh_hardening_ok=1"
printf "%s\n" "$health_report" | grep -F "tailscale_expected=0"
printf "%s\n" "$health_report" | grep -F "tailscale_ok=skipped"
printf "%s\n" "$health_report" | grep -F "health_launchd_loaded_ok=1"

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

# should install the launchd health check tool
test -x /opt/tanaab/agentbox/bin/health.sh
printf "%s\n" "$health_report" | grep -F "root_disk_available_kb="

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
