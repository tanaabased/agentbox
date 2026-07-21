# Advanced

This file keeps the less common `agentbox` details out of the main README while preserving the deeper
operator reference. Start with [README.md](./README.md) for the main install path. For the optional
Codex plugin, see [CODEX.md](./CODEX.md).

## Preflight Checks

Complete these checks before following the [Quickstart](./README.md#quickstart):

- Put the Mac somewhere ventilated, physically safe, and connected to power.
- Use Mac hardware you physically control; Mac VPS behavior is unverified.
- Connect Ethernet and reserve its LAN IP in the router by MAC address.
- Do not add WAN port forwards for SSH, Screen Sharing, local services, or future app ports.
- Create the initial macOS admin account for human maintenance and recovery.
- Temporarily enable Remote Login only if you need SSH access before running `agentbox`; the bootstrap
  enables classic SSH programmatically.
- Install all macOS updates:

```sh
softwareupdate --list
sudo softwareupdate --install --all --restart
```

- Keep automatic/background security updates enabled in System Settings.
- Choose the operating profile deliberately: FileVault with manual runtime-user login, or FileVault
  disabled with default autologin for unattended Gateway recovery. `agentbox` does not promise both.
- Consider installing an [HDMI dummy plug or headless display adapter](https://www.amazon.com/dp/B0CKKLTWMN?ref=fed_asin_title)
  for smoother headless display behavior.
- Create or choose a preauthorized Tailscale auth key with any desired device tags, or decide to skip
  Tailscale setup.
- Confirm MagicDNS and HTTPS Certificates are enabled in
  [Tailscale DNS settings](https://login.tailscale.com/admin/dns) when the OpenClaw Gateway should be
  exposed through Tailscale Serve.
- Optionally choose SSH public keys for `agentbox` to install for the admin and OpenClaw runner users.

## What Gets Installed

### Dependencies

[`Brewfile`](./Brewfile) is the source of truth for core host packages. It installs the OpenClaw CLI,
`ripgrep`, Tailscale, and the supporting tools needed by the bootstrap. Homebrew `bin` and `sbin`
paths are published for login shells through `/etc/paths.d/00-agentbox-homebrew`.

The host Brewfile does not pin a `node@24` formula. The Homebrew `openclaw-cli` formula owns its Node
dependency; the repository's Node tool version is for development rather than the installed host
package contract.

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

OpenClaw Gateway runs only as OpenClaw's native per-user LaunchAgent. Because macOS creates the
`gui/<uid>` launchd domain only for a logged-in user, `agentbox` enables runtime-user autologin by
default. After a normal reboot, macOS logs in the dedicated non-admin runner and the native Gateway
returns without operator intervention.

Autologin reduces physical-access security. FileVault prevents unattended autologin after a cold
boot, so `agentbox` stops before mutation when both are requested. Use `--openclaw-autologin off`
only when manual graphical login after every reboot or logout is acceptable.

#### Dashboard Access

When logged in directly as the OpenClaw runner, open the authenticated Dashboard with:

```sh
openclaw dashboard
```

From an admin account, run the same command as the runner. The default runner command is:

```sh
sudo -iu openclaw "$(brew --prefix)/bin/openclaw" dashboard
```

Replace `openclaw` with the configured runner short name when using a custom identity. `agentbox`
also prints the fully resolved command after a successful setup. OpenClaw normally opens the
Dashboard and copies its authenticated URL without printing the gateway token.

To copy the authenticated URL without opening a browser, add `--no-open`:

```sh
sudo -iu openclaw "$(brew --prefix)/bin/openclaw" dashboard --no-open
```

Copying may be unavailable in a purely headless or SSH-only session. In that case, OpenClaw does not
print the hidden token as a fallback. `openclaw config get gateway.auth.token` also intentionally
returns a redacted value. See the [OpenClaw Dashboard documentation](https://docs.openclaw.ai/cli/dashboard)
for the upstream command behavior.

When Tailscale Serve is enabled, `agentbox` keeps gateway token authentication enabled and explicitly
sets `gateway.auth.allowTailscale` to `true` in the runner-owned configuration. Open the remote
Dashboard at the agentbox MagicDNS HTTPS address. Each additional browser profile or device must
complete its own OpenClaw authorization flow; enter the gateway token in the Dashboard connection
settings when prompted. Repeat this after clearing that browser's site data or when using another
browser profile.

If the authenticated Dashboard command cannot transfer the token to the remote device, an admin can
deliberately reveal the runner-owned token with the following command. Replace `openclaw` with the
configured runner short name, and treat the output as a secret:

```sh
sudo jq -r '.gateway.auth.token' /Users/openclaw/.openclaw/openclaw.json
```

#### Reruns and Later OpenClaw Configuration

On first setup, interactive `agentbox` runs let OpenClaw show its normal onboarding flow. On a later
run, `agentbox` asks OpenClaw to validate the runner configuration and read `gateway.mode`. When the
configuration is valid and the gateway mode is `local`, `agentbox` reconciles its managed gateway
settings through OpenClaw's non-interactive onboarding path instead of reopening the wizard. Missing,
invalid, or non-local configuration keeps the normal onboarding path so repair remains visible.

Use OpenClaw's native configuration flow for targeted changes after setup. The default runner command
is:

```sh
sudo -iu openclaw "$(brew --prefix)/bin/openclaw" configure
```

Replace `openclaw` with the configured runner short name when using a custom identity. To deliberately
run the complete OpenClaw onboarding flow again, use `onboard --classic` as that runner:

```sh
sudo -iu openclaw "$(brew --prefix)/bin/openclaw" onboard --classic
```

Full OpenClaw onboarding can change gateway or service choices. Rerun `agentbox` afterward to
reconcile native LaunchAgent activation, loopback bind, gateway port, and Tailscale exposure.

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
| Values      | Password for runner creation or runtime-user autologin                            |
| Description | Supplies the OpenClaw runner password when `agentbox` cannot proceed without one. |

Creating the runner, or enabling autologin for an existing runner, requires a password.
Prefer the environment variable so the password does not land in shell history:

```sh
AGENTBOX_OPENCLAW_PASSWORD="$OPENCLAW_PASSWORD" \
agentbox --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

When `agentbox` runs interactively without a password and one is required, it prompts without echoing
input.

`agentbox` preserves an existing runner profile picture and does not reset the password for an existing
runner.

### `--openclaw-autologin`

| Field       | Value                                                         |
| ----------- | ------------------------------------------------------------- |
| Environment | `AGENTBOX_OPENCLAW_AUTOLOGIN`                                 |
| Default     | `on`                                                          |
| Values      | `on`, `off`                                                   |
| Description | Controls unattended runtime-user login after a normal reboot. |

The native `ai.openclaw.gateway` LaunchAgent is the only supported macOS Gateway service. With the
default `on` policy, `agentbox` configures the dedicated non-admin runner as the macOS autologin user.
If FileVault is enabled, or local policy prevents `sysadminctl` from applying autologin, setup stops
instead of claiming unattended recovery.

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-autologin on \
  --hostname TANAABAGENTBOX1
```

Autologin lowers physical-access security because anyone at the Mac can reach the runner's logged-in
desktop. The runner remains non-admin, but this does not replace physical security. `off` is the
alternative for FileVault or stricter login-window policy:

```sh
agentbox --openclaw-autologin off --hostname TANAABAGENTBOX1
```

With `off`, a graphical runner login is required after every reboot and after explicitly logging the
runner out. Fast User Switching is supported because it keeps the runner's Aqua session alive; a
full logout stops its LaunchAgents.

#### First-login activation

Onboarding always uses `--no-install-daemon --skip-health`. `agentbox` then installs an Aqua-only,
one-time finalizer at:

- `~/.local/libexec/agentbox-openclaw-finalize`
- `~/Library/LaunchAgents/dev.tanaab.agentbox.openclaw-finalize.plist`
- `~/.agentbox/openclaw-gateway-finalizer-state`
- `~/Library/Logs/agentbox/openclaw-finalize.log`

Before staging a Gateway it owns, `agentbox` writes `OPENCLAW_MDNS_HOSTNAME` and its non-secret
ownership metadata to the runner's private `~/.openclaw/.env`. OpenClaw copies those durable values
into its generated native service environment. A healthy native Gateway without the agentbox
ownership markers is preserved without changing its environment or restarting it.

If the runner's GUI domain already exists, setup runs the finalizer immediately and waits up to 90
seconds. Otherwise setup succeeds with `openclaw_gateway_state=pending_first_login`; the next reboot
or graphical login completes installation. The finalizer removes its own plist only after the native
LaunchAgent is loaded and RPC health succeeds. On failure it retains the plist, state, and logs for
the next retry. After installation, the native Gateway runtime log is
`~/Library/Logs/openclaw/gateway.log`; finalizer logs cover only activation and retry work.

#### Migration and rollback

Reruns stop and archive the retired `dev.tanaab.agentbox.openclaw-gateway` system job and its private
service environment under `/var/db/tanaab/agentbox/migrations/`, with root-only permissions. A
conflicting invoking-admin native Gateway is uninstalled after a timestamped backup of the admin's
`~/.openclaw`; non-conflicting admin state is preserved and configured for attach-only access.

If an unexpected process owns the configured Gateway port, `agentbox` reports its PID and owner and
stops without killing it. To roll back a migration, first stop the native runner Gateway, inspect the
retained backup, and deliberately restore the archived files; automatic rollback to the retired
system-service model is not supported.

Messages sign-in and macOS TCC/Automation authorization remain manual. Autologin and Gateway
activation do not grant Messages, Full Disk Access, or Apple Events permissions.

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

The preferred guided verification path is `$tanaab-agentbox-doctor`, which runs on the local host,
groups the installed health checks, and recommends focused remediation without applying it. See the
[Codex plugin guide](./CODEX.md#diagnose-host-health) for the workflow and example prompt.

The installed `/opt/tanaab/agentbox/bin/health.sh` remains the authoritative health contract for the
host version. Use `--check` to print its line-oriented `key=value` report and return nonzero when a
required check fails:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --check
```

Use `--report` to print the same report without propagating health failures through the command exit
status:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --report
```

`openclaw_gateway_activation_ok` is the primary Gateway readiness leaf. The accompanying
`openclaw_gateway_state` explains whether activation is `not_configured`, `pending_first_login`,
`installing`, `healthy`, `failed`, `gui_session_inactive`, `legacy_system_service_detected`, or
`duplicate_gateway_detected`. A deliberately staged first login is a successful bootstrap outcome,
but strict health remains pending until the native Gateway is healthy.

For agentbox-managed Gateways, health also verifies the mDNS hostname and agentbox ownership
metadata in OpenClaw's generated service environment. Native Gateway log ownership and permissions
are checked after the LaunchAgent is installed. Unmanaged healthy native Gateways report the managed
environment checks as `skipped`.

Downstream `tnab running` adoption is separate work: it should consume
`openclaw_gateway_activation_ok` and `openclaw_gateway_state` instead of retired system-service
fields.

Health ends with `agentbox_ok=1` when all required checks pass and `agentbox_ok=0` when required drift
is present. Individual checks may be `skipped` when their feature is inactive.

Review the periodic health log when investigating when drift first appeared:

```sh
tail -n 50 /var/log/tanaab/agentbox/health.log
```

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

Release payloads provide the core Brewfile, health script, launchd templates, Aqua finalizer, and
profile assets. The entrypoint does not clone the default branch as a fallback because that can pair
an old script with newer runtime files.
