# Codex Example

This non-mutating example verifies the shell preflight used by agentbox plugin skills before they
invoke Bun.

## Setup

```bash
# should have the plugin runtime preflight available
test -x "$AGENTBOX_PAYLOAD_DIR/scripts/check-plugin-runtime.sh"
```

## Testing

```bash
# should explain when Bun is not on PATH
mkdir -p "$TMPDIR/codex-missing"
set +e
output="$(PATH="$TMPDIR/codex-missing" "$AGENTBOX_PAYLOAD_DIR/scripts/check-plugin-runtime.sh" 2>&1)"
command_status="$?"
set -e
printf '%s\n' "$output"
printf '%s\n' "$output" | grep -F "Bun was not found on PATH"
printf '%s\n' "$output" | grep -F "hosted agentbox Bash bootstrap"
test "$command_status" -eq 2

# should pass silently for a supported Bun version
mkdir -p "$TMPDIR/codex-supported/bin"
ln -s "$AGENTBOX_PAYLOAD_DIR/examples/codex/fixtures/bun" "$TMPDIR/codex-supported/bin/bun"
output="$(FAKE_BUN_VERSION=1.3.4 PATH="$TMPDIR/codex-supported/bin" "$AGENTBOX_PAYLOAD_DIR/scripts/check-plugin-runtime.sh" 2>&1)"
test -z "$output"

# should reject Bun versions outside the declared engine range
mkdir -p "$TMPDIR/codex-unsupported/bin"
ln -s "$AGENTBOX_PAYLOAD_DIR/examples/codex/fixtures/bun" "$TMPDIR/codex-unsupported/bin/bun"
for bun_version in 1.2.23 1.4.0; do
  set +e
  output="$(FAKE_BUN_VERSION="$bun_version" PATH="$TMPDIR/codex-unsupported/bin" "$AGENTBOX_PAYLOAD_DIR/scripts/check-plugin-runtime.sh" 2>&1)"
  command_status="$?"
  set -e
  printf '%s\n' "$output"
  printf '%s\n' "$output" | grep -F "Bun $bun_version"
  printf '%s\n' "$output" | grep -F "requires Bun >=1.3.0 <1.4.0"
  test "$command_status" -eq 2
done

# should explain when the discovered Bun executable is broken
mkdir -p "$TMPDIR/codex-broken/bin"
ln -s "$AGENTBOX_PAYLOAD_DIR/examples/codex/fixtures/bun" "$TMPDIR/codex-broken/bin/bun"
set +e
output="$(FAKE_BUN_BROKEN=1 PATH="$TMPDIR/codex-broken/bin" "$AGENTBOX_PAYLOAD_DIR/scripts/check-plugin-runtime.sh" 2>&1)"
command_status="$?"
set -e
printf '%s\n' "$output"
printf '%s\n' "$output" | grep -F "was found at"
printf '%s\n' "$output" | grep -F "but could not run"
test "$command_status" -eq 2
```
