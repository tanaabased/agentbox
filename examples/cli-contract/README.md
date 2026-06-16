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
boot.sh --help | grep -F "[NONINTERACTIVE=1]"
boot.sh --help | grep -F "[CI=1]"
boot.sh --help | grep -F "[AGENTBOX_*...]"
boot.sh --help | grep -F "boot.sh [options]"

# should document public options
boot.sh --help | grep -F -- "--agentbox-version"
boot.sh --help | grep -F -- "--authorized-key"
boot.sh --help | grep -F -- "--tailscale-authkey"
boot.sh --help | grep -F -- "--brewgroup"
boot.sh --help | grep -F -- "group[:trusted-group]"
boot.sh --help | grep -F -- "--hostname"
boot.sh --help | grep -F -- "--version"
boot.sh --help | grep -F -- "--debug"
boot.sh --help | grep -F -- "--force"
boot.sh --help | grep -F -- "--yes"

# should document public environment variables
boot.sh --help | grep -F "AGENTBOX_VERSION               same as --agentbox-version"
boot.sh --help | grep -F "AGENTBOX_AUTHORIZED_KEY        same as --authorized-key"
boot.sh --help | grep -F "AGENTBOX_TAILSCALE_AUTHKEY     same as --tailscale-authkey"
boot.sh --help | grep -F "AGENTBOX_BREWGROUP             same as --brewgroup"
boot.sh --help | grep -F "AGENTBOX_HOSTNAME              same as --hostname"
boot.sh --help | grep -F "AGENTBOX_FORCE                 same as --force"
boot.sh --help | grep -F "AGENTBOX_DEBUG                 same as --debug"
boot.sh --help | grep -F "NONINTERACTIVE                 same as --yes"
boot.sh --help | grep -F "CI                             runs in CI mode and disables prompts"
if boot.sh --help | grep -F -- "--ci"; then exit 1; fi

# should keep the unsupported macOS override out of help
if boot.sh --help | grep -F "AGENTBOX_ALLOW_UNSUPPORTED_MACOS"; then exit 1; fi

# should keep hidden plural authorized-key inputs out of help
if boot.sh --help | grep -F -- "--authorized-keys"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_AUTHORIZED_KEYS"; then exit 1; fi

# should keep removed Tailscale tag inputs out of help
if boot.sh --help | grep -F -- "--tailscale-tag"; then exit 1; fi
if boot.sh --help | grep -F -- "--tailscale-tags"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TAILSCALE_TAG"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TAILSCALE_TAGS"; then exit 1; fi

# should not expose dashed brewgroup aliases
if boot.sh --help | grep -F -- "--brew-group"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_BREW_GROUP"; then exit 1; fi
if boot.sh --help | grep -F -- "--trusted-brewgroup"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TRUSTED_BREWGROUP"; then exit 1; fi

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

# should show the default and disabled brewgroup values
boot.sh --help | grep -F "[default: brewer]"
AGENTBOX_BREWGROUP=off boot.sh --help | grep -F "[default: disabled]"
AGENTBOX_BREWGROUP=brewer:staff boot.sh --help | grep -F "[default: brewer:staff]"

# should fail on unknown options with usage context
set +e
output="$(boot.sh --not-real 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "unrecognized option"
printf "%s\n" "$output" | grep -F "Usage:"
printf "%s\n" "$output" | grep -F "boot.sh [options]"
test "$command_status" -ne 0
```

## Destroy tests

```bash
# should have no cleanup work
true
```
