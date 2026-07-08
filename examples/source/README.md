# Source Example

This example verifies source selection and replacement for a local git checkout and a local
`agentbox` tar archive. It is intended for CI by default because it mutates system settings,
Homebrew state, SSH, OpenClaw, and launchd.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should install from the local git source
mkdir -p "$TMPDIR"
boot.sh \
  --force \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-password "SourceOpenClawPass1!" \
  --skip-openclaw-autologin \
  --hostname "TANAABAGENTBOXSOURCE"
git -C "$HOME/tanaab/agentbox" config --get remote.origin.url > "$TMPDIR/agentbox.local.origin"

# should replace the checkout from a local archive
git -C "$GITHUB_WORKSPACE" archive \
  --format=tar.gz \
  --prefix=agentbox-current/ \
  --output="$TMPDIR/agentbox-current.tar.gz" \
  HEAD
boot.sh \
  --force \
  --agentbox-version "$TMPDIR/agentbox-current.tar.gz" \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-password "SourceOpenClawPass1!" \
  --skip-openclaw-autologin \
  --hostname "TANAABAGENTBOXSOURCE"
```

## Testing

```bash
# should record the local git source
grep -Fx "$GITHUB_WORKSPACE" "$TMPDIR/agentbox.local.origin"

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
test -f "$HOME/tanaab/agentbox/launchd/dev.tanaab.agentbox.openclaw-gateway.plist.in"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```
