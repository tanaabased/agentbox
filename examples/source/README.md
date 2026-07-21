# Source Example

This example verifies that CI runs `agentbox` with an explicit agentbox payload directory and that
runtime files come from that payload. It is intended for CI by default because it mutates system
settings, Homebrew state, SSH, OpenClaw, and launchd.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"
test "$AGENTBOX_PAYLOAD_DIR" = "$GITHUB_WORKSPACE"

# should run agentbox successfully with the workflow payload
agentbox \
  --force \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-autologin off \
  --openclaw-password "SourceOpenClawPass1!" \
  --hostname "TANAABAGENTBOXSOURCE"
```

## Testing

```bash
# should install the health script from the workflow payload
sudo cmp "$AGENTBOX_PAYLOAD_DIR/bin/health.sh" /opt/tanaab/agentbox/bin/health.sh

# should satisfy the workflow payload brewfile
brew bundle check --file "$AGENTBOX_PAYLOAD_DIR/Brewfile" --no-upgrade

# should keep payload avatar and profile picture assets available
test -f "$AGENTBOX_PAYLOAD_DIR/assets/default_avatar.png"
test -f "$AGENTBOX_PAYLOAD_DIR/assets/profile1.png"
test -f "$AGENTBOX_PAYLOAD_DIR/assets/profile8.png"

# should keep payload launchd templates available
test -f "$AGENTBOX_PAYLOAD_DIR/launchd/dev.tanaab.agentbox.health.plist.in"
test -f "$AGENTBOX_PAYLOAD_DIR/launchd/dev.tanaab.agentbox.tailscaled.plist.in"
test -f "$AGENTBOX_PAYLOAD_DIR/launchd/dev.tanaab.agentbox.openclaw-finalize.plist.in"
test -f "$AGENTBOX_PAYLOAD_DIR/libexec/agentbox-openclaw-finalize.sh"

# should stage gateway activation without changing CI autologin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"
```
