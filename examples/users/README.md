# Users Example

This example verifies OpenClaw runner behavior for a preexisting non-admin macOS user. It is
intended for CI by default because it mutates local users, SSH, Homebrew state, and launchd.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should prepare a clean agentbox target and runner state
existing_user="agentboxuser$GITHUB_RUN_ID$GITHUB_RUN_ATTEMPT"
../../scripts/cleanup-agentbox-runner.sh \
  --user "$existing_user" \
  --brewgroup "agentboxbrewuser$GITHUB_RUN_ID"
mkdir -p "$TMPDIR"

# should generate a public key fixture for preexisting user authorized-key installation
rm -f "$TMPDIR/id_agentbox_users" "$TMPDIR/id_agentbox_users.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-users@example.test" -f "$TMPDIR/id_agentbox_users" >/dev/null

# should create a preexisting non-admin openclaw runner with a custom picture
sudo sysadminctl \
  -addUser ted \
  -fullName "Ted Existing Claw" \
  -shell /bin/zsh \
  -home /Users/ted \
  -password "AgentboxExistingUser$GITHUB_RUN_ID!" \
  -picture "$GITHUB_WORKSPACE/assets/agentbox-dark.png" || id -u ted >/dev/null
if dseditgroup -o checkmember -m ted admin >/dev/null 2>&1; then exit 1; fi
sudo dscl . -create /Users/ted Picture "$GITHUB_WORKSPACE/assets/agentbox-dark.png"
test "$(dscl . -read /Users/ted Picture | cut -d " " -f 2-)" = "$GITHUB_WORKSPACE/assets/agentbox-dark.png"
! test -d /Users/ted

# should fail early for malformed openclaw identity syntax
if boot.sh \
  --force \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-identity "Ted Existing Claw" \
  --skip-openclaw-autologin; then
  exit 1
fi

# should reuse the existing openclaw runner without needing an openclaw password
boot.sh \
  --force \
  --debug \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup "agentboxbrewuser$GITHUB_RUN_ID" \
  --openclaw-identity "Ted Existing Claw <ted>" \
  --skip-openclaw-autologin \
  --authorized-key "file:$TMPDIR/id_agentbox_users.pub" \
  --hostname "TANAABAGENTBOXUSER$GITHUB_RUN_ID"
```

## Testing

```bash
# should preserve and harden the preexisting non-admin openclaw runner
id -u ted >/dev/null
if dseditgroup -o checkmember -m ted admin >/dev/null 2>&1; then exit 1; fi
test -d /Users/ted
test "$(stat -f "%Su" /Users/ted)" = "ted"
test "$(dscl . -read /Users/ted Picture | cut -d " " -f 2-)" = "$GITHUB_WORKSPACE/assets/agentbox-dark.png"

# should keep the preexisting openclaw runner autologin skipped
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"

# should add the preexisting openclaw runner to the configured brewgroup
dscl . -read "/Groups/agentboxbrewuser$GITHUB_RUN_ID" >/dev/null
dseditgroup -o checkmember -m "$(id -un)" "agentboxbrewuser$GITHUB_RUN_ID"
dseditgroup -o checkmember -m ted "agentboxbrewuser$GITHUB_RUN_ID"

# should install authorized keys for the admin and preexisting openclaw runner users
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_users.pub")" "$HOME/.ssh/authorized_keys"
sudo test -f /Users/ted/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_users.pub")" /Users/ted/.ssh/authorized_keys
test "$(sudo stat -f "%Lp" /Users/ted/.ssh)" = "700"
test "$(sudo stat -f "%Lp" /Users/ted/.ssh/authorized_keys)" = "600"

# should report the preexisting openclaw runner as healthy
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user=ted"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_full_name=Ted Existing Claw"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_exists_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_home_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_openclaw_user_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_allowed_users=$(id -un) ted"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group=com.apple.access_ssh"
if sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group_exists_ok=1"; then
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=1"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=1"
else
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=skipped"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=skipped"
fi
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_hardening_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check

# should allow ssh login to the preexisting openclaw runner
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
  -i "$TMPDIR/id_agentbox_users" \
  ted@localhost true
```

## Destroy tests

```bash
# should remove agentbox user scenario state
existing_user="agentboxuser$GITHUB_RUN_ID$GITHUB_RUN_ATTEMPT"
../../scripts/cleanup-agentbox-runner.sh \
  --authorized-key-file "$TMPDIR/id_agentbox_users.pub" \
  --user "$existing_user" \
  --brewgroup "agentboxbrewuser$GITHUB_RUN_ID" \
  --remove-tmpdir
```
