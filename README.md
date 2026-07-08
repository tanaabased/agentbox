# agentbox

`agentbox` prepares a physically accessible macOS 26.x Mac to become a managed OpenClaw host. The
target scope is zero-to-running-gateway: base host setup, a non-sudo OpenClaw runner user, SSH access,
OpenClaw gateway onboarding, health verification, and host-level OpenClaw plugin installation.

Current releases perform the base host bootstrap and gateway bring-up: Homebrew packages, a
non-sudo OpenClaw runner user, classic SSH, optional Tailscale access, OpenClaw gateway onboarding,
configurable gateway service mode, and launchd-managed health checks.

Agent workspaces layer on top of the OpenClaw host. EMORI-specific setup, per-agent dotfiles,
project credentials, trading services, and application workloads remain outside the agentbox host
contract.

**What current releases do**

- Uses a release-matched or source-relative agentbox payload for the core Brewfile and runtime
  assets.
- Applies the repo [`Brewfile`](./Brewfile) through
  [Bootbox](https://github.com/tanaabased/bootbox).
- Can append extra local or URL Brewfiles, such as [`Brewfile.extras`](./Brewfile.extras), after
  the core host Brewfile.
- Installs the OpenClaw CLI and `ripgrep` as base host tools; OpenClaw CLI brings the
  Homebrew-managed Node runtime it needs.
- Exposes the Homebrew prefix `bin` and `sbin` directories to all login shells through
  `/etc/paths.d/00-agentbox-homebrew`.
- Makes the Homebrew prefix group-writable by the configured brewgroup.
- Creates or reuses a non-sudo OpenClaw runner user.
- Sets macOS system identity and headless power, time, and recovery defaults.
- Enables classic SSH, installs optional authorized keys for the admin and OpenClaw runner users,
  ensures both users are allowed by macOS Remote Login access when that access group exists, and
  hardens sshd to key-only login when keys are provided.
- Installs Tailscale from Homebrew and optionally joins the tailnet.
- Runs gateway-only OpenClaw onboarding as the OpenClaw runner user.
- Installs an agentbox-owned system LaunchDaemon for the OpenClaw gateway by default.
- Installs a launchd health check under `/opt/tanaab/agentbox`.

**What current releases do not yet do**

- Install host-level OpenClaw plugins.

**What remains out of scope**

- Configure EMORI or any other agent workspace as a special case.
- Install per-agent dotfiles, project credentials, trading services, or app-specific workloads.
- Configure Wi-Fi, Screen Sharing, Tailscale SSH, router port forwarding, or public WAN exposure.

**Caveats**

- Supports macOS 26.x on `x64` and `arm64`; newer major versions are blocked until validated.
- Requires a sudo-capable admin user.
- Designed for Mac hardware you physically control; Mac VPS behavior is unverified.
- Tailscale is recommended and enabled by default, but can be skipped with a falsey auth-key value.
- Authorized keys enable SSH key-only hardening for the admin and OpenClaw runner users. Bad keys
  can lock out remote SSH, so keep physical or admin recovery access available.
- `--openclaw-service-mode user` delegates gateway supervision to OpenClaw's native per-user
  service. On macOS, agentbox enables OpenClaw runner autologin for that mode so the user session
  can return after reboot. FileVault or local macOS policy may block autologin.

## Quickstart

Complete the [Manual Setup Checklist](#manual-setup-checklist) first, then run the hosted bootstrap
script on the Mac you are preparing:

```sh
curl -fsSL https://agentbox.boot.tanaab.sh/macos.sh | \
  AGENTBOX_OPENCLAW_PASSWORD="$OPENCLAW_PASSWORD" \
  AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" \
  AGENTBOX_HOSTNAME=TANAABAGENTBOX1 \
  bash
```

## Manual Setup Checklist

Before running `macos.sh`:

- Put the Mac somewhere ventilated, physically safe, and connected to power.
- Connect Ethernet and reserve its LAN IP in the router by MAC address.
- Do not add WAN port forwards for SSH, Screen Sharing, local services, or future app ports.
- Create the initial macOS admin account for human maintenance and recovery.
- Install macOS updates:

```sh
softwareupdate --list
sudo softwareupdate --install --all --restart
```

- Keep automatic/background security updates enabled in System Settings.
- Decide FileVault deliberately. macOS 26 on Apple silicon supports SSH unlock after restart when
  Remote Login and network connectivity are available, but physical recovery access is still the
  safest assumption for a headless agentbox.
- Consider installing an HDMI dummy plug / headless display adapter, such as
  [this example](https://www.amazon.com/dp/B0CKKLTWMN?ref=fed_asin_title), for smoother headless
  display behavior.
- Temporarily enable Remote Login only if you need SSH access before running `macos.sh`; the
  bootstrap enables classic SSH programmatically.
- Create or choose a preauthorized Tailscale auth key with any desired device tags, or decide to
  skip Tailscale setup.
- Optionally choose SSH public keys for `macos.sh` to install for the admin and OpenClaw runner
  users.

## Usage

For repeated use, install the hosted script as a local command in a directory you manage on `PATH`.

```sh
mkdir -p "$HOME/.local/bin"
curl -fsSL https://agentbox.boot.tanaab.sh/macos.sh -o "$HOME/.local/bin/agentbox"
chmod +x "$HOME/.local/bin/agentbox"

agentbox --help
```

Run it with flags when you want to keep the command explicit:

```sh
agentbox --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

Authorized keys are optional runtime inputs for classic SSH. When provided, `macos.sh` installs them
for the invoking admin user and the OpenClaw runner, then hardens SSH to key-only access for those
users. Supported values are public-key lines, explicit `file:` references, and existing public-key
paths:

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

`macos.sh` resolves its agentbox payload automatically. When run from a source checkout, it uses the
checkout beside the script. When run as a released hosted script, it fetches the matching release
archive for the script version and uses that payload for the core Brewfile, health script, launchd
templates, and profile assets. It does not clone the default branch as a fallback, because that can
pair an old script with newer runtime files.

Use `--brewfile` to append extra Bootbox Brewfiles after the core agentbox `Brewfile`. Values can be
local paths or URLs. Relative local paths are resolved from the invocation directory first, then from
the resolved agentbox payload:

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

`Brewfile.extras` is intentionally not part of the core host contract. It installs personal operator
apps: Codex, Codex App, OpenClaw, and Warp.

The OpenClaw runner defaults to `A Tanaab-based Claw <openclaw>`, where the value inside angle
brackets is the macOS short username. Use `--openclaw-identity` to choose another non-admin local
account. The short name must be lowercase and macOS-safe:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-identity "Agentbox OpenClaw <agentboxclaw>" \
  --hostname TANAABAGENTBOX1
```

Creating the runner, or enabling user-service autologin for an existing runner, requires a password.
Prefer the environment variable so the password does not land in shell history:

```sh
AGENTBOX_OPENCLAW_PASSWORD="$OPENCLAW_PASSWORD" \
agentbox --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

agentbox never prints, persists, or generates the runner password. When run interactively without a
password and one is required, it prompts without echoing input. For newly created runners, agentbox
selects one bundled profile image. If the runner already exists, agentbox verifies that it is not an
admin user, preserves any existing profile picture, and does not reset the password.

The OpenClaw gateway service mode defaults to `system`. In `system` mode, agentbox runs OpenClaw
onboarding with native service installation disabled, then installs an agentbox-owned system
LaunchDaemon that runs `openclaw gateway` as the OpenClaw runner user. This is the recommended
headless mode because it does not require a GUI login session or autologin. On rerun, `system` mode
removes OpenClaw's native `ai.openclaw.gateway` user LaunchAgent if it is present:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-service-mode system \
  --hostname TANAABAGENTBOX1
```

Use `--openclaw-service-mode user` to delegate gateway supervision to OpenClaw's native per-user
service installer. On macOS, that service is a LaunchAgent and requires a logged-in user session, so
agentbox configures OpenClaw runner autologin in `user` mode to preserve reboot behavior on headless
hosts. On rerun, `user` mode removes the agentbox-owned system gateway LaunchDaemon if it is
present:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-service-mode user \
  --hostname TANAABAGENTBOX1
```

agentbox validates the `user` mode option wiring and records the selected mode in health output, but
agentbox CI does not run a full live `user` mode gateway because GitHub-hosted macOS runners do not
provide the logged-in target-user GUI session required by macOS LaunchAgents. agentbox relies on
OpenClaw's supported native user-service path for that supervisor behavior.

OpenClaw gateway onboarding is gateway-only by default: agentbox uses `--auth-choice skip`, skips
OpenClaw workspace bootstrap files and skill installation, and keeps gateway token auth enabled.
agentbox keeps those gateway-only settings in both interactive and non-interactive runs. When
agentbox runs interactively, OpenClaw can show its normal onboarding prompts for the remaining
choices. When `CI`, `NONINTERACTIVE`, `--yes`, or a missing interactive terminal puts agentbox in
non-interactive mode, agentbox passes OpenClaw's non-interactive onboarding flags and explicit risk
acknowledgement. agentbox always binds the OpenClaw gateway to loopback. When Tailscale setup is
enabled, agentbox also asks OpenClaw to expose the loopback gateway through Tailscale Serve:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-gateway-port 18789 \
  --hostname TANAABAGENTBOX1
```

For the Tailscale Serve route, confirm that MagicDNS and HTTPS Certificates are enabled in the
Tailscale admin DNS settings. With those enabled, Tailscale serves the gateway through the node's
MagicDNS HTTPS name while OpenClaw itself remains bound to `127.0.0.1`. If either setting is off,
agentbox stops after Tailscale setup and asks you to enable them before it installs the OpenClaw
gateway.

Pass `--openclaw-auth-choice` only when you want OpenClaw onboarding to configure initial model
auth. For example, OpenClaw can use provider-specific environment variables such as
`OPENAI_API_KEY` when the matching auth choice is selected:

```sh
OPENAI_API_KEY="$OPENAI_API_KEY" \
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-auth-choice openai-api-key \
  --hostname TANAABAGENTBOX1
```

For known environment-backed auth choices, agentbox requires the matching provider environment
variable in the parent process before sudo setup and passes it only to `openclaw onboard`. Debug
output masks the value. If the variable is missing, agentbox stops with the required env names and
OpenClaw provider docs before sudo bootstrap.

If OpenClaw adds a new environment-backed auth choice before agentbox knows its provider variable,
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

In `system` mode, the agentbox LaunchDaemon invokes an agentbox-generated wrapper and service
environment under `/Users/openclaw/.openclaw/service-env/`. That generated file is agentbox-owned
output and may be rewritten on rerun; do not use it for local customizations.

agentbox-managed LaunchDaemon plists include an `AgentboxVersion` metadata key for human-readable
inspection. Reruns compare rendered plist content before deciding whether an already loaded
agentbox service needs a launchd reload, so the metadata is informational rather than the refresh
source of truth.

The generated `system` mode service environment is aligned with OpenClaw's launcher markers,
including `HOME`, `USER`, `LOGNAME`, `PATH`, `TMPDIR`, `NODE_EXTRA_CA_CERTS`,
`NODE_USE_SYSTEM_CA`, `OPENCLAW_STATE_DIR`, `OPENCLAW_GATEWAY_PORT`, `OPENCLAW_LAUNCHD_LABEL`,
`OPENCLAW_SERVICE_MARKER=openclaw`, `OPENCLAW_SERVICE_KIND=gateway`, and
`OPENCLAW_SERVICE_VERSION`. agentbox also adds `AGENTBOX_MANAGED=1`,
`AGENTBOX_SERVICE_KIND=openclaw-gateway`, `AGENTBOX_VERSION`, and
`AGENTBOX_HEALTH_COMMAND=/opt/tanaab/agentbox/bin/health.sh --report` for local integrations that
need to detect the managed host or inspect its health. For durable user-provided gateway runtime
variables, prefer OpenClaw config or `/Users/openclaw/.openclaw/.env`.

The Homebrew prefix is made group-writable by `brewer` by default so the OpenClaw runner user or
other trusted local users can be granted package-management access through group membership. Use
`--brewgroup` to choose another group, or pass a falsey value to skip brewgroup setup:

```sh
agentbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup agentbrew --hostname TANAABAGENTBOX1
agentbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup off --hostname TANAABAGENTBOX1
```

When brewgroup setup is enabled, agentbox adds the invoking admin user to the configured brewgroup
as a direct member so the bootstrap account keeps write access to the Homebrew prefix. It also adds
the OpenClaw runner as a direct member so the runner can use the Homebrew-managed OpenClaw CLI and
related tools.

For controlled agentbox hosts, you may append a trusted nested group with
`--brewgroup brewgroup:trusted-group`. For example, `--brewgroup brewer:staff` keeps the Homebrew
prefix owned by `brewer`, but nests macOS `staff` into `brewer` so future local users in `staff`
inherit Homebrew prefix write access without being added one by one:

```sh
agentbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup brewer:staff --hostname TANAABAGENTBOX1
```

This is opt-in because it grants every current and future member of the trusted group write access
to the Homebrew prefix. Use it only on secured infrastructure hosts with restrictive network access,
SSH-key access, and trusted local account creation. Do not use it on shared workstations or machines
where unrelated local users may be added to the trusted group. agentbox creates the brewgroup when
missing, but the trusted group must already exist.

## Tailscale

Tailscale is the recommended remote access path, but it is not mandatory. When enabled, `macos.sh`
installs an agentbox-owned system LaunchDaemon for `tailscaled`, checks whether the Mac is already
joined, and only requires an auth key for a first join. The daemon is installed as
`/Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist` and runs as `root`; agentbox does not
use `brew services` as the Tailscale launchd wrapper. On rerun, agentbox reloads the tailscaled
daemon when the rendered plist changed, and otherwise leaves the already loaded daemon running. Its
daemon state directory is `/var/db/tanaab/agentbox/tailscale`.

To skip Tailscale setup, pass a falsey auth-key value:

```sh
agentbox --tailscale-authkey off --hostname TANAABAGENTBOX1
AGENTBOX_TAILSCALE_AUTHKEY=off agentbox --hostname TANAABAGENTBOX1
```

The default hostname is `TANAABAGENTBOX1`. The configured hostname is used for macOS system
identity. When Tailscale is enabled, a leading `TANAAB` prefix is stripped for the Tailscale node
name, so `TANAABAGENTBOX1` joins as `AGENTBOX1`.

To tag newly joined machines, create or use a Tailscale auth key that applies the desired tags.
agentbox passes the auth key to `tailscale up` and does not manage tailnet tag policy itself.
When Tailscale is enabled, agentbox sets the OpenClaw runner as the Tailscale operator so
OpenClaw's gateway process can use native Tailscale Serve without sudo. Bootstrap fails if the
tailnet does not have MagicDNS and HTTPS Certificates enabled in
[Tailscale DNS settings](https://login.tailscale.com/admin/dns), or if the OpenClaw gateway becomes
ready but the expected Tailscale Serve route is not configured. See Tailscale's
[MagicDNS](https://tailscale.com/docs/features/magicdns) and
[HTTPS certificate](https://tailscale.com/docs/how-to/set-up-https-certificates) docs for the
required tailnet settings.
agentbox also writes a macOS scoped resolver file for the tailnet MagicDNS suffix under
`/etc/resolver/`, pointing that suffix at Tailscale's local DNS resolver `100.100.100.100`.

agentbox does not enable macOS Application Firewall. When the OpenClaw gateway is exposed through
Tailscale Serve, macOS Application Firewall can prevent Tailscale Serve HTTPS from reaching the
gateway over the tailnet. If the firewall is already enabled, agentbox prints a warning and
recommends disabling it for tailnet-hosted gateway access. Use Tailscale ACLs, no WAN port
forwarding, SSH hardening, and loopback gateway binding as the access-control boundary.

After joining, use the Tailscale admin console to confirm the node name, decide whether node key
expiry should be disabled for this infrastructure node, and keep ACLs restrictive.

If your tailnet uses another friendly DNS name, such as `tanaab.net`, verify the node is reachable
through that name as well as its Tailscale IP.

## Configuration

The public configuration surface is intentionally small. Prefer environment variables for secrets so
they do not land in shell history.

- `AGENTBOX_AUTHORIZED_KEY` or `--authorized-key`: optional public key or public-key file path for
  classic SSH; providing keys also enables key-only SSH hardening.
- `AGENTBOX_BREWFILE` or `--brewfile`: optional comma-separated extra Brewfile sources to append
  after the core agentbox `Brewfile`; accepts local paths and URLs.
- `AGENTBOX_BREWGROUP` or `--brewgroup`: Homebrew prefix group for write access; defaults to
  `brewer`; accepts `brewgroup:trusted-group` for opt-in nested trusted group access; use `off`,
  `false`, `no`, `0`, or `null` to skip brewgroup setup.
- `AGENTBOX_DEBUG` or `--debug`: show debug output with secrets masked.
- `AGENTBOX_FORCE` or `--force`: replace supported existing targets.
- `AGENTBOX_HOSTNAME` or `--hostname`: canonical macOS hostname and Tailscale hostname source.
- `AGENTBOX_OPENCLAW_AUTH_CHOICE` or `--openclaw-auth-choice`: initial OpenClaw model auth choice;
  defaults to `skip`.
- `AGENTBOX_OPENCLAW_AUTH_ENV` or `--openclaw-auth-env`: one extra parent environment variable name
  to pass to OpenClaw auth onboarding for env-backed auth choices not yet known to agentbox.
- `AGENTBOX_OPENCLAW_GATEWAY_PORT` or `--openclaw-gateway-port`: OpenClaw gateway port; defaults to
  `18789`.
- `AGENTBOX_OPENCLAW_IDENTITY` or `--openclaw-identity`: OpenClaw runner identity in
  `Full Name <shortname>` syntax; defaults to `A Tanaab-based Claw <openclaw>`.
- `AGENTBOX_OPENCLAW_PASSWORD` or `--openclaw-password`: password used only when creating the
  OpenClaw runner or enabling `user` service autologin; prefer the environment variable.
- `AGENTBOX_OPENCLAW_SERVICE_MODE` or `--openclaw-service-mode`: OpenClaw gateway supervision mode;
  `system` installs the agentbox system LaunchDaemon, while `user` delegates to OpenClaw's native
  per-user service and enables macOS autologin; defaults to `system`.
- `AGENTBOX_TAILSCALE_AUTHKEY` or `--tailscale-authkey`: Tailscale auth key for first join; use
  `off`, `false`, `no`, `0`, or `null` to skip Tailscale setup.
- `CI`: run in CI mode and disable prompts.
- `NONINTERACTIVE` or `--yes`: skip interactive prompts.

Run `macos.sh --help` for the exact current CLI and environment-variable contract.

## Verification

- Reboot the Mac and confirm it returns to the expected network state before any GUI login.
- Confirm the current agentbox health:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --check
```

Use `--report` for the same line-oriented `key=value` report without failing on drift. The report
includes `agentbox_version`. When Tailscale is enabled, it should include
`tailscaled_launchd_loaded_ok=1` and
`tailscaled_homebrew_launchd_absent_ok=1`, confirming the agentbox system daemon is loaded and the
legacy Homebrew launchd wrapper is not.

The report should also include `homebrew_login_path_file_ok=1`, `openclaw_cli_ok=1`, `node_cli_ok=1`,
and `ripgrep_ok=1`. agentbox does not pin `node@24`; the Homebrew `openclaw-cli` formula owns its
Node dependency.

The report should include `openclaw_service_mode=system`, `openclaw_gateway_launchd_loaded_ok=1`,
`openclaw_gateway_status_ok=1`, and `openclaw_gateway_ok=1` for default system-mode installs. In
`user` mode, `openclaw_gateway_launchd_loaded_ok` is `skipped` and `openclaw_gateway_ok` is based on
OpenClaw's native `gateway status --require-rpc` check as the OpenClaw runner. The report also
prints `openclaw_gateway_bind`, `openclaw_gateway_tailscale_mode`, and `openclaw_gateway_port`.
Tailscale-enabled hosts should report `openclaw_gateway_bind=loopback` and
`openclaw_gateway_tailscale_mode=serve`, `tailscale_magicdns_enabled=1`,
`tailscale_https_certificates_enabled=1`, and `openclaw_gateway_tailscale_serve_route_ok=1`;
hosts bootstrapped with Tailscale disabled should report `openclaw_gateway_bind=loopback` and
`openclaw_gateway_tailscale_mode=off`.

When brewgroup setup is enabled, the report should include `brewgroup_admin_user_ok=1` and
`brewgroup_openclaw_user_ok=1` plus `brew_prefix_ok=1`. The report should also include
`openclaw_user_ok=1`. If macOS exposes the `com.apple.access_ssh` Remote Login access group, the
report should include `ssh_access_admin_user_ok=1` and `ssh_access_openclaw_user_ok=1`; otherwise
those fields are `skipped`. When service mode is `user`, the report should include
`openclaw_autologin_ok=1`. If trusted nesting is enabled, it should also include
`trusted_brewgroup_nested_ok=1`. To expose the configured filesystem group to other systems, use:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --brewgroup
```

This prints the configured brewgroup without any trusted-group suffix, or `off` when brewgroup setup
was disabled.

- If authorized keys were provided, verify key-based SSH over Tailscale or LAN from another machine
  before closing the local/admin recovery session:

```sh
ssh -o PreferredAuthentications=publickey <admin-user>@<tailscale-name-or-ip>
ssh -o PreferredAuthentications=publickey <openclaw-user>@<tailscale-name-or-ip>
```

- Review the periodic health log:

```sh
tail -n 50 /var/log/tanaab/agentbox/health.log
```

- Inspect listening ports and keep public exposure closed:

```sh
sudo lsof -iTCP -sTCP:LISTEN -n -P
```

## Development

This repo uses Bun for repo-local tooling and publishes a Netlify-ready `dist/` directory.

```sh
git clone https://github.com/tanaabased/agentbox.git
cd agentbox
bun install
bun run lint
bun run build
bun run
./dist/macos.sh --help
```

Leia examples run in GitHub Actions on fresh macOS runners because the mutating scenarios configure
system settings, Homebrew packages, SSH, launchd, and Tailscale.

## Issues, Questions and Support

Use the [GitHub issue queue](https://github.com/tanaabased/agentbox/issues) for bugs, regressions,
or feature requests.

## Changelog

See [`CHANGELOG.md`](./CHANGELOG.md) for release history and
[GitHub releases](https://github.com/tanaabased/agentbox/releases) for published artifacts.

## Maintainers

- `@pirog`

## Contributors

<a href="https://github.com/tanaabased/agentbox/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=tanaabased/agentbox" />
</a>

Made with [contrib.rocks](https://contrib.rocks).
