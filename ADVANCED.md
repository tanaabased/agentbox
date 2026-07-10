# Advanced

This file keeps the less common `agentbox` details out of the main README while preserving the deeper
operator reference. Start with [README.md](./README.md) for the main install path.

## What Gets Installed

### Dependencies

[`Brewfile`](./Brewfile) is the source of truth for core host packages. It installs the OpenClaw CLI,
`ripgrep`, Tailscale, and the supporting tools needed by the bootstrap. Homebrew `bin` and `sbin`
paths are published for login shells through `/etc/paths.d/00-agentbox-homebrew`.

[`Brewfile.extras`](./Brewfile.extras) is optional personal/operator tooling, not part of the core
host contract. Use it when you also want apps such as Codex, Codex App, OpenClaw, and Warp.

### System

`agentbox` applies the host-level macOS configuration before OpenClaw Gateway setup. It sets the system
identity, applies headless power, time, and recovery defaults, enables classic SSH, and installs
`/opt/tanaab/agentbox/bin/health.sh` with a periodic launchd health check and log output.

When authorized keys are provided, `agentbox` installs them for the invoking admin user and the
OpenClaw runner, then hardens managed SSH access to key-only login for those users. It also prepares
the non-admin OpenClaw runner account used by OpenClaw Gateway without granting that user sudo/admin
privileges.

### Tailscale

Tailscale setup is optional. When enabled, `agentbox` installs an `agentbox`-owned `tailscaled`
LaunchDaemon, joins the tailnet when needed, sets the OpenClaw runner as the Tailscale operator,
checks MagicDNS and HTTPS Certificate prerequisites, and writes a scoped macOS resolver file under
`/etc/resolver/<tailnet-suffix>`.

`agentbox` does not enable macOS Application Firewall; use Tailscale ACLs, no WAN port forwarding,
SSH hardening, and loopback gateway binding as the access-control boundary.

### OpenClaw

`agentbox` creates or reuses a non-admin OpenClaw runner user. The default identity is
`A Tanaab-based Claw <openclaw>`, where the value inside angle brackets is the macOS short username.
Newly created runners receive one bundled profile image from [`assets/`](./assets/).

OpenClaw Gateway onboarding is gateway-only by default: `agentbox` skips OpenClaw workspace bootstrap files,
skill installation, UI setup, hooks, and OpenClaw health checks, while keeping gateway token auth
enabled.

By default, `--openclaw-service-mode system` installs an `agentbox`-owned system LaunchDaemon that
runs `openclaw gateway` as the OpenClaw runner user. This is the recommended headless mode because it
does not require a GUI login session or autologin.

`--openclaw-service-mode user` delegates supervision to OpenClaw's native per-user service. On macOS
that service is a LaunchAgent and requires a logged-in user session, so `agentbox` enables OpenClaw
runner autologin in that mode. FileVault or local macOS policy may block autologin.

## Configuration Reference

The public configuration surface is intentionally small. CLI options override environment variables,
which override defaults. Prefer environment variables for secrets so they do not land in shell
history. Run `agentbox --help` for the exact current CLI and environment-variable contract.

### `--hostname`

| Field       | Value                                                                            |
| ----------- | -------------------------------------------------------------------------------- |
| Environment | `AGENTBOX_HOSTNAME`                                                              |
| Default     | `TANAABAGENTBOX1`                                                                |
| Values      | DNS-safe hostname                                                                |
| Description | Sets the macOS system hostname and the source value for the Tailscale node name. |

The configured hostname is used for macOS system identity. When Tailscale is enabled, a leading
`TANAAB` prefix is stripped for the Tailscale node name, so `TANAABAGENTBOX1` joins as `AGENTBOX1`.

If your tailnet uses another friendly DNS name, such as `tanaab.net`, verify the node is reachable
through that name as well as its Tailscale IP.

### `--authorized-key`

