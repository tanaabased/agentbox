# Sudo Example

This example uses a real password-required macOS administrator and `/usr/bin/sudo` on a fresh
GitHub-hosted runner. It verifies that non-interactive agentbox runs reject unavailable reusable
sudo before Bootbox applies Brewfiles or agentbox installs its payload. Successful end-to-end
bootstrap and health coverage remains in the domain examples.

## Setup

```bash
# should have the prepared agentbox entrypoint and workflow payload
test -x "$GITHUB_WORKSPACE/dist/agentbox"
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should prepare a password-required macos administrator
mkdir -p "$TMPDIR"
umask 077
printf "Agentbox%sAa1!\n" "$(uuidgen | tr -d '-')" > "$TMPDIR/admin-password"
sudo sysadminctl -addUser sudoexample -fullName "Sudo Example Admin" -password "$(cat "$TMPDIR/admin-password")" -home /Users/sudoexample -shell /bin/bash -admin
sudo /usr/sbin/createhomedir -c -u sudoexample
printf '%s\n' 'Defaults:sudoexample timestamp_timeout=5' 'sudoexample ALL = (ALL) PASSWD: ALL' | sudo tee /private/etc/sudoers.d/zz-agentbox-sudo-example >/dev/null
sudo chmod 440 /private/etc/sudoers.d/zz-agentbox-sudo-example
sudo visudo -cf /etc/sudoers
if sudo -u sudoexample /usr/bin/sudo -n -v; then exit 1; fi
```

## Testing

```bash
# should reject unavailable non-interactive sudo before bootbox or payload installation
set +e
output="$(
  sudo -u sudoexample env \
    CI="$CI" \
    HOME=/Users/sudoexample \
    USER=sudoexample \
    LOGNAME=sudoexample \
    AGENTBOX_DEBUG=1 \
    AGENTBOX_PAYLOAD_DIR="$GITHUB_WORKSPACE" \
    AGENTBOX_OPENCLAW_PASSWORD="$(cat "$TMPDIR/admin-password")" \
    AGENTBOX_TAILSCALE_AUTHKEY=off \
    AGENTBOX_BREWGROUP=off \
    AGENTBOX_OPENCLAW_AUTH_CHOICE=skip \
    "$GITHUB_WORKSPACE/dist/agentbox" --hostname TANAABAGENTBOXSUDO 2>&1
)"
command_status="$?"
set -e
printf "%s\n" "$output"
test "$command_status" -ne 0
printf "%s\n" "$output" | grep -F "sudo access is required before agentbox can install packages or configure services."
if printf "%s\n" "$output" | grep -F "bootbox finished applying agentbox brewfiles"; then exit 1; fi
test ! -e /opt/tanaab/agentbox/bin/health.sh
```
