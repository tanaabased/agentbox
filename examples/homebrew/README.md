# Homebrew Example

This example verifies extra Brewfile delegation, Homebrew prefix ownership, and brewgroup behavior.
It is intended for CI by default because it mutates local groups, Homebrew state, SSH, launchd, and
OpenClaw.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null

# should have a workflow payload available for agentbox
test -d "$AGENTBOX_PAYLOAD_DIR/.git"

# should run agentbox successfully with homebrew options
mkdir -p "$TMPDIR"
printf 'brew "hello"\n' > "$TMPDIR/Brewfile.extra-local"
printf 'brew "tree"\n' > "$TMPDIR/Brewfile.extra-url"
agentbox \
  --force \
  --hostname "TANAABAGENTBOXHOMEBREW" \
  --brewfile "$TMPDIR/Brewfile.extra-local" \
  --brewfile "file://$TMPDIR/Brewfile.extra-url" \
  --tailscale-authkey off \
  --brewgroup "bobsbrewcrew:staff" \
  --openclaw-autologin off \
  --openclaw-identity "Bob Homebrew Claw <bob>" \
  --openclaw-password "BobHomebrewClawPass1!" \
  --openclaw-auth-choice skip
```

## Testing

```bash
# should satisfy the extra brewfiles
brew bundle check --file "$TMPDIR/Brewfile.extra-local" --no-upgrade
brew bundle check --file "$TMPDIR/Brewfile.extra-url" --no-upgrade
command -v hello >/dev/null
command -v tree >/dev/null

# should create the brewgroup
dscl . -read "/Groups/bobsbrewcrew" >/dev/null

# should add bootstrap users to the brewgroup
dscl . -read "/Groups/bobsbrewcrew" GroupMembership | tr " " "\n" | grep -Fx "$(id -un)"
dscl . -read "/Groups/bobsbrewcrew" GroupMembership | tr " " "\n" | grep -Fx bob

# should make the homebrew prefix writable by the brewgroup
brew_prefix="$(brew --prefix)"
test "$(stat -f "%Sg" "$brew_prefix")" = "bobsbrewcrew"
brew_prefix_mode="$(stat -f "%Lp" "$brew_prefix")"
test "$((8#$brew_prefix_mode & 8#070))" = "$((8#070))"

# should give a future staff user inherited membership in the brewgroup
sudo dscl . -delete /Users/brewhelper >/dev/null 2>&1 || true
test_user_uid="$(dscl . -list /Users UniqueID | awk '$2 ~ /^[0-9]+$/ { used[$2] = 1 } END { for (uid = 701; uid < 1000; uid++) { if (!(uid in used)) { print uid; exit } } }')"
test -n "$test_user_uid"
sudo dscl . -create /Users/brewhelper
sudo dscl . -create /Users/brewhelper UserShell /usr/bin/false
sudo dscl . -create /Users/brewhelper RealName "Brew Helper"
sudo dscl . -create /Users/brewhelper UniqueID "$test_user_uid"
sudo dscl . -create /Users/brewhelper PrimaryGroupID 20
sudo dseditgroup -o checkmember -m brewhelper "bobsbrewcrew"

# should report brewgroup state
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_expected=bobsbrewcrew"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_admin_user_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brewgroup_openclaw_user_ok=1"

# should report trusted brewgroup health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_enabled=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_expected=staff"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "trusted_brewgroup_nested_ok=1"

# should report homebrew prefix health
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix=$(brew --prefix)"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_group_rwx_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_recursive_access_ok=1"
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "brew_prefix_ok=1"
test "$(sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup)" = "bobsbrewcrew"

# should stage gateway activation without changing CI autologin
sudo /opt/tanaab/agentbox/bin/health.sh --report | tee /dev/stderr | grep -F "openclaw_gateway_state=pending_first_login"
```
