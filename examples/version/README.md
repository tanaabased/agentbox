# Version Example

This example verifies that `boot.sh --agentbox-version` can fetch local git sources and extract a
local `agentbox` tar archive.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should prepare a clean agentbox target and runner state
../../scripts/cleanup-agentbox-runner.sh
mkdir -p "$TMPDIR"

# should clone a local agentbox source without Tailscale setup
boot.sh \
  --force \
  --debug \
  --agentbox-version "$GITHUB_WORKSPACE" \
  --tailscale-authkey off \
  --brewgroup off \
  --hostname "TANAABAGENTBOXVER$GITHUB_RUN_ID"
test -d "$HOME/tanaab/agentbox/.git"
git -C "$HOME/tanaab/agentbox" remote get-url origin > "$TMPDIR/agentbox.local.origin"

# should prepare a current local archive source
git -C "$GITHUB_WORKSPACE" archive \
  --format=tar.gz \
  --prefix=agentbox-current/ \
  --output="$TMPDIR/agentbox-current.tar.gz" \
  HEAD

# should install a local archive without Tailscale setup and replace the local checkout
boot.sh \
  --force \
  --debug \
  --agentbox-version "$TMPDIR/agentbox-current.tar.gz" \
  --tailscale-authkey off \
  --brewgroup off \
  --hostname "TANAABAGENTBOXVER$GITHUB_RUN_ID"
```

## Testing

```bash
# should have cloned agentbox from the local workflow checkout before replacing it
test "$(cat "$TMPDIR/agentbox.local.origin")" = "$GITHUB_WORKSPACE"

# should extract the local archive in place
test -f "$HOME/tanaab/agentbox/boot.sh"
test -f "$HOME/tanaab/agentbox/Brewfile"
test -f "$HOME/tanaab/agentbox/bin/health.sh"
test -f "$HOME/tanaab/agentbox/launchd/dev.tanaab.agentbox.health.plist.in"
test -f "$HOME/tanaab/agentbox/launchd/dev.tanaab.agentbox.tailscaled.plist.in"
! test -d "$HOME/tanaab/agentbox/.git"
```

## Destroy tests

```bash
# should remove agentbox runner state
../../scripts/cleanup-agentbox-runner.sh --remove-tmpdir
```