| Field       | Value                                                                      |
| ----------- | -------------------------------------------------------------------------- |
| Environment | `AGENTBOX_AUTHORIZED_KEY`, `AGENTBOX_AUTHORIZED_KEYS`                      |
| Default     | unset                                                                      |
| Values      | Public-key line, `file:` reference, or existing public-key path            |
| Description | Adds SSH public keys and enables key-only SSH hardening for managed users. |

Authorized keys are optional runtime inputs for classic SSH. When provided, `agentbox` installs them for
the invoking admin user and the OpenClaw runner, then hardens SSH to key-only access for those users.
Supported values are public-key lines, explicit `file:` references, and existing public-key paths:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --authorized-key file:~/.ssh/id_ed25519.pub \
  --hostname TANAABAGENTBOX1

agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --authorized-key "ssh-ed25519 AAAA... user@example" \
  --authorized-key file:~/.ssh/backup.pub \
  --hostname TANAABAGENTBOX1
```

Bad keys can lock out remote SSH, so keep physical or admin recovery access available until login is
verified.

If macOS exposes the `com.apple.access_ssh` Remote Login access group, `agentbox` ensures both the
invoking admin user and the OpenClaw runner are allowed by that group.

### `--brewfile`

| Field       | Value                                                                          |
| ----------- | ------------------------------------------------------------------------------ |
| Environment | `AGENTBOX_BREWFILE`, `AGENTBOX_BREWFILES`                                      |
| Default     | none                                                                           |
| Values      | Local path or URL; repeat the option or use comma-separated environment values |
| Description | Appends extra Brewfiles after the core `agentbox` `Brewfile`.                  |

Use `--brewfile` to append extra Bootbox Brewfiles after the core `agentbox` `Brewfile`. Values can be
local paths or URLs. Relative local paths are resolved from the invocation directory first, then from
the resolved `agentbox` payload:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --brewfile Brewfile.extras \
  --hostname TANAABAGENTBOX1

agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --brewfile https://raw.githubusercontent.com/example/profile/main/Brewfile \
  --hostname TANAABAGENTBOX1
```

[`Brewfile.extras`](./Brewfile.extras) is intentionally not part of the core host contract. It
installs personal operator apps: Codex, Codex App, OpenClaw, and Warp.

### `--openclaw-identity`

| Field       | Value                                                |
| ----------- | ---------------------------------------------------- |
| Environment | `AGENTBOX_OPENCLAW_IDENTITY`                         |
| Default     | `A Tanaab-based Claw <openclaw>`                     |
| Values      | `Full Name <shortname>`                              |
| Description | Chooses the non-admin local OpenClaw runner account. |

The OpenClaw runner defaults to `A Tanaab-based Claw <openclaw>`. Use `--openclaw-identity` to choose
another non-admin local account. The short name must be lowercase and macOS-safe:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-identity "Agentbox OpenClaw <agentboxclaw>" \
  --hostname TANAABAGENTBOX1
```

### `--openclaw-password`

| Field       | Value                                                                             |
| ----------- | --------------------------------------------------------------------------------- |
| Environment | `AGENTBOX_OPENCLAW_PASSWORD`                                                      |
| Default     | unset; prompts interactively when required                                        |
| Values      | Password for runner creation or `user` service autologin                          |
| Description | Supplies the OpenClaw runner password when `agentbox` cannot proceed without one. |

Creating the runner, or enabling user-service autologin for an existing runner, requires a password.
Prefer the environment variable so the password does not land in shell history:

```sh
AGENTBOX_OPENCLAW_PASSWORD="$OPENCLAW_PASSWORD" \
agentbox --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

When `agentbox` runs interactively without a password and one is required, it prompts without echoing
input.

`agentbox` preserves an existing runner profile picture and does not reset the password for an existing
runner.

### `--openclaw-service-mode`

| Field       | Value                                       |
| ----------- | ------------------------------------------- |
| Environment | `AGENTBOX_OPENCLAW_SERVICE_MODE`            |
| Default     | `system`                                    |
| Values      | `system`, `user`                            |
| Description | Chooses how OpenClaw Gateway is supervised. |

