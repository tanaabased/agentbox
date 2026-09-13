# Tailscale Example

This example verifies the explicit disabled-Tailscale path while keeping the Tailscale formula
available for later use. With the daemon stopped, it also checks resolver creation, repair, and
preservation using reserved `.invalid` names. It is intended for CI by default because it mutates
system settings, Homebrew state, SSH, launchd, and OpenClaw.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should run agentbox successfully with tailscale disabled
AGENTBOX_TAILSCALE_AUTHKEY=off agentbox \
  --force \
  --hostname "TANAABAGENTBOXTAILSCALE" \
  --brewgroup off \
  --openclaw-autologin off \
  --openclaw-identity "Tess Tailscale Claw <tess>" \
  --openclaw-password "TessTailscaleClawPass1!"
```

## Testing

```bash
# should install tailscale
test -x "$(brew --prefix)/bin/tailscale"

# should leave tailscaled stopped
if pgrep -x tailscaled >/dev/null; then exit 1; fi

# should leave tailscale unjoined
if status_json="$(tailscale status --json 2>/dev/null)" &&
  printf "%s\n" "$status_json" | jq -e '((.Self.HostName // "") != "") or (((.Self.TailscaleIPs // []) | length) > 0)'
then
  exit 1
fi
if tailscale ip -4 2>/dev/null | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"; then exit 1; fi

# should report the expected hostname
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "expected_hostname=TANAABAGENTBOXTAILSCALE"

# should report skipped tailscale health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_expected=0"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscaled_launchd_loaded_ok=skipped"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "tailscale_ok=skipped"

# should report loopback openclaw gateway exposure
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_bind=loopback"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_tailscale_mode=off"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"

# should keep gateway activation pending until the runtime user logs in
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_activation_ok=0"
```

### Resolver ownership

The helper runs the prepared installer's resolver function and the installed health function against
controlled files. These cases retain ownership coverage independently of whether a live Tailscale
version creates the real tailnet resolver before agentbox reaches it.

```bash
# should create an owned resolver when none exists
set -o pipefail
resolver=/etc/resolver/created.agentbox-resolver.invalid
sudo test ! -e "$resolver"
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" reconcile created
sudo cat "$resolver"
sudo grep -Fx "# Managed by agentbox." "$resolver"
sudo grep -Fx "nameserver 100.100.100.100" "$resolver"
test "$(sudo stat -f '%Su:%Sg:%Lp' "$resolver")" = root:wheel:644
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" health created | tee /dev/stderr | grep -Fx resolver_ok=1

# should repair an incorrect owned resolver
set -o pipefail
resolver=/etc/resolver/repaired.agentbox-resolver.invalid
printf '%s\n' '# Managed by agentbox.' 'nameserver 192.0.2.1' | sudo tee "$resolver" >/dev/null
sudo chmod 600 "$resolver"
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" reconcile repaired
sudo cat "$resolver"
sudo grep -Fx "# Managed by agentbox." "$resolver"
sudo grep -Fx "nameserver 100.100.100.100" "$resolver"
test "$(sudo stat -f '%Su:%Sg:%Lp' "$resolver")" = root:wheel:644
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" health repaired | tee /dev/stderr | grep -Fx resolver_ok=1

# should preserve a correct resolver owned by another tool
set -o pipefail
resolver=/etc/resolver/preserved.agentbox-resolver.invalid
mkdir -p "$TMPDIR"
printf '%s\n' '# Added by tailscaled' 'nameserver 100.100.100.100' 'port 53' > "$TMPDIR/resolver-preserved"
sudo install -o "$(id -un)" -g staff -m 640 "$TMPDIR/resolver-preserved" "$resolver"
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" reconcile preserved | tee /dev/stderr | grep -F 'already points to tailscale dns'
sudo cmp "$TMPDIR/resolver-preserved" "$resolver"
test "$(sudo stat -f '%Su:%Sg:%Lp' "$resolver")" = "$(id -un):staff:640"
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" health preserved | tee /dev/stderr | grep -Fx resolver_ok=1

# should leave an unowned conflicting resolver unhealthy without overwriting it
set -o pipefail
resolver=/etc/resolver/conflict.agentbox-resolver.invalid
mkdir -p "$TMPDIR"
printf '%s\n' '# Operator configuration' 'nameserver 192.0.2.1' > "$TMPDIR/resolver-conflict"
sudo install -o "$(id -un)" -g staff -m 640 "$TMPDIR/resolver-conflict" "$resolver"
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" reconcile conflict 2>&1 | tee /dev/stderr | grep -F 'not managed by agentbox; leaving it unchanged.'
sudo cmp "$TMPDIR/resolver-conflict" "$resolver"
test "$(sudo stat -f '%Su:%Sg:%Lp' "$resolver")" = "$(id -un):staff:640"
bash "$AGENTBOX_PAYLOAD_DIR/examples/tailscale/resolver-case.sh" health conflict | tee /dev/stderr | grep -Fx resolver_ok=0
```
