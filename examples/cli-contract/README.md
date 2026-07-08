# CLI Contract Example

This example keeps lightweight coverage on the public `boot.sh` interface. It does not run the
bootstrap path; mutating setup coverage lives in the envvars, options, users, and version examples.

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

# should document source selection options
boot.sh --help | grep -F -- "--agentbox-version"
boot.sh --help | grep -F "tar archive URL/path"
boot.sh --help | grep -F -- "--brewfile"
boot.sh --help | grep -F "local path or URL"

# should document host access options
boot.sh --help | grep -F -- "--authorized-key"
boot.sh --help | grep -F -- "--tailscale-authkey"
boot.sh --help | grep -F -- "--brewgroup"
boot.sh --help | grep -F -- "group[:trusted-group]"
boot.sh --help | grep -F -- "--hostname"

# should document openclaw runner options
boot.sh --help | grep -F -- "--openclaw-identity"
boot.sh --help | grep -F -- "--openclaw-password"
boot.sh --help | grep -F -- "--skip-openclaw-autologin"

# should document operational options
boot.sh --help | grep -F -- "--version"
boot.sh --help | grep -F -- "--debug"
boot.sh --help | grep -F -- "--force"
boot.sh --help | grep -F -- "--yes"

# should document source selection environment variables
boot.sh --help | grep -F "AGENTBOX_VERSION               same as --agentbox-version"
boot.sh --help | grep -F "AGENTBOX_BREWFILE              same as --brewfile"

# should document host access environment variables
boot.sh --help | grep -F "AGENTBOX_HOSTNAME              same as --hostname"
boot.sh --help | grep -F "AGENTBOX_AUTHORIZED_KEY        same as --authorized-key"
boot.sh --help | grep -F "AGENTBOX_TAILSCALE_AUTHKEY     same as --tailscale-authkey"
boot.sh --help | grep -F "AGENTBOX_BREWGROUP             same as --brewgroup"

# should document openclaw runner environment variables
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_IDENTITY     same as --openclaw-identity"
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_PASSWORD     same as --openclaw-password"
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_AUTOLOGIN    falsey disables OpenClaw runner autologin"

# should document operational environment variables
boot.sh --help | grep -F "AGENTBOX_FORCE                 same as --force"
boot.sh --help | grep -F "NONINTERACTIVE                 same as --yes"
boot.sh --help | grep -F "AGENTBOX_DEBUG                 same as --debug"
boot.sh --help | grep -F "CI                             runs in CI mode and disables prompts"
if boot.sh --help | grep -F -- "--ci"; then exit 1; fi

# should keep the unsupported macOS override out of help
if boot.sh --help | grep -F "AGENTBOX_ALLOW_UNSUPPORTED_MACOS"; then exit 1; fi

# should keep hidden plural authorized-key inputs out of help
if boot.sh --help | grep -F -- "--authorized-keys"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_AUTHORIZED_KEYS"; then exit 1; fi

# should keep hidden plural brewfile inputs out of help
if boot.sh --help | grep -F -- "--brewfiles"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_BREWFILES"; then exit 1; fi

# should not expose abbreviated openclaw aliases
if boot.sh --help | grep -F -- "--oc-"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_OC_"; then exit 1; fi

# should keep removed tailscale tag inputs out of help
if boot.sh --help | grep -F -- "--tailscale-tag"; then exit 1; fi
if boot.sh --help | grep -F -- "--tailscale-tags"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TAILSCALE_TAG"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TAILSCALE_TAGS"; then exit 1; fi

# should not expose dashed brewgroup aliases
if boot.sh --help | grep -F -- "--brew-group"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_BREW_GROUP"; then exit 1; fi
if boot.sh --help | grep -F -- "--trusted-brewgroup"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_TRUSTED_BREWGROUP"; then exit 1; fi

# should not expose alternate openclaw autologin spelling
if boot.sh --help | grep -F -- "--skip-openclaw-auto-login"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_OPENCLAW_AUTO_LOGIN"; then exit 1; fi

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

# should mask tailscale auth key defaults in help
AGENTBOX_TAILSCALE_AUTHKEY="tskey-secret-example" boot.sh --help | grep -F "tske...mple"
if AGENTBOX_TAILSCALE_AUTHKEY="tskey-secret-example" boot.sh --help | grep -F "tskey-secret-example"; then exit 1; fi

# should show falsey tailscale auth key values as disabled
AGENTBOX_TAILSCALE_AUTHKEY=off boot.sh --help | grep -F "falsey disables setup"
AGENTBOX_TAILSCALE_AUTHKEY=off boot.sh --help | grep -F "[default: disabled]"

# should show the default brewgroup value
boot.sh --help | grep -F "[default: brewer]"

# should show the disabled brewgroup value
AGENTBOX_BREWGROUP=off boot.sh --help | grep -F "[default: disabled]"

# should show the trusted brewgroup value
AGENTBOX_BREWGROUP=brewer:staff boot.sh --help | grep -F "[default: brewer:staff]"

# should show extra brewfile defaults
boot.sh --help | grep -F -- "--brewfile                  adds an extra Brewfile from a local path or URL [default: none]"
AGENTBOX_BREWFILE="Brewfile.extras,https://example.test/Brewfile" boot.sh --help | grep -F "[default: Brewfile.extras,https://example.test/Brewfile]"
AGENTBOX_BREWFILE="Brewfile.env" boot.sh --brewfile Brewfile.cli --help | grep -F "[default: Brewfile.cli]"
if AGENTBOX_BREWFILE="Brewfile.env" boot.sh --brewfile Brewfile.cli --help | grep -F "Brewfile.env"; then exit 1; fi
AGENTBOX_BREWFILE="Brewfile.env" boot.sh --brewfile= --help | grep -F "[default: none]"

# should show openclaw runner defaults without leaking passwords
boot.sh --help | grep -F -- "--openclaw-identity         configures the OpenClaw runner as \"Full Name <shortname>\""
boot.sh --help | grep -F "A Tanaab-based Claw <openclaw>"
boot.sh --help | grep -F -- "--openclaw-password         sets the OpenClaw runner password"
boot.sh --help | grep -F -- "[default: none]"
AGENTBOX_OPENCLAW_PASSWORD="secret-password" boot.sh --help | grep -F -- "--openclaw-password         sets the OpenClaw runner password"
AGENTBOX_OPENCLAW_PASSWORD="secret-password" boot.sh --help | grep -F "[default: provided]"
if AGENTBOX_OPENCLAW_PASSWORD="secret-password" boot.sh --help | grep -F "secret-password"; then exit 1; fi
AGENTBOX_OPENCLAW_AUTOLOGIN=off boot.sh --help | grep -F -- "--skip-openclaw-autologin   skips default OpenClaw runner autologin"
boot.sh --skip-openclaw-autologin --help | grep -F -- "--skip-openclaw-autologin   skips default OpenClaw runner autologin"
if AGENTBOX_OPENCLAW_AUTOLOGIN=off boot.sh --help | grep -F -- "--skip-openclaw-autologin" | grep -F "[default:"; then exit 1; fi
if boot.sh --skip-openclaw-autologin --help | grep -F -- "--skip-openclaw-autologin" | grep -F "[default:"; then exit 1; fi

# should fail when openclaw option values are missing
set +e
output="$(boot.sh --openclaw-identity 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-identity requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw password value is empty
set +e
output="$(boot.sh --openclaw-password= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-password must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when brewfile option values are missing
set +e
output="$(boot.sh --brewfile 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --brewfile requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

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