The OpenClaw Gateway service mode defaults to `system`. In `system` mode, `agentbox` runs OpenClaw
onboarding with native service installation disabled, then installs an `agentbox`-owned system
LaunchDaemon that runs `openclaw gateway` as the OpenClaw runner user:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-service-mode system \
  --hostname TANAABAGENTBOX1
```

This is the recommended headless mode because it does not require a GUI login session or autologin.
On rerun, `system` mode removes OpenClaw's native `ai.openclaw.gateway` user LaunchAgent if it is
present.

The shared `/var/log/tanaab/agentbox` directory remains `root:wheel` mode `0755`, while the gateway's
stdout and stderr files are owned by the OpenClaw runner and its primary group at mode `0600`.
Reruns repair those file permissions without truncating existing log contents.

Use `--openclaw-service-mode user` to delegate gateway supervision to OpenClaw's native per-user
service installer:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-service-mode user \
  --hostname TANAABAGENTBOX1
```

`agentbox` validates the `user` mode option wiring and records the selected mode in health output, but
`agentbox` CI does not run a full live `user` mode OpenClaw Gateway because GitHub-hosted macOS
runners do not provide the logged-in target-user GUI session required by macOS LaunchAgents.

On rerun, `user` mode removes the `agentbox`-owned system OpenClaw Gateway LaunchDaemon if it is
present.

#### System Service Environment

In `system` mode, the `agentbox` LaunchDaemon invokes an `agentbox`-generated wrapper and service
environment under `/Users/openclaw/.openclaw/service-env/`. That generated file is `agentbox`-owned
output and may be rewritten on rerun; do not use it for local customizations.

`agentbox`-managed LaunchDaemon plists include an `AgentboxVersion` metadata key for human-readable
inspection. Reruns compare rendered plist content before deciding whether an already loaded `agentbox`
service needs a launchd reload, so the metadata is informational rather than the refresh source of
truth.

The generated `system` mode service environment is aligned with OpenClaw's launcher markers:

```text
HOME
USER
LOGNAME
PATH
TMPDIR
NODE_EXTRA_CA_CERTS
NODE_USE_SYSTEM_CA
OPENCLAW_STATE_DIR
OPENCLAW_GATEWAY_PORT
OPENCLAW_LAUNCHD_LABEL
OPENCLAW_SERVICE_MARKER=openclaw
OPENCLAW_SERVICE_KIND=gateway
OPENCLAW_SERVICE_VERSION
```

`agentbox` also adds local integration markers:

```text
AGENTBOX_MANAGED=1
AGENTBOX_SERVICE_KIND=openclaw-gateway
AGENTBOX_VERSION
AGENTBOX_HEALTH_COMMAND=/opt/tanaab/agentbox/bin/health.sh --report
```

Use those markers only to detect the managed host or inspect its health. For durable user-provided
gateway runtime variables, prefer OpenClaw config or `/Users/openclaw/.openclaw/.env`.

### `--openclaw-gateway-port`

| Field       | Value                                 |
| ----------- | ------------------------------------- |
| Environment | `AGENTBOX_OPENCLAW_GATEWAY_PORT`      |
| Default     | `18789`                               |
| Values      | TCP port from `1` to `65535`          |
| Description | Sets the local OpenClaw Gateway port. |

OpenClaw Gateway onboarding is gateway-only by default: `agentbox` skips OpenClaw workspace bootstrap
files and skill installation, and keeps gateway token auth enabled. The configured port is passed to
OpenClaw onboarding and recorded in health state.

The OpenClaw Gateway always binds to loopback. When Tailscale setup is enabled, `agentbox` also asks
OpenClaw to expose that loopback service through Tailscale Serve:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-gateway-port 18789 \
  --hostname TANAABAGENTBOX1
