# agentbox

`agentbox` prepares a physically accessible macOS 26.x Mac to become a managed OpenClaw host. The
target scope is zero-to-running-gateway: base host setup, a non-sudo OpenClaw runner user, SSH access,
OpenClaw gateway onboarding, health verification, and host-level OpenClaw plugin installation.

Current releases perform the base host bootstrap and gateway bring-up: Homebrew packages, a
non-sudo OpenClaw runner user, classic SSH, optional Tailscale access, runner autologin, OpenClaw
gateway onboarding, an agentbox-owned gateway LaunchDaemon, and launchd-managed health checks.

Agent workspaces layer on top of the OpenClaw host. EMORI-specific setup, per-agent dotfiles,
project credentials, trading services, and application workloads remain outside the agentbox host
contract.

**What current releases do**

- Materializes this repo at `~/tanaab/agentbox` through the hosted `boot.sh` wrapper.
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
- Enables OpenClaw runner autologin by default.
- Enables classic SSH, installs optional authorized keys for the admin and OpenClaw runner users,
  ensures both users are allowed by macOS Remote Login access when that access group exists, and
  hardens sshd to key-only login when keys are provided.
- Installs Tailscale from Homebrew and optionally joins the tailnet.
- Runs gateway-only OpenClaw onboarding as the OpenClaw runner user.
- Installs an agentbox-owned system LaunchDaemon for the OpenClaw gateway.
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
- OpenClaw runner autologin may be blocked by FileVault or local macOS policy; pass
  `--skip-openclaw-autologin` when a GUI login session is not desired. Gateway supervision does not
  depend on autologin.

## Quickstart

