# Version Example

This example verifies that `boot.sh --agentbox-version` can fetch local git sources and extract a
local `agentbox` tar archive.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should clone a local agentbox source without tailscale setup
mkdir -p "$TMPDIR"
boot.sh \
  --force \
  --debug \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-identity "Jack Archive Claw <jack>" \
  --openclaw-password "JackArchiveClawPass1!" \
  --skip-openclaw-autologin \
  --hostname "TANAABAGENTBOXVER"
test -d "$HOME/tanaab/agentbox/.git"
git -C "$HOME/tanaab/agentbox" remote get-url origin > "$TMPDIR/agentbox.local.origin"

# should prepare a current local archive source
git -C "$GITHUB_WORKSPACE" archive \
  --format=tar.gz \
  --prefix=agentbox-current/ \
  --output="$TMPDIR/agentbox-current.tar.gz" \
  HEAD

# should replace the local checkout from a local archive
boot.sh \
  --force \
  --debug \
  --agentbox-version "$TMPDIR/agentbox-current.tar.gz" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-identity "Jack Archive Claw <jack>" \
  --openclaw-password "JackArchiveClawPass1!" \
  --skip-openclaw-autologin \
  --hostname "TANAABAGENTBOXVER"
```

## Testing

```bash
# should have cloned agentbox from the local workflow checkout before replacing it
test "$(cat "$TMPDIR/agentbox.local.origin")" = "$GITHUB_WORKSPACE"

# should extract source files from the local archive
test -f "$HOME/tanaab/agentbox/boot.sh"
! test -d "$HOME/tanaab/agentbox/.git"

# should extract profile picture assets from the local archive
test -f "$HOME/tanaab/agentbox/assets/profile1.png"
test -f "$HOME/tanaab/agentbox/assets/profile8.png"

# should extract runtime support assets from the local archive
test -f "$HOME/tanaab/agentbox/bin/health.sh"
test -f "$HOME/tanaab/agentbox/launchd/dev.tanaab.agentbox.health.plist.in"
test -f "$HOME/tanaab/agentbox/launchd/dev.tanaab.agentbox.tailscaled.plist.in"

# should create the openclaw runner account
id -u jack >/dev/null
dscl . -read /Users/jack RealName | sed -e '1s/^RealName:[[:space:]]*//' -e 's/^[[:space:]]*//' | grep -Fx "Jack Archive Claw"
test -d /Users/jack
test "$(stat -f "%Su" /Users/jack)" = "jack"

# should report the openclaw runner as non-admin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_user_non_admin_ok=1"

# should keep openclaw runner autologin skipped
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_autologin_ok=skipped"
```