```

See `--tailscale-authkey` for the Tailscale Serve prerequisites.

### `--openclaw-auth-choice`

| Field       | Value                                                  |
| ----------- | ------------------------------------------------------ |
| Environment | `AGENTBOX_OPENCLAW_AUTH_CHOICE`                        |
| Default     | `skip`                                                 |
| Values      | `skip` or an OpenClaw auth choice                      |
| Description | Selects initial model auth during OpenClaw onboarding. |

Pass `--openclaw-auth-choice` only when you want OpenClaw onboarding to configure initial model auth.
For example, OpenClaw can use provider-specific environment variables such as `OPENAI_API_KEY` when
the matching auth choice is selected:

```sh
OPENAI_API_KEY="$OPENAI_API_KEY" \
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-auth-choice openai-api-key \
  --hostname TANAABAGENTBOX1
```

For known environment-backed auth choices, `agentbox` requires the matching provider environment
variable in the parent process before sudo setup and passes it only to `openclaw onboard`. Debug
output masks the value. If the variable is missing, `agentbox` stops with the required env names and
OpenClaw provider docs before sudo bootstrap.

### `--openclaw-auth-env`

| Field       | Value                                                                     |
| ----------- | ------------------------------------------------------------------------- |
| Environment | `AGENTBOX_OPENCLAW_AUTH_ENV`                                              |
| Default     | unset                                                                     |
| Values      | One parent environment variable name                                      |
| Description | Passes one extra parent environment variable to OpenClaw auth onboarding. |

If OpenClaw adds a new environment-backed auth choice before `agentbox` knows its provider variable,
use `--openclaw-auth-env` with one parent environment variable name:

```sh
FUTURE_PROVIDER_API_KEY="$FUTURE_PROVIDER_API_KEY" \
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-auth-choice future-provider-api-key \
  --openclaw-auth-env FUTURE_PROVIDER_API_KEY \
  --hostname TANAABAGENTBOX1
