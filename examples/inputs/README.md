# Inputs Example

This example keeps lightweight coverage on the public `boot.sh` input surface. It does not run the
bootstrap path; mutating setup coverage lives in the defaults, tailscale, homebrew, ssh, openclaw,
rerun, users-custom, users-existing, and source examples.

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
boot.sh --help | grep -F "tar archive url/path"
boot.sh --help | grep -F -- "--brewfile"
boot.sh --help | grep -F "local path or url"

# should document host access options
boot.sh --help | grep -F -- "--authorized-key"
boot.sh --help | grep -F -- "--tailscale-authkey"
boot.sh --help | grep -F -- "--brewgroup"
boot.sh --help | grep -F -- "group[:trusted-group]"
boot.sh --help | grep -F -- "--hostname"

# should document openclaw runner options
boot.sh --help | grep -F -- "--openclaw-identity"
boot.sh --help | grep -F -- "--openclaw-password"
boot.sh --help | grep -F -- "--openclaw-auth-choice"
boot.sh --help | grep -F -- "--openclaw-auth-env"
boot.sh --help | grep -F -- "--openclaw-service-mode"
boot.sh --help | grep -F -- "--openclaw-gateway-port"

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
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_SERVICE_MODE same as --openclaw-service-mode"
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_AUTH_CHOICE  same as --openclaw-auth-choice"
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_AUTH_ENV     same as --openclaw-auth-env"
boot.sh --help | grep -F "AGENTBOX_OPENCLAW_GATEWAY_PORT same as --openclaw-gateway-port"

# should document operational environment variables
boot.sh --help | grep -F "AGENTBOX_FORCE                 same as --force"
boot.sh --help | grep -F "NONINTERACTIVE                 same as --yes"
boot.sh --help | grep -F "AGENTBOX_DEBUG                 same as --debug"
boot.sh --help | grep -F "CI                             runs in CI mode and disables prompts"
if boot.sh --help | grep -F -- "--ci"; then exit 1; fi

# should keep the unsupported macos override out of help
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

# should not expose openclaw autologin controls
if boot.sh --help | grep -F -- "--skip-openclaw-autologin"; then exit 1; fi
if boot.sh --help | grep -F -- "--skip-openclaw-auto-login"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_OPENCLAW_AUTOLOGIN"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_OPENCLAW_AUTO_LOGIN"; then exit 1; fi

# should not expose skipped openclaw onboarding controls
if boot.sh --help | grep -F -- "--skip-openclaw-onboarding"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_OPENCLAW_ONBOARDING"; then exit 1; fi

# should not expose secret passthrough controls
if boot.sh --help | grep -F -- "--openclaw-secret-input-mode"; then exit 1; fi
if boot.sh --help | grep -F "AGENTBOX_OPENCLAW_SECRET_INPUT_MODE"; then exit 1; fi

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

# should show hostname input precedence
AGENTBOX_HOSTNAME=TANAABENVINPUT boot.sh --help | grep -F "[default: TANAABENVINPUT]"
AGENTBOX_HOSTNAME=TANAABENVINPUT boot.sh --hostname TANAABCLIINPUT --help | grep -F "[default: TANAABCLIINPUT]"
if AGENTBOX_HOSTNAME=TANAABENVINPUT boot.sh --hostname TANAABCLIINPUT --help | grep -F "TANAABENVINPUT"; then exit 1; fi

# should show the default brewgroup value
boot.sh --help | grep -F "[default: brewer]"

# should show disabled brewgroup input
AGENTBOX_BREWGROUP=off boot.sh --help | grep -F "[default: disabled]"

# should show trusted brewgroup input
AGENTBOX_BREWGROUP=brewer:staff boot.sh --help | grep -F "[default: brewer:staff]"

