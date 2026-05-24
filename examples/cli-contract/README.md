# CLI Contract Example

This example keeps lightweight coverage on the public `boot.sh` interface. It does not run the
bootstrap path; mutating setup coverage lives in the envvars and options examples.

## Setup

```bash
# should have prepared boot.sh on PATH
command -v boot.sh >/dev/null
```

## Testing

```bash
# should show agentbox usage
boot.sh --help | grep -F "Usage:"
boot.sh --help | grep -F "boot.sh [options]"

# should document public options
boot.sh --help | grep -F -- "--agentbox-version"
boot.sh --help | grep -F -- "--authorized-key"
boot.sh --help | grep -F -- "--tailscale-authkey"
boot.sh --help | grep -F -- "--tailscale-tag"
boot.sh --help | grep -F -- "--hostname"
boot.sh --help | grep -F -- "--version"
boot.sh --help | grep -F -- "--debug"
boot.sh --help | grep -F -- "--force"
boot.sh --help | grep -F -- "--yes"

# should document public environment variables
boot.sh --help | grep -F "AGENTBOX_VERSION"
boot.sh --help | grep -F "AGENTBOX_AUTHORIZED_KEY"
boot.sh --help | grep -F "AGENTBOX_TAILSCALE_AUTHKEY"
boot.sh --help | grep -F "AGENTBOX_TAILSCALE_TAG"
boot.sh --help | grep -F "AGENTBOX_HOSTNAME"
boot.sh --help | grep -F "AGENTBOX_FORCE"
boot.sh --help | grep -F "AGENTBOX_DEBUG"
boot.sh --help | grep -F "NONINTERACTIVE"
boot.sh --help | grep -F "CI"

# should keep hidden plural authorized-key inputs out of help
if boot.sh --help | grep -F -- "--authorized-keys"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_AUTHORIZED_KEYS"; then exit 1; fi

# should keep hidden plural Tailscale tag inputs out of help
if boot.sh --help | grep -F -- "--tailscale-tags"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TAILSCALE_TAGS"; then exit 1; fi

# should still accept hidden plural Tailscale tag inputs before an early help exit
boot.sh --tailscale-tags tag:ci,tag:agentbox --help | grep -F "Usage:"
AGENTBOX_TAILSCALE_TAGS=tag:ci,tag:agentbox boot.sh --help | grep -F "Usage:"

# should not expose removed legacy surfaces
if boot.sh --help | grep -F -- "--op-token"; then exit 1; fi
if boot.sh --help | grep -F -- "--ssh-key"; then exit 1; fi
if boot.sh --help | grep -F -- "--me"; then exit 1; fi
if boot.sh --help | grep -F -- "--tanaab"; then exit 1; fi
if boot.sh --help | grep -F "PIROME"; then exit 1; fi
if boot.sh --help | grep -F "OP_SERVICE_ACCOUNT_TOKEN"; then exit 1; fi
if boot.sh --help | grep -F ".codex-plugin"; then exit 1; fi
if boot.sh --help | grep -F "piroplugin"; then exit 1; fi

# should print a version string
test -n "$(boot.sh --version)"

# should mask Tailscale auth key defaults in help
AGENTBOX_TAILSCALE_AUTHKEY="tskey-secret-example" boot.sh --help | grep -F "tske...mple"
if AGENTBOX_TAILSCALE_AUTHKEY="tskey-secret-example" boot.sh --help | grep -F "tskey-secret-example"; then exit 1; fi

# should show falsey Tailscale auth key values as disabled
AGENTBOX_TAILSCALE_AUTHKEY=off boot.sh --help | grep -F "falsey disables setup"
AGENTBOX_TAILSCALE_AUTHKEY=off boot.sh --help | grep -F "[default: disabled]"

# should fail on unknown options with usage context
output="$(boot.sh --not-real 2>&1)" && exit 1
printf "%s\n" "$output" | grep -F "unrecognized option"
printf "%s\n" "$output" | grep -F "Usage:"
printf "%s\n" "$output" | grep -F "boot.sh [options]"
```

## Destroy tests

```bash
# should have no cleanup work
true
```
