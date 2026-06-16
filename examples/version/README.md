# Version Example

This example verifies that `boot.sh --agentbox-version` can fetch local git sources and extract a
published `agentbox` release archive.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should have a local git checkout available as the agentbox source
test -d "$GITHUB_WORKSPACE/.git"

# should prepare a clean agentbox target and runner state
../../scripts/cleanup-agentbox-runner.sh
mkdir -p "$TMPDIR"

# should also brew trust oven-sh/bun for legacy version support
brew trust oven-sh/bun

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

# should install a published version archive without Tailscale setup and replace the local checkout
boot.sh \
  --force \
  --debug \
  --agentbox-version v1.0.0-beta.1 \
  --tailscale-authkey off \
  --brewgroup off \
  --hostname "TANAABAGENTBOXVER$GITHUB_RUN_ID"
```

## Testing

```bash
# should have cloned agentbox from the local workflow checkout before replacing it
test "$(cat "$TMPDIR/agentbox.local.origin")" = "$GITHUB_WORKSPACE"

# should extract the version archive in place
test -f "$HOME/tanaab/agentbox/boot.sh"
test -f "$HOME/tanaab/agentbox/Brewfile"
! test -d "$HOME/tanaab/agentbox/.git"

# should extract the requested release tag contents
grep -F "## v1.0.0-beta.1" "$HOME/tanaab/agentbox/CHANGELOG.md"
grep -F 'SCRIPT_VERSION="v1.0.0-beta.1"' "$HOME/tanaab/agentbox/dist/boot.sh"
```

## Destroy tests

```bash
# should remove agentbox runner state
../../scripts/cleanup-agentbox-runner.sh --remove-tmpdir
```