# should show extra brewfile input precedence
boot.sh --help | grep -F -- "--brewfile                  adds an extra Brewfile from a local path or url [default: none]"
AGENTBOX_BREWFILE="Brewfile.extras,https://example.test/Brewfile" boot.sh --help | grep -F "[default: Brewfile.extras,https://example.test/Brewfile]"
AGENTBOX_BREWFILE="Brewfile.env" boot.sh --brewfile Brewfile.cli --help | grep -F "[default: Brewfile.cli]"
if AGENTBOX_BREWFILE="Brewfile.env" boot.sh --brewfile Brewfile.cli --help | grep -F "Brewfile.env"; then exit 1; fi
AGENTBOX_BREWFILE="Brewfile.env" boot.sh --brewfile= --help | grep -F "[default: none]"

# should show openclaw runner defaults without leaking passwords
boot.sh --help | grep -F -- "--openclaw-identity         configures the openclaw runner as \"full name <shortname>\""
boot.sh --help | grep -F "A Tanaab-based Claw <openclaw>"
boot.sh --help | grep -F -- "--openclaw-password         sets the openclaw runner password"
boot.sh --help | grep -F -- "[default: none]"
AGENTBOX_OPENCLAW_PASSWORD="secret-password" boot.sh --help | grep -F -- "--openclaw-password         sets the openclaw runner password"
AGENTBOX_OPENCLAW_PASSWORD="secret-password" boot.sh --help | grep -F "[default: provided]"
if AGENTBOX_OPENCLAW_PASSWORD="secret-password" boot.sh --help | grep -F "secret-password"; then exit 1; fi
boot.sh --help | grep -F -- "--openclaw-service-mode     sets openclaw gateway supervision mode"
boot.sh --help | grep -F -- "--openclaw-service-mode" | grep -F "[default: system]"
AGENTBOX_OPENCLAW_SERVICE_MODE=user boot.sh --help | grep -F -- "--openclaw-service-mode" | grep -F "[default: user]"
AGENTBOX_OPENCLAW_SERVICE_MODE=user boot.sh --openclaw-service-mode system --help | grep -F -- "--openclaw-service-mode" | grep -F "[default: system]"
if AGENTBOX_OPENCLAW_SERVICE_MODE=user boot.sh --openclaw-service-mode system --help | grep -F "[default: user]"; then exit 1; fi

# should show openclaw identity input precedence
AGENTBOX_OPENCLAW_IDENTITY="Env Input Claw <envinput>" boot.sh --help | grep -F "Env Input Claw <envinput>"
AGENTBOX_OPENCLAW_IDENTITY="Env Input Claw <envinput>" boot.sh --openclaw-identity "Cli Input Claw <cliinput>" --help | grep -F "Cli Input Claw <cliinput>"
if AGENTBOX_OPENCLAW_IDENTITY="Env Input Claw <envinput>" boot.sh --openclaw-identity "Cli Input Claw <cliinput>" --help | grep -F "Env Input Claw <envinput>"; then exit 1; fi

# should show openclaw gateway onboarding defaults
boot.sh --help | grep -F -- "--openclaw-auth-choice" | grep -F "sets initial openclaw model auth choice"
boot.sh --help | grep -F -- "--openclaw-auth-choice" | grep -F "[default: skip]"
boot.sh --help | grep -F -- "--openclaw-auth-env" | grep -F "passes one extra parent env var to openclaw auth onboarding"
boot.sh --help | grep -F -- "--openclaw-auth-env" | grep -F "[default: none]"
boot.sh --help | grep -F -- "--openclaw-gateway-port" | grep -F "sets openclaw gateway port"
boot.sh --help | grep -F -- "--openclaw-gateway-port" | grep -F "[default: 18789]"
AGENTBOX_OPENCLAW_AUTH_CHOICE=openai-api-key boot.sh --help | grep -F -- "--openclaw-auth-choice" | grep -F "[default: openai-api-key]"
AGENTBOX_OPENCLAW_AUTH_ENV=ENV_OPENCLAW_API_KEY boot.sh --help | grep -F -- "--openclaw-auth-env" | grep -F "[default: ENV_OPENCLAW_API_KEY]"
AGENTBOX_OPENCLAW_AUTH_ENV=ENV_OPENCLAW_API_KEY boot.sh --openclaw-auth-env CLI_OPENCLAW_API_KEY --help | grep -F -- "--openclaw-auth-env" | grep -F "[default: CLI_OPENCLAW_API_KEY]"
if AGENTBOX_OPENCLAW_AUTH_ENV=ENV_OPENCLAW_API_KEY boot.sh --openclaw-auth-env CLI_OPENCLAW_API_KEY --help | grep -F "ENV_OPENCLAW_API_KEY"; then exit 1; fi
AGENTBOX_OPENCLAW_GATEWAY_PORT=18888 boot.sh --help | grep -F -- "--openclaw-gateway-port" | grep -F "[default: 18888]"