Complete the [Manual Setup Checklist](#manual-setup-checklist) first, then run the hosted bootstrap
script on the Mac you are preparing:

```sh
curl -fsSL https://agentbox.boot.tanaab.sh/boot.sh | \
  AGENTBOX_OPENCLAW_PASSWORD="$OPENCLAW_PASSWORD" \
  AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" \
  AGENTBOX_HOSTNAME=TANAABAGENTBOX1 \
  bash
```

## Manual Setup Checklist

Before running `boot.sh`:

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
- Temporarily enable Remote Login only if you need SSH access before running `boot.sh`; the
  bootstrap enables classic SSH programmatically.
- Create or choose a preauthorized Tailscale auth key with any desired device tags, or decide to
  skip Tailscale setup.
- Optionally choose SSH public keys for `boot.sh` to install for the admin and OpenClaw runner
  users.

## Usage

For repeated use, install the hosted script as a local command in a directory you manage on `PATH`.

```sh
mkdir -p "$HOME/.local/bin"
curl -fsSL https://agentbox.boot.tanaab.sh/boot.sh -o "$HOME/.local/bin/agentbootbox"
chmod +x "$HOME/.local/bin/agentbootbox"

agentbootbox --help
```

Run it with flags when you want to keep the command explicit:

```sh
agentbootbox --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

Authorized keys are optional runtime inputs for classic SSH. When provided, `boot.sh` installs them
for the invoking admin user and the OpenClaw runner, then hardens SSH to key-only access for those
users. Supported values are public-key lines, explicit `file:` references, and existing public-key
paths:

```sh
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --authorized-key file:~/.ssh/id_ed25519.pub \
  --hostname TANAABAGENTBOX1

agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --authorized-key "ssh-ed25519 AAAA... user@example" \
  --authorized-key file:~/.ssh/backup.pub \
  --hostname TANAABAGENTBOX1
```

Use `--agentbox-version` to install a tagged release, local source checkout, or tar archive instead
of cloning the default branch:

```sh
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --agentbox-version 1.2.3 \
  --hostname TANAABAGENTBOX1

agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --agentbox-version https://api.github.com/repos/tanaabased/agentbox/tarball \
  --hostname TANAABAGENTBOX1

agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --agentbox-version ~/Downloads/agentbox-current.tar.gz \
  --hostname TANAABAGENTBOX1
```

The GitHub API tarball URL above resolves to the repository default branch when no `ref` is
provided. Archive installs require current agentbox contents, including root-level `bin/` and
`launchd/` runtime assets.

Use `--brewfile` to append extra Bootbox Brewfiles after the core agentbox `Brewfile`. Values can be
local paths or URLs. Relative local paths are resolved from the invocation directory first, then from
the materialized agentbox checkout:

```sh
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --brewfile Brewfile.extras \
  --hostname TANAABAGENTBOX1

agentbootbox \
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
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-identity "Agentbox OpenClaw <agentboxclaw>" \
  --hostname TANAABAGENTBOX1
```

Creating the runner, or enabling autologin for an existing runner, requires a password. Prefer the
environment variable so the password does not land in shell history:

```sh
AGENTBOX_OPENCLAW_PASSWORD="$OPENCLAW_PASSWORD" \
agentbootbox --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

agentbox never prints, persists, or generates the runner password. When run interactively without a
password and one is required, it prompts without echoing input. For newly created runners, agentbox
selects one bundled profile image. If the runner already exists, agentbox verifies that it is not an
admin user, preserves any existing profile picture, and does not reset the password.

OpenClaw runner autologin is enabled by default because the target host is expected to run a GUI
gateway session. Disable it when the box should not auto-login or when local macOS policy prevents
autologin:

```sh
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --skip-openclaw-autologin \
  --hostname TANAABAGENTBOX1
```

OpenClaw gateway onboarding is gateway-only by default: agentbox uses `--auth-choice skip`, skips
OpenClaw workspace bootstrap files and skill installation, and keeps gateway token auth enabled.
agentbox always binds the OpenClaw gateway to loopback. When Tailscale setup is enabled, agentbox
also asks OpenClaw to expose the loopback gateway through Tailscale Serve:

```sh
agentbootbox \
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
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-auth-choice openai-api-key \
  --hostname TANAABAGENTBOX1
```

agentbox does not use OpenClaw's macOS `--install-daemon` path. On macOS, that path installs a
per-user LaunchAgent that depends on a logged-in user session; agentbox instead installs a system
LaunchDaemon that runs `openclaw gateway` as the OpenClaw runner user.

The Homebrew prefix is made group-writable by `brewer` by default so the OpenClaw runner user or
other trusted local users can be granted package-management access through group membership. Use
`--brewgroup` to choose another group, or pass a falsey value to skip brewgroup setup:

```sh
agentbootbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup agentbrew --hostname TANAABAGENTBOX1
agentbootbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup off --hostname TANAABAGENTBOX1
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
agentbootbox --tailscale-authkey "$TS_AUTHKEY" --brewgroup brewer:staff --hostname TANAABAGENTBOX1
```

This is opt-in because it grants every current and future member of the trusted group write access
to the Homebrew prefix. Use it only on secured infrastructure hosts with restrictive network access,
SSH-key access, and trusted local account creation. Do not use it on shared workstations or machines
where unrelated local users may be added to the trusted group. agentbox creates the brewgroup when
missing, but the trusted group must already exist.

## Tailscale

Tailscale is the recommended remote access path, but it is not mandatory. When enabled, `boot.sh`
installs an agentbox-owned system LaunchDaemon for `tailscaled`, checks whether the Mac is already
joined, and only requires an auth key for a first join. The daemon is installed as
`/Library/LaunchDaemons/dev.tanaab.agentbox.tailscaled.plist` and runs as `root`; agentbox does not
use `brew services` as the Tailscale launchd wrapper. Its daemon state directory is
`/var/db/tanaab/agentbox/tailscale`.

To skip Tailscale setup, pass a falsey auth-key value:

```sh
agentbootbox --tailscale-authkey off --hostname TANAABAGENTBOX1
AGENTBOX_TAILSCALE_AUTHKEY=off agentbootbox --hostname TANAABAGENTBOX1
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
- `AGENTBOX_OPENCLAW_AUTOLOGIN` or `--skip-openclaw-autologin`: autologin is enabled by default;
  set a falsey environment value or pass the flag to disable it.
- `AGENTBOX_OPENCLAW_AUTH_CHOICE` or `--openclaw-auth-choice`: initial OpenClaw model auth choice;
  defaults to `skip`.
- `AGENTBOX_OPENCLAW_GATEWAY_PORT` or `--openclaw-gateway-port`: OpenClaw gateway port; defaults to
  `18789`.
- `AGENTBOX_OPENCLAW_IDENTITY` or `--openclaw-identity`: OpenClaw runner identity in
  `Full Name <shortname>` syntax; defaults to `A Tanaab-based Claw <openclaw>`.
- `AGENTBOX_OPENCLAW_PASSWORD` or `--openclaw-password`: password used only when creating the
  OpenClaw runner or enabling autologin; prefer the environment variable.
- `AGENTBOX_TAILSCALE_AUTHKEY` or `--tailscale-authkey`: Tailscale auth key for first join; use
  `off`, `false`, `no`, `0`, or `null` to skip Tailscale setup.
- `AGENTBOX_VERSION` or `--agentbox-version`: tagged agentbox release archive, local git checkout,
  HTTPS tar archive URL, or local `.tar`, `.tar.gz`, or `.tgz` archive path to install.
- `CI`: run in CI mode and disable prompts.
- `NONINTERACTIVE` or `--yes`: skip interactive prompts.

Run `boot.sh --help` for the exact current CLI and environment-variable contract.

## Verification

- Reboot the Mac and confirm it returns to the expected network state before any GUI login.
- Confirm the current agentbox health:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --check
```

Use `--report` for the same key-value report without failing on drift. When Tailscale is enabled,
the report should include `tailscaled_launchd_loaded_ok=1` and
`tailscaled_homebrew_launchd_absent_ok=1`, confirming the agentbox system daemon is loaded and the
legacy Homebrew launchd wrapper is not.

The report should also include `homebrew_login_path_file_ok=1`, `openclaw_cli_ok=1`, `node_cli_ok=1`,
and `ripgrep_ok=1`. agentbox does not pin `node@24`; the Homebrew `openclaw-cli` formula owns its
Node dependency.

The report should include `openclaw_gateway_launchd_loaded_ok=1`,
`openclaw_gateway_status_ok=1`, and `openclaw_gateway_ok=1`. The status check runs OpenClaw's
native `gateway status --require-rpc` command as the OpenClaw runner. It also prints
`openclaw_gateway_bind`, `openclaw_gateway_tailscale_mode`, and `openclaw_gateway_port`.
Tailscale-enabled hosts should report `openclaw_gateway_bind=loopback` and
`openclaw_gateway_tailscale_mode=serve`, `tailscale_magicdns_enabled=1`,
`tailscale_https_certificates_enabled=1`, and `openclaw_gateway_tailscale_serve_route_ok=1`;
hosts bootstrapped with Tailscale disabled should report `openclaw_gateway_bind=loopback` and
`openclaw_gateway_tailscale_mode=off`.

When brewgroup setup is enabled, the report should include `brewgroup_admin_user_ok=1` and
`brewgroup_openclaw_user_ok=1` plus `brew_prefix_ok=1`. The report should also include
`openclaw_user_ok=1`. If macOS exposes the `com.apple.access_ssh` Remote Login access group, the
report should include `ssh_access_admin_user_ok=1` and `ssh_access_openclaw_user_ok=1`; otherwise
those fields are `skipped`. When autologin is enabled, the report should include
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
./dist/boot.sh --help
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
