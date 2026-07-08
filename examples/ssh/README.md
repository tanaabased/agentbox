# SSH Example

This example verifies authorized-key installation, SSH hardening, and localhost SSH login for the
invoking admin and OpenClaw runner. It is intended for CI by default because it mutates SSH, local
users, Homebrew state, launchd, and OpenClaw.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should run boot.sh successfully with authorized keys
mkdir -p "$TMPDIR"
rm -f "$TMPDIR/id_agentbox_ssh_file" "$TMPDIR/id_agentbox_ssh_file.pub"
rm -f "$TMPDIR/id_agentbox_ssh_raw" "$TMPDIR/id_agentbox_ssh_raw.pub"
ssh-keygen -t ed25519 -N "" -C "agentbox-ssh-file@example.test" -f "$TMPDIR/id_agentbox_ssh_file" >/dev/null
ssh-keygen -t ed25519 -N "" -C "agentbox-ssh-raw@example.test" -f "$TMPDIR/id_agentbox_ssh_raw" >/dev/null
boot.sh \
  --force \
  --hostname "TANAABAGENTBOXSSH" \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-identity "Sam SSH Claw <sam>" \
  --openclaw-password "SamSSHClawPass1!" \
  --openclaw-auth-choice skip \
  --skip-openclaw-autologin \
  --authorized-key "file:$TMPDIR/id_agentbox_ssh_file.pub" \
  --authorized-key "$(cat "$TMPDIR/id_agentbox_ssh_raw.pub")"
```

## Testing

```bash
# should install both authorized keys for the admin user
test -f "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_ssh_file.pub")" "$HOME/.ssh/authorized_keys"
grep -qxF "$(cat "$TMPDIR/id_agentbox_ssh_raw.pub")" "$HOME/.ssh/authorized_keys"
test "$(stat -f "%Lp" "$HOME/.ssh")" = "700"
test "$(stat -f "%Lp" "$HOME/.ssh/authorized_keys")" = "600"

# should install both authorized keys for the openclaw runner user
sudo test -f /Users/sam/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_ssh_file.pub")" /Users/sam/.ssh/authorized_keys
sudo grep -qxF "$(cat "$TMPDIR/id_agentbox_ssh_raw.pub")" /Users/sam/.ssh/authorized_keys
test "$(sudo stat -f "%Lp" /Users/sam/.ssh)" = "700"
test "$(sudo stat -f "%Lp" /Users/sam/.ssh/authorized_keys)" = "600"

# should report ssh hardening for allowed users
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_allowed_users=$(id -un) sam"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group=com.apple.access_ssh"
if sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_group_exists_ok=1"; then
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=1"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=1"
else
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_admin_user_ok=skipped"
  sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_access_openclaw_user_ok=skipped"
fi
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "ssh_hardening_ok=1"

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
  -i "$TMPDIR/id_agentbox_ssh_file" \
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
  -i "$TMPDIR/id_agentbox_ssh_raw" \
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
  -i "$TMPDIR/id_agentbox_ssh_file" \
  sam@localhost true

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
