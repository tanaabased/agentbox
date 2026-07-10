# Sudo Example

This example runs the prepared `agentbox` entrypoint with real macOS users, `/usr/bin/sudo`,
Bootbox, Homebrew, and launchd. It verifies the password-required interactive authorization boundary
on a fresh GitHub-hosted runner rather than replacing product dependencies with test doubles.

## Setup

```bash
# should have the prepared agentbox entrypoint and interactive driver
test -x "$GITHUB_WORKSPACE/dist/agentbox"
test -d "$AGENTBOX_PAYLOAD_DIR/.git"
test -x /usr/bin/expect
test -f interactive.exp

# should prepare a password-required macos administrator
mkdir -p "$TMPDIR"
umask 077
printf "Agentbox%sAa1!\n" "$(uuidgen | tr -d '-')" > "$TMPDIR/admin-password"
sudo sysadminctl -addUser sudoexample -fullName "Sudo Example Admin" -password "$(cat "$TMPDIR/admin-password")" -home /Users/sudoexample -shell /bin/bash -admin
sudo /usr/sbin/createhomedir -c -u sudoexample
printf '%s\n' 'Defaults:sudoexample timestamp_timeout=5' 'sudoexample ALL = (ALL) PASSWD: ALL' | sudo tee /private/etc/sudoers.d/zz-agentbox-sudo-example >/dev/null
sudo chmod 440 /private/etc/sudoers.d/zz-agentbox-sudo-example
sudo visudo -cf /etc/sudoers
sudo chown -R "sudoexample:$(id -gn sudoexample)" "$TMPDIR"
sudo chown -R sudoexample:admin "$(brew --prefix)"
if sudo -u sudoexample /usr/bin/sudo -n -v; then exit 1; fi

# should reject unavailable non-interactive sudo before bootbox
set +e
output="$(
  sudo -u sudoexample env \
    CI=1 \
    NONINTERACTIVE=1 \
    HOME=/Users/sudoexample \
    USER=sudoexample \
    LOGNAME=sudoexample \
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

# should run agentbox interactively with real password-required sudo
sudo -iu sudoexample env \
  AGENTBOX_PAYLOAD_DIR="$GITHUB_WORKSPACE" \
  AGENTBOX_SUDO_AGENTBOX="$GITHUB_WORKSPACE/dist/agentbox" \
  AGENTBOX_SUDO_PASSWORD_FILE="$TMPDIR/admin-password" \
  AGENTBOX_SUDO_TRANSCRIPT="$TMPDIR/interactive.log" \
  AGENTBOX_SUDO_WORKSPACE="$GITHUB_WORKSPACE" \
  TERM=xterm-256color \
  /usr/bin/expect "$GITHUB_WORKSPACE/examples/sudo/interactive.exp"
```

## Testing

```bash
# should authorize agentbox once after bootbox completes
bootbox_line="$(grep -n -m 1 -F "bootbox finished applying agentbox brewfiles" "$TMPDIR/interactive.log" | cut -d: -f1)"
authorization_line="$(grep -n -m 1 -F "administrator access required" "$TMPDIR/interactive.log" | cut -d: -f1)"
test -n "$bootbox_line"
test -n "$authorization_line"
test "$bootbox_line" -lt "$authorization_line"
grep -Fx "agentbox_sudo_prompt_count=1" "$TMPDIR/interactive.log"

# should pass the overall agentbox health check
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "agentbox_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --check
```

## Destroy tests

```bash
# should remove generated sudo password material
sudo rm -f /private/etc/sudoers.d/zz-agentbox-sudo-example
sudo rm -f "$TMPDIR/admin-password"
```
