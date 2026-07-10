# Sudo Example

This example verifies the non-mutating `agentbox` sudo contract with example-local fake sudo and
Bootbox commands. It exercises interactive authorization, stale-keepalive recovery, contextual
reauthorization, the Bootbox boundary, and CI paths without changing machine state or reading an
administrator password.

## Setup

```bash
# should have prepared agentbox on PATH or provided a local source override
if ! printenv AGENTBOX_SUDO_TEST_SCRIPT >/dev/null; then command -v agentbox >/dev/null; fi

# should have executable sudo fixtures
test -x bin/run-agentbox
test -x bin/sudo
test -x bin/bootbox
```

## Testing

```bash
# should keep bootbox execution before interactive authorization in main
agentbox_source="$(printenv AGENTBOX_SUDO_TEST_SCRIPT 2>/dev/null || command -v agentbox)"
awk '
  /^main[(][)] [{]/ { in_main=1 }
  in_main && $0 == "  ensure_bootbox_core_requirements" { core=NR }
  in_main && $0 == "  run_bootbox_for_agentbox_brewfile" { brewfiles=NR }
  in_main && $0 == "  start_sudo_session" { authorization=NR }
  in_main && $0 == "  run_agentbox_hostname_setup" { host_setup=NR }
  END { exit !(core < brewfiles && brewfiles < authorization && authorization < host_setup) }
' "$agentbox_source"
```

```bash
# should run bootbox before requesting interactive agentbox authorization
mkdir -p "$TMPDIR"
output="$(bin/run-agentbox interactive-happy 2>&1)"
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "debug prepared effective brewfile at /var/folders/fake/brewfile-effective.test"
printf "%s\n" "$output" | grep -F "keepalive_after_authorization=alive"
printf "%s\n" "$output" | grep -F "verified sudo access before\\ homebrew\\ login-shell\\ PATH\\ setup"
grep -Fx "bootbox_external_sudo=missing" "$TMPDIR/sudo-state-interactive-happy/bootbox.log"
test "$(sed -n '1p' "$TMPDIR/sudo-state-interactive-happy/events.log")" = "bootbox"
test "$(sed -n '2p' "$TMPDIR/sudo-state-interactive-happy/events.log")" = "sudo -v"
test "$(grep -Fxc "sudo -v" "$TMPDIR/sudo-state-interactive-happy/sudo.log")" -eq 1
grep -Fx "sudo -n -v" "$TMPDIR/sudo-state-interactive-happy/sudo.log"
grep -Fx "sudo -n /usr/bin/true" "$TMPDIR/sudo-state-interactive-happy/sudo.log"
tail -n +2 "$TMPDIR/sudo-state-interactive-happy/sudo.log" | awk '$2 != "-n" { exit 1 }'
if printf "%s\n" "$output" | grep -F "please enter sudo password:"; then exit 1; fi
```

```bash
# should allow bootbox to request sudo before agentbox authorization when required
output="$(bin/run-agentbox interactive-bootbox-sudo 2>&1)"
printf "%s\n" "$output"
grep -Fx "bootbox_external_sudo=missing" "$TMPDIR/sudo-state-interactive-bootbox-sudo/bootbox.log"
test "$(sed -n '1p' "$TMPDIR/sudo-state-interactive-bootbox-sudo/events.log")" = "bootbox"
test "$(sed -n '2p' "$TMPDIR/sudo-state-interactive-bootbox-sudo/events.log")" = "sudo -v"
test "$(sed -n '3p' "$TMPDIR/sudo-state-interactive-bootbox-sudo/events.log")" = "sudo -v"
test "$(grep -Fxc "sudo -v" "$TMPDIR/sudo-state-interactive-bootbox-sudo/sudo.log")" -eq 2
grep -Fx "sudo -n /usr/bin/true" "$TMPDIR/sudo-state-interactive-bootbox-sudo/sudo.log"
```

