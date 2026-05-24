# Version Example

This example verifies that `boot.sh --agentbox-version` can fetch and extract a published
`agentbox` release archive.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null

# should prepare a clean agentbox target and runner state
../../scripts/cleanup-agentbox-runner.sh
mkdir -p "$TMPDIR"

# should install a published version archive without Tailscale setup
boot.sh \
  --force \
  --debug \
  --agentbox-version v1.0.0-beta.1 \
  --tailscale-authkey off \
  --hostname "TANAABAGENTBOXVER$GITHUB_RUN_ID"
```

## Testing

```bash
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
