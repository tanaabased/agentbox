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

# should install the provided public key
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_version.pub")" "$HOME/.ssh/authorized_keys"

# should report healthy macOS, SSH, launchd, and Tailscale posture
health_report="$(sudo /opt/tanaab/agentbox/bin/health.sh --check)"
printf "%s\n" "$health_report" | grep -F "posture_ok=1"
printf "%s\n" "$health_report" | grep -F "expected_hostname=TANAABAGENTBOXVER$GITHUB_RUN_ID"
printf "%s\n" "$health_report" | grep -F "expected_tailscale_hostname=AGENTBOXVER$GITHUB_RUN_ID"
printf "%s\n" "$health_report" | grep -F "macos_identity_ok=1"
printf "%s\n" "$health_report" | grep -F "ssh_hardening_ok=1"
printf "%s\n" "$health_report" | grep -F "tailscale_ok=1"
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
  -i "$TMPDIR/id_agentbox_version" \
  "$(id -un)@localhost" true

# should install the launchd health check tool
test -x /opt/tanaab/agentbox/bin/health.sh
printf "%s\n" "$health_report" | grep -F "root_disk_available_kb="
```

## Destroy tests

```bash
# should remove agentbox runner state and example fixtures
../../scripts/cleanup-agentbox-runner.sh \
  --authorized-key-file "$TMPDIR/id_agentbox_version.pub" \
  --remove-tmpdir
```