# should show openclaw gateway port input precedence
AGENTBOX_OPENCLAW_GATEWAY_PORT=18888 boot.sh --openclaw-gateway-port 19999 --help | grep -F -- "--openclaw-gateway-port" | grep -F "[default: 19999]"
if AGENTBOX_OPENCLAW_GATEWAY_PORT=18888 boot.sh --openclaw-gateway-port 19999 --help | grep -F "[default: 18888]"; then exit 1; fi

# should fail when openclaw identity is missing
set +e
output="$(boot.sh --openclaw-identity 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-identity requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw identity syntax is malformed
set +e
output="$(boot.sh --tailscale-authkey off --brewgroup off --openclaw-identity "Missing Shortname" 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw identity"
printf "%s\n" "$output" | grep -F "full name <shortname>"
test "$command_status" -ne 0

# should fail when openclaw auth choice is missing
set +e
output="$(boot.sh --openclaw-auth-choice 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-auth-choice requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw auth env is missing
set +e
output="$(boot.sh --openclaw-auth-env 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-auth-env requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw auth env is empty
set +e
output="$(boot.sh --openclaw-auth-env= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-auth-env must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when custom openclaw auth env name is invalid
set +e
output="$(FUTURE_OPENCLAW_API_KEY=test-value boot.sh \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-auth-choice future-api-key \
  --openclaw-auth-env future-openclaw-api-key \
  --openclaw-identity "Invalid Env Claw <invalidenv>" \
  2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw auth env future-openclaw-api-key must be a valid environment variable name."
test "$command_status" -ne 0

# should fail when custom openclaw auth env is used with skip auth
set +e
output="$(FUTURE_OPENCLAW_API_KEY=test-value boot.sh \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-auth-choice skip \
  --openclaw-auth-env FUTURE_OPENCLAW_API_KEY \
  --openclaw-identity "Skipped Env Claw <skippedenv>" \
  2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw auth env FUTURE_OPENCLAW_API_KEY requires an openclaw auth choice other than skip."
test "$command_status" -ne 0

# should fail when custom openclaw auth env is missing from the parent environment
set +e
output="$(env -u FUTURE_OPENCLAW_API_KEY boot.sh \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-auth-choice future-api-key \
  --openclaw-auth-env FUTURE_OPENCLAW_API_KEY \
  --openclaw-identity "Missing Env Claw <missingenv>" \
  2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw auth env FUTURE_OPENCLAW_API_KEY is not set in the parent environment"
printf "%s\n" "$output" | grep -F "https://docs.openclaw.ai/providers"
test "$command_status" -ne 0

# should fail when openai api-key auth is missing the provider env
set +e
output="$(env -u OPENAI_API_KEY boot.sh \
  --tailscale-authkey off \
  --brewgroup off \
  --openclaw-auth-choice openai-api-key \
  --openclaw-identity "Missing Key Claw <missingkey>" \
  2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw auth choice openai-api-key requires one of these parent environment variables"
printf "%s\n" "$output" | grep -F "OPENAI_API_KEY"
printf "%s\n" "$output" | grep -F "https://docs.openclaw.ai/providers"
test "$command_status" -ne 0

# should fail when openclaw gateway port is empty
set +e
output="$(boot.sh --openclaw-gateway-port= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-gateway-port must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw service mode is missing
set +e
output="$(boot.sh --openclaw-service-mode 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-service-mode requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw service mode is empty
set +e
output="$(boot.sh --openclaw-service-mode= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-service-mode must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw service mode is invalid
set +e
output="$(boot.sh --tailscale-authkey off --brewgroup off --openclaw-service-mode launch-agent 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw service mode launch-agent must be system or user."
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