```bash
# should restart a stale keepalive while cached authorization remains valid
output="$(bin/run-agentbox stale-keepalive 2>&1)"
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "keepalive_before_check=dead"
printf "%s\n" "$output" | grep -F "detected inactive sudo keepalive"
printf "%s\n" "$output" | grep -F "restarted sudo keepalive before\\ homebrew\\ login-shell\\ PATH\\ setup"
printf "%s\n" "$output" | grep -F "keepalive_after_check=alive"
test "$(grep -Fxc "sudo -v" "$TMPDIR/sudo-state-stale-keepalive/sudo.log")" -eq 1
grep -Fx "sudo -n /usr/bin/true" "$TMPDIR/sudo-state-stale-keepalive/sudo.log"
tail -n +2 "$TMPDIR/sudo-state-stale-keepalive/sudo.log" | awk '$2 != "-n" { exit 1 }'
if printf "%s\n" "$output" | grep -F "administrator authorization required again"; then exit 1; fi
```

```bash
# should explain and recover each time interactive authorization is lost
output="$(bin/run-agentbox interactive-recovery 2>&1)"
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "keepalive_before_check=dead"
test "$(printf "%s\n" "$output" | grep -Fxc "administrator authorization required again")" -eq 2
printf "%s\n" "$output" | grep -F "agentbox could not refresh its sudo authorization during before homebrew login-shell PATH setup."
printf "%s\n" "$output" | grep -F "agentbox could not refresh its sudo authorization during before second privileged phase."
printf "%s\n" "$output" | grep -F "restored sudo access before\\ homebrew\\ login-shell\\ PATH\\ setup"
printf "%s\n" "$output" | grep -F "restored sudo access before\\ second\\ privileged\\ phase"
printf "%s\n" "$output" | grep -F "keepalive_after_recovery=alive"
test "$(grep -Fxc "sudo -v" "$TMPDIR/sudo-state-interactive-recovery/sudo.log")" -eq 3
grep -Fx "sudo -n /usr/bin/true" "$TMPDIR/sudo-state-interactive-recovery/sudo.log"
awk '$0 == "sudo -v" { prompts++; next } $2 != "-n" { exit 1 } END { exit (prompts == 3 ? 0 : 1) }' "$TMPDIR/sudo-state-interactive-recovery/sudo.log"
```

```bash
# should keep ci sudo authorization fully noninteractive
output="$(bin/run-agentbox ci-valid 2>&1)"
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "verified sudo access before\\ ci\\ phase"
grep -Fx "bootbox_external_sudo=1" "$TMPDIR/sudo-state-ci-valid/bootbox.log"
grep -Fx "sudo -n /usr/bin/true" "$TMPDIR/sudo-state-ci-valid/sudo.log"
if grep -Fx "sudo -v" "$TMPDIR/sudo-state-ci-valid/sudo.log"; then exit 1; fi
awk '$2 != "-n" { exit 1 }' "$TMPDIR/sudo-state-ci-valid/sudo.log"
if printf "%s\n" "$output" | grep -F "administrator access required"; then exit 1; fi
```

```bash
# should fail ci authorization without prompting or starting a keepalive
set +e
output="$(bin/run-agentbox ci-invalid 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
test "$command_status" -ne 0
printf "%s\n" "$output" | grep -F "sudo access is required before agentbox can install packages or configure services."
printf "%s\n" "$output" | grep -F "keepalive_pid_at_exit=empty"
printf "%s\n" "$output" | grep -F "sudo_session_active_at_exit=0"
grep -Fx "sudo -n -v" "$TMPDIR/sudo-state-ci-invalid/sudo.log"
if grep -Fx "sudo -v" "$TMPDIR/sudo-state-ci-invalid/sudo.log"; then exit 1; fi
if printf "%s\n" "$output" | grep -F "administrator access required"; then exit 1; fi
```

## Destroy tests

```bash
# should remove sudo fixtures
rm -rf "$TMPDIR"/agentbox-sudo-testable.sh "$TMPDIR"/sudo-state-*
```