```

This is only an auth-onboarding escape hatch. It does not configure runtime proxy, certificate, or
service environment variables.

### `--brewgroup`

| Field       | Value                                                   |
| ----------- | ------------------------------------------------------- |
| Environment | `AGENTBOX_BREWGROUP`                                    |
| Default     | `brewer`                                                |
| Values      | `brewgroup`, `brewgroup:trusted-group`, or falsey value |
| Description | Manages Homebrew prefix group write access.             |

The Homebrew prefix is made group-writable by `brewer` by default so the OpenClaw runner user or other
trusted local users can be granted package-management access through group membership. Use
`--brewgroup` to choose another group, or pass a falsey value to skip brewgroup setup:

```sh
agentbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup agentbrew --hostname TANAABAGENTBOX1
agentbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup off --hostname TANAABAGENTBOX1
```

When brewgroup setup is enabled, `agentbox` adds the invoking admin user to the configured brewgroup as
a direct member so the bootstrap account keeps write access to the Homebrew prefix. It also adds the
OpenClaw runner as a direct member so the runner can use the Homebrew-managed OpenClaw CLI and related
tools.

For controlled `agentbox` hosts, you may append a trusted nested group with
`--brewgroup brewgroup:trusted-group`. For example, `--brewgroup brewer:staff` keeps the Homebrew
prefix owned by `brewer`, but nests macOS `staff` into `brewer` so future local users in `staff`
inherit Homebrew prefix write access without being added one by one:

```sh
agentbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup brewer:staff --hostname TANAABAGENTBOX1
```

This is opt-in because it grants every current and future member of the trusted group write access to
the Homebrew prefix. Use it only on secured infrastructure hosts with restrictive network access,
SSH-key access, and trusted local account creation. Do not use it on shared workstations or machines
where unrelated local users may be added to the trusted group. `agentbox` creates the brewgroup when
missing, but the trusted group must already exist.

### `--tailscale-authkey`

| Field       | Value                                                           |
| ----------- | --------------------------------------------------------------- |
| Environment | `AGENTBOX_TAILSCALE_AUTHKEY`                                    |
| Default     | unset; required unless Tailscale is skipped or already joined   |
| Values      | Tailscale auth key, or `off`, `false`, `no`, `0`, `null`        |
| Description | Joins the Mac to Tailscale or explicitly skips Tailscale setup. |

To skip Tailscale setup, pass a falsey auth-key value:

```sh
agentbox --tailscale-authkey off --hostname TANAABAGENTBOX1
AGENTBOX_TAILSCALE_AUTHKEY=off agentbox --hostname TANAABAGENTBOX1
```

To tag newly joined machines, create or use a Tailscale auth key that applies the desired tags.
`agentbox` passes the auth key to `tailscale up` and does not manage tailnet tag policy itself.

When Tailscale is enabled, `agentbox` installs
`/Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist` and runs `tailscaled` as `root`.
`agentbox` does not use `brew services` as the Tailscale launchd wrapper. On rerun, it reloads the
daemon only when the rendered plist changed, and otherwise leaves the already loaded daemon running.
The daemon state directory is `/var/db/tanaab/agentbox/tailscale`.
Before loading its daemon, `agentbox` removes conflicting official CLI and Homebrew launchd wrappers
while preserving their binaries and state directories. A new join must persist
`/var/db/tanaab/agentbox/tailscale/tailscaled.state` and survive one managed daemon restart before
bootstrap continues. On rerun, `agentbox` resumes a stopped existing identity without a new auth key
and requires it to return to the expected hostname with backend state `Running` before continuing.

When Tailscale is enabled, `agentbox` sets the OpenClaw runner as the Tailscale operator so the
OpenClaw Gateway process can use native Tailscale Serve without sudo. Bootstrap fails if the tailnet
does not have MagicDNS and HTTPS Certificates enabled in
[Tailscale DNS settings](https://login.tailscale.com/admin/dns), or if the OpenClaw Gateway becomes
ready but the expected Tailscale Serve route is not configured. See Tailscale's
[MagicDNS](https://tailscale.com/docs/features/magicdns) and
[HTTPS certificate](https://tailscale.com/docs/how-to/set-up-https-certificates) docs for the
required tailnet settings.

`agentbox` also writes a macOS scoped resolver file for the tailnet MagicDNS suffix under
`/etc/resolver/`, pointing that suffix at Tailscale's local DNS resolver `100.100.100.100`.

`agentbox` does not enable macOS Application Firewall. When the OpenClaw Gateway is exposed through
Tailscale Serve, macOS Application Firewall can prevent Tailscale Serve HTTPS from reaching the
service over the tailnet. If the firewall is already enabled, `agentbox` prints a warning and
recommends disabling it for tailnet-hosted gateway access. Use Tailscale ACLs, no WAN port
forwarding, SSH hardening, and loopback gateway binding as the access-control boundary.

After joining, use the Tailscale admin console to confirm the node name, decide whether node key
expiry should be disabled for this infrastructure node, and keep ACLs restrictive.

### `--yes`

| Field       | Value                                             |
| ----------- | ------------------------------------------------- |
| Environment | `NONINTERACTIVE`                                  |
| Default     | off                                               |
| Values      | Any non-empty value                               |
| Description | Skips interactive prompts and runs with defaults. |

When `agentbox` runs interactively, OpenClaw can show its normal onboarding prompts for remaining
choices. When `CI`, `NONINTERACTIVE`, `--yes`, or a missing interactive terminal puts `agentbox` in
non-interactive mode, `agentbox` passes OpenClaw's non-interactive onboarding flags and explicit risk
acknowledgement.

### `--force`

| Field       | Value                                    |
| ----------- | ---------------------------------------- |
| Environment | `AGENTBOX_FORCE`                         |
| Default     | off                                      |
| Values      | Any non-empty value                      |
| Description | Allows supported replacement operations. |

Use this only when the current target is expected to be replaced by the bootstrap flow. It is not a
general reset flag.

### `--debug`

| Field       | Value                                   |
| ----------- | --------------------------------------- |
| Environment | `AGENTBOX_DEBUG`                        |
| Default     | off                                     |
| Values      | Any non-empty value                     |
| Description | Shows debug output with secrets masked. |

Debug output is meant for setup troubleshooting. It preserves token masking and does not print raw
OpenClaw runner passwords, Tailscale auth keys, or provider API keys.

### `CI`

| Field       | Value                                 |
| ----------- | ------------------------------------- |
| Environment | `CI`                                  |
| Default     | off                                   |
| Values      | Any non-empty value                   |
| Description | Runs in CI mode and disables prompts. |

## Verification Details

Use `--report` for the same line-oriented `key=value` report as `--check`, but without failing on
drift. The report includes:

```ini
agentbox_version=<version>
```

When Tailscale is enabled, the report should confirm the `agentbox` system daemon is loaded and the
legacy Homebrew launchd wrapper is not:

```ini
tailscaled_launchd_loaded_ok=1
tailscaled_launchd_running_ok=1
tailscaled_homebrew_launchd_absent_ok=1
tailscaled_official_launchd_absent_ok=1
tailscaled_state_file_ok=1
```

The report should also include the core dependency checks. `agentbox` does not pin `node@24`; the
Homebrew `openclaw-cli` formula owns its Node dependency.

```ini
homebrew_login_path_file_ok=1
openclaw_cli_ok=1
node_cli_ok=1
ripgrep_ok=1
```

For default system-mode installs, the report should include:

```ini
openclaw_service_mode=system
openclaw_gateway_launchd_loaded_ok=1
openclaw_gateway_launchd_running_ok=1
openclaw_gateway_log_permissions_ok=1
openclaw_gateway_status_ok=1
openclaw_gateway_ok=1
```

In `user` mode, the gateway check is based on OpenClaw's native `gateway status --require-rpc` check as
the OpenClaw runner:

```ini
openclaw_service_mode=user
openclaw_gateway_launchd_loaded_ok=skipped
openclaw_gateway_launchd_running_ok=skipped
openclaw_gateway_log_permissions_ok=skipped
openclaw_gateway_ok=1
openclaw_autologin_ok=1
```

Tailscale-enabled hosts should report:

```ini
openclaw_gateway_bind=loopback
openclaw_gateway_tailscale_mode=serve
tailscale_magicdns_enabled=1
tailscale_magicdns_resolver_ok=1
tailscale_https_certificates_enabled=1
openclaw_gateway_tailscale_serve_route_ok=1
```

Hosts bootstrapped with Tailscale disabled should report:

```ini
openclaw_gateway_bind=loopback
openclaw_gateway_tailscale_mode=off
```

When brewgroup setup is enabled, the report should include:

```ini
brewgroup_admin_user_ok=1
brewgroup_openclaw_user_ok=1
brew_prefix_ok=1
```

If trusted nesting is enabled, it should also include:

```ini
trusted_brewgroup_nested_ok=1
```

If macOS exposes the `com.apple.access_ssh` Remote Login access group, the report should include:

```ini
ssh_access_admin_user_ok=1
ssh_access_openclaw_user_ok=1
```

Otherwise those fields are `skipped`.

If authorized keys were provided, verify key-based SSH over Tailscale or LAN from another machine
before closing the local/admin recovery session:

```sh
ssh -o PreferredAuthentications=publickey <admin-user>@<tailscale-name-or-ip>
ssh -o PreferredAuthentications=publickey <openclaw-user>@<tailscale-name-or-ip>
```

To expose the configured filesystem group to other systems, use:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup
```

This prints the configured brewgroup without any trusted-group suffix, or `off` when brewgroup setup
was disabled.

Inspect listening ports and keep public exposure closed:

```sh
sudo lsof -iTCP -sTCP:LISTEN -n -P
```

## Payload Resolution

The macOS entrypoint resolves its `agentbox` payload automatically:

- If `AGENTBOX_PAYLOAD_DIR` is set, it must point to a current `agentbox` checkout or payload.
- When run from a source checkout, `macos.sh` uses the checkout beside the script.
- When run as a released hosted script, it fetches the matching release archive for the script version.

Release payloads provide the core Brewfile, health script, launchd templates, and profile assets. The
entrypoint does not clone the default branch as a fallback because that can pair an old script with
newer runtime files.
