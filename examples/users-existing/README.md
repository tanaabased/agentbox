# Users Existing Example

This example verifies OpenClaw runner behavior for a preexisting non-admin macOS user. It is
intended for CI by default because it mutates local users, SSH, Homebrew state, OpenClaw, and
launchd.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should seed a non-admin runner with a missing home
sudo sysadminctl \
  -addUser ted \
  -fullName "Ted Existing Claw" \
  -shell /bin/zsh \
  -home /Users/ted \
  -password "TedExistingClawPass1!" \
  -picture "$GITHUB_WORKSPACE/assets/agentbox-dark.png" || id -u ted >/dev/null
sudo dscl . -create /Users/ted Picture "$GITHUB_WORKSPACE/assets/agentbox-dark.png"
test "$(dscl . -read /Users/ted Picture | cut -d " " -f 2-)" = "$GITHUB_WORKSPACE/assets/agentbox-dark.png"
! test -d /Users/ted

# should reuse the seeded runner without needing an openclaw password
mkdir -p "$TMPDIR"
rm -f "$TMPDIR/id_agentbox_users_existing" "$TMPDIR/id_agentbox_users_existing.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-users-existing@example.test" -f "$TMPDIR/id_agentbox_users_existing" >/dev/null
boot.sh \
  --force \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup "tedsbrewclub" \
  --openclaw-identity "Ted Existing Claw <ted>" \
  --authorized-key "file:$TMPDIR/id_agentbox_users_existing.pub" \
  --hostname "TANAABAGENTBOXUSERSEXISTING"
```

## Testing

```bash
# should keep the openclaw runner account
id -u ted >/dev/null
test -d /Users/ted
test "$(stat -f "%Su" /Users/ted)" = "ted"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should preserve the openclaw runner profile picture
test "$(dscl . -read /Users/ted Picture | cut -d " " -f 2-)" = "$GITHUB_WORKSPACE/assets/agentbox-dark.png"

# should use system openclaw service mode
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_service_mode=system"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"

# should add the openclaw runner to the brewgroup
dscl . -read "/Groups/tedsbrewclub" >/dev/null
dscl . -read "/Groups/tedsbrewclub" GroupMembership | tr " " "\n" | grep -Fx "$(id -un)"
dscl . -read "/Groups/tedsbrewclub" GroupMembership | tr " " "\n" | grep -Fx ted

# should install authorized keys for the openclaw runner user
sudo test -f /Users/ted/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_users_existing.pub")" /Users/ted/.ssh/authorized_keys
test "$(sudo stat -f "%Lp" /Users/ted/.ssh)" = "700"
test "$(sudo stat -f "%Lp" /Users/ted/.ssh/authorized_keys)" = "600"

# should report openclaw runner health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=ted"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Ted Existing Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_exists_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_home_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"

# should report openclaw runner brewgroup health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_openclaw_user_ok=1"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
