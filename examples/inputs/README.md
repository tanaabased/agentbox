# Inputs Example

This example keeps lightweight coverage on the public `agentbox` input surface. It does not run the
bootstrap path; mutating setup coverage lives in the defaults, tailscale, homebrew, ssh, openclaw,
rerun, users-custom, users-existing, and source examples.

## Setup

```bash
# should have prepared agentbox on PATH
command -v agentbox >/dev/null
```

## Testing

```bash
# should show agentbox usage
agentbox --help | grep -F "Usage:"
agentbox --help | grep -F "[NONINTERACTIVE=1]"
agentbox --help | grep -F "[CI=1]"
agentbox --help | grep -F "[AGENTBOX_*...]"
agentbox --help | grep -F "agentbox [options]"

# should document brewfile options
agentbox --help | grep -F -- "--brewfile"
agentbox --help | grep -F "local path or url"

# should document host access options
agentbox --help | grep -F -- "--authorized-key"
agentbox --help | grep -F -- "--tailscale-authkey"
agentbox --help | grep -F -- "--brewgroup"
agentbox --help | grep -F -- "group[:trusted-group]"
agentbox --help | grep -F -- "--hostname"

# should document openclaw runner options
agentbox --help | grep -F -- "--openclaw-identity"
agentbox --help | grep -F -- "--openclaw-password"
agentbox --help | grep -F -- "--openclaw-auth-choice"
agentbox --help | grep -F -- "--openclaw-auth-env"
agentbox --help | grep -F -- "--openclaw-autologin"
agentbox --help | grep -F -- "--openclaw-gateway-port"

# should document operational options
agentbox --help | grep -F -- "--version"
agentbox --help | grep -F -- "--debug"
agentbox --help | grep -F -- "--force"
agentbox --help | grep -F -- "--openclaw-takeover-main"
agentbox --help | grep -F -- "--yes"

# should document brewfile environment variables
agentbox --help | grep -F "AGENTBOX_BREWFILE              same as --brewfile"

# should document host access environment variables
agentbox --help | grep -F "AGENTBOX_HOSTNAME              same as --hostname"
agentbox --help | grep -F "AGENTBOX_AUTHORIZED_KEY        same as --authorized-key"
agentbox --help | grep -F "AGENTBOX_TAILSCALE_AUTHKEY     same as --tailscale-authkey"
agentbox --help | grep -F "AGENTBOX_BREWGROUP             same as --brewgroup"

# should document openclaw runner environment variables
agentbox --help | grep -F "AGENTBOX_OPENCLAW_IDENTITY     same as --openclaw-identity"
agentbox --help | grep -F "AGENTBOX_OPENCLAW_PASSWORD     same as --openclaw-password"
agentbox --help | grep -F "AGENTBOX_OPENCLAW_AUTOLOGIN    same as --openclaw-autologin"
agentbox --help | grep -F "AGENTBOX_OPENCLAW_AUTH_CHOICE  same as --openclaw-auth-choice"
agentbox --help | grep -F "AGENTBOX_OPENCLAW_AUTH_ENV     same as --openclaw-auth-env"
agentbox --help | grep -F "AGENTBOX_OPENCLAW_GATEWAY_PORT same as --openclaw-gateway-port"
agentbox --help | grep -F "AGENTBOX_OPENCLAW_TAKEOVER_MAIN same as --openclaw-takeover-main"

# should document operational environment variables
agentbox --help | grep -F "AGENTBOX_FORCE                 same as --force"
agentbox --help | grep -F "NONINTERACTIVE                 same as --yes"
agentbox --help | grep -F "AGENTBOX_DEBUG                 same as --debug"
agentbox --help | grep -F "CI                             runs in CI mode and disables prompts"
if agentbox --help | grep -F -- "--ci"; then exit 1; fi

# should keep the unsupported macos override out of help
if agentbox --help | grep -F "AGENTBOX_ALLOW_UNSUPPORTED_MACOS"; then exit 1; fi

# should keep hidden payload controls out of help
if agentbox --help | grep -F -- "--agentbox-version"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_VERSION"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_PAYLOAD_DIR"; then exit 1; fi

# should keep hidden plural authorized-key inputs out of help
if agentbox --help | grep -F -- "--authorized-keys"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_AUTHORIZED_KEYS"; then exit 1; fi

# should keep hidden plural brewfile inputs out of help
if agentbox --help | grep -F -- "--brewfiles"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_BREWFILES"; then exit 1; fi

# should not expose abbreviated openclaw aliases
if agentbox --help | grep -F -- "--oc-"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_OC_"; then exit 1; fi

# should keep removed tailscale tag inputs out of help
if agentbox --help | grep -F -- "--tailscale-tag"; then exit 1; fi
if agentbox --help | grep -F -- "--tailscale-tags"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_TAILSCALE_TAG"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_TAILSCALE_TAGS"; then exit 1; fi

# should not expose dashed brewgroup aliases
if agentbox --help | grep -F -- "--brew-group"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_BREW_GROUP"; then exit 1; fi
if agentbox --help | grep -F -- "--trusted-brewgroup"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_TRUSTED_BREWGROUP"; then exit 1; fi

# should expose only the canonical openclaw autologin control
if agentbox --help | grep -F -- "--skip-openclaw-autologin"; then exit 1; fi
if agentbox --help | grep -F -- "--skip-openclaw-auto-login"; then exit 1; fi
agentbox --help | grep -F "AGENTBOX_OPENCLAW_AUTOLOGIN"
if agentbox --help | grep -F "AGENTBOX_OPENCLAW_AUTO_LOGIN"; then exit 1; fi

# should not expose skipped openclaw onboarding controls
if agentbox --help | grep -F -- "--skip-openclaw-onboarding"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_OPENCLAW_ONBOARDING"; then exit 1; fi

# should not expose secret passthrough controls
if agentbox --help | grep -F -- "--openclaw-secret-input-mode"; then exit 1; fi
if agentbox --help | grep -F "AGENTBOX_OPENCLAW_SECRET_INPUT_MODE"; then exit 1; fi

# should not expose removed legacy surfaces
if agentbox --help | grep -F -- "--op-token"; then exit 1; fi
if agentbox --help | grep -F -- "--ssh-key"; then exit 1; fi
if agentbox --help | grep -F -- "--me"; then exit 1; fi
if agentbox --help | grep -F -- "--tanaab"; then exit 1; fi
if agentbox --help | grep -F "PIROME"; then exit 1; fi
if agentbox --help | grep -F "OP_SERVICE_ACCOUNT_TOKEN"; then exit 1; fi
if agentbox --help | grep -F ".codex-plugin"; then exit 1; fi
if agentbox --help | grep -F "piroplugin"; then exit 1; fi

# should print a version string
test -n "$(agentbox --version)"

# should mask tailscale auth key defaults in help
AGENTBOX_TAILSCALE_AUTHKEY="tskey-secret-example" agentbox --help | grep -F "tske...mple"
if AGENTBOX_TAILSCALE_AUTHKEY="tskey-secret-example" agentbox --help | grep -F "tskey-secret-example"; then exit 1; fi

# should show falsey tailscale auth key values as disabled
AGENTBOX_TAILSCALE_AUTHKEY=off agentbox --help | grep -F "falsey disables setup"
AGENTBOX_TAILSCALE_AUTHKEY=off agentbox --help | grep -F "[default: disabled]"

# should show hostname input precedence
AGENTBOX_HOSTNAME=TANAABENVINPUT agentbox --help | grep -F "[default: TANAABENVINPUT]"
AGENTBOX_HOSTNAME=TANAABENVINPUT agentbox --hostname TANAABCLIINPUT --help | grep -F "[default: TANAABCLIINPUT]"
if AGENTBOX_HOSTNAME=TANAABENVINPUT agentbox --hostname TANAABCLIINPUT --help | grep -F "TANAABENVINPUT"; then exit 1; fi

# should show the default brewgroup value
agentbox --help | grep -F "[default: brewer]"

# should show disabled brewgroup input
AGENTBOX_BREWGROUP=off agentbox --help | grep -F "[default: disabled]"

# should show trusted brewgroup input
AGENTBOX_BREWGROUP=brewer:staff agentbox --help | grep -F "[default: brewer:staff]"

# should show extra brewfile input precedence
agentbox --help | grep -F -- "--brewfile                  adds an extra Brewfile from a local path or url [default: none]"
AGENTBOX_BREWFILE="Brewfile.extras,https://example.test/Brewfile" agentbox --help | grep -F "[default: Brewfile.extras,https://example.test/Brewfile]"
AGENTBOX_BREWFILE="Brewfile.env" agentbox --brewfile Brewfile.cli --help | grep -F "[default: Brewfile.cli]"
if AGENTBOX_BREWFILE="Brewfile.env" agentbox --brewfile Brewfile.cli --help | grep -F "Brewfile.env"; then exit 1; fi
AGENTBOX_BREWFILE="Brewfile.env" agentbox --brewfile= --help | grep -F "[default: none]"

# should show openclaw runner defaults without leaking passwords
agentbox --help | grep -F -- "--openclaw-identity         configures the openclaw runner as \"full name <shortname>\""
agentbox --help | grep -F "A Tanaab-based Claw <openclaw>"
agentbox --help | grep -F -- "--openclaw-password         sets the openclaw runner password"
agentbox --help | grep -F -- "[default: none]"
AGENTBOX_OPENCLAW_PASSWORD="secret-password" agentbox --help | grep -F -- "--openclaw-password         sets the openclaw runner password"
AGENTBOX_OPENCLAW_PASSWORD="secret-password" agentbox --help | grep -F "[default: provided]"
if AGENTBOX_OPENCLAW_PASSWORD="secret-password" agentbox --help | grep -F "secret-password"; then exit 1; fi
agentbox --help | grep -F -- "--openclaw-autologin        sets runtime-user autologin"
agentbox --help | grep -F -- "--openclaw-autologin" | grep -F "[default: on]"
AGENTBOX_OPENCLAW_AUTOLOGIN=off agentbox --help | grep -F -- "--openclaw-autologin" | grep -F "[default: off]"
AGENTBOX_OPENCLAW_AUTOLOGIN=off agentbox --openclaw-autologin on --help | grep -F -- "--openclaw-autologin" | grep -F "[default: on]"
if AGENTBOX_OPENCLAW_AUTOLOGIN=off agentbox --openclaw-autologin on --help | grep -F -- "--openclaw-autologin" | grep -F "[default: off]"; then exit 1; fi

# should show openclaw identity input precedence
AGENTBOX_OPENCLAW_IDENTITY="Env Input Claw <envinput>" agentbox --help | grep -F "Env Input Claw <envinput>"
AGENTBOX_OPENCLAW_IDENTITY="Env Input Claw <envinput>" agentbox --openclaw-identity "Cli Input Claw <cliinput>" --help | grep -F "Cli Input Claw <cliinput>"
if AGENTBOX_OPENCLAW_IDENTITY="Env Input Claw <envinput>" agentbox --openclaw-identity "Cli Input Claw <cliinput>" --help | grep -F "Env Input Claw <envinput>"; then exit 1; fi

# should show openclaw gateway onboarding defaults
agentbox --help | grep -F -- "--openclaw-auth-choice" | grep -F "sets initial openclaw model auth choice"
agentbox --help | grep -F -- "--openclaw-auth-choice" | grep -F "[default: skip]"
agentbox --help | grep -F -- "--openclaw-auth-env" | grep -F "passes one extra parent env var to openclaw auth onboarding"
agentbox --help | grep -F -- "--openclaw-auth-env" | grep -F "[default: none]"
agentbox --help | grep -F -- "--openclaw-gateway-port" | grep -F "sets openclaw gateway port"
agentbox --help | grep -F -- "--openclaw-gateway-port" | grep -F "[default: 18789]"
AGENTBOX_OPENCLAW_AUTH_CHOICE=openai-api-key agentbox --help | grep -F -- "--openclaw-auth-choice" | grep -F "[default: openai-api-key]"
AGENTBOX_OPENCLAW_AUTH_ENV=ENV_OPENCLAW_API_KEY agentbox --help | grep -F -- "--openclaw-auth-env" | grep -F "[default: ENV_OPENCLAW_API_KEY]"
AGENTBOX_OPENCLAW_AUTH_ENV=ENV_OPENCLAW_API_KEY agentbox --openclaw-auth-env CLI_OPENCLAW_API_KEY --help | grep -F -- "--openclaw-auth-env" | grep -F "[default: CLI_OPENCLAW_API_KEY]"
if AGENTBOX_OPENCLAW_AUTH_ENV=ENV_OPENCLAW_API_KEY agentbox --openclaw-auth-env CLI_OPENCLAW_API_KEY --help | grep -F "ENV_OPENCLAW_API_KEY"; then exit 1; fi
AGENTBOX_OPENCLAW_GATEWAY_PORT=18888 agentbox --help | grep -F -- "--openclaw-gateway-port" | grep -F "[default: 18888]"

# should show openclaw main takeover input precedence
agentbox --help | grep -F -- "--openclaw-takeover-main" | grep -F "[default: off]"
AGENTBOX_OPENCLAW_TAKEOVER_MAIN=1 agentbox --help | grep -F -- "--openclaw-takeover-main" | grep -F "[default: on]"
AGENTBOX_OPENCLAW_TAKEOVER_MAIN=off agentbox --openclaw-takeover-main --help | grep -F -- "--openclaw-takeover-main" | grep -F "[default: on]"

# should show openclaw gateway port input precedence
AGENTBOX_OPENCLAW_GATEWAY_PORT=18888 agentbox --openclaw-gateway-port 19999 --help | grep -F -- "--openclaw-gateway-port" | grep -F "[default: 19999]"
if AGENTBOX_OPENCLAW_GATEWAY_PORT=18888 agentbox --openclaw-gateway-port 19999 --help | grep -F "[default: 18888]"; then exit 1; fi

# should fail when openclaw identity is missing
set +e
output="$(agentbox --openclaw-identity 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-identity requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw identity syntax is malformed
set +e
output="$(agentbox --tailscale-authkey off --brewgroup off --openclaw-identity "Missing Shortname" 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw identity"
printf "%s\n" "$output" | grep -F "full name <shortname>"
test "$command_status" -ne 0

# should fail when openclaw auth choice is missing
set +e
output="$(agentbox --openclaw-auth-choice 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-auth-choice requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw auth env is missing
set +e
output="$(agentbox --openclaw-auth-env 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-auth-env requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw auth env is empty
set +e
output="$(agentbox --openclaw-auth-env= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-auth-env must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when custom openclaw auth env name is invalid
set +e
output="$(FUTURE_OPENCLAW_API_KEY=test-value agentbox \
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
output="$(FUTURE_OPENCLAW_API_KEY=test-value agentbox \
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
output="$(env -u FUTURE_OPENCLAW_API_KEY agentbox \
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
output="$(env -u OPENAI_API_KEY agentbox \
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

# should fail when removed agentbox version option is used
set +e
output="$(agentbox --agentbox-version 1.2.3 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "unrecognized option --agentbox-version"
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw gateway port is empty
set +e
output="$(agentbox --openclaw-gateway-port= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-gateway-port must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw autologin is missing
set +e
output="$(agentbox --openclaw-autologin 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-autologin requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw autologin is empty
set +e
output="$(agentbox --openclaw-autologin= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-autologin must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when openclaw autologin is invalid
set +e
output="$(agentbox --tailscale-authkey off --brewgroup off --openclaw-autologin sometimes 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "openclaw autologin sometimes must be on or off."
test "$command_status" -ne 0

# should fail when openclaw password value is empty
set +e
output="$(agentbox --openclaw-password= 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --openclaw-password must not be empty."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail when brewfile option values are missing
set +e
output="$(agentbox --brewfile 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "option --brewfile requires a value."
printf "%s\n" "$output" | grep -F "Usage:"
test "$command_status" -ne 0

# should fail on unknown options with usage context
set +e
output="$(agentbox --not-real 2>&1)"
command_status="$?"
set -e
printf "%s\n" "$output"
printf "%s\n" "$output" | grep -F "unrecognized option"
printf "%s\n" "$output" | grep -F "Usage:"
printf "%s\n" "$output" | grep -F "agentbox [options]"
test "$command_status" -ne 0
```
