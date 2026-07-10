# `agentbox`

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./assets/agentbox-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="./assets/agentbox-light.png" />
    <img src="./assets/agentbox-light.png" alt="agentbox" width="180" />
  </picture>
</p>

<p align="center">
  <a href="https://github.com/tanaabased/agentbox/releases"><img src="https://img.shields.io/github/v/release/tanaabased/agentbox?include_prereleases&sort=semver" alt="Latest release" /></a>
  <a href="https://app.netlify.com/projects/tanaab-agentbox-sh/deploys"><img src="https://api.netlify.com/api/v1/badges/0c4b2bbf-7d25-417f-9af0-940249cd7e2c/deploy-status" alt="Netlify Status" /></a>
  <img src="https://img.shields.io/badge/macOS-26.x-111827" alt="macOS 26.x" />
  <img src="https://img.shields.io/badge/OpenClaw-host-00c88a" alt="OpenClaw host" />
</p>

`agentbox` prepares a Mac to become a managed, headless OpenClaw host, optionally connected to your
[Tailscale](https://tailscale.com/) tailnet. Its goal is to take a fresh box from zero to a running
OpenClaw Gateway with reasonable security defaults and a host ready for agent workspaces.

> Supports macOS 26.x on `x64` and `arm64`.
> Requires a sudo-capable admin user and physical or admin recovery access.
> Best run on a fresh Mac dedicated to the OpenClaw host role.
>
> **Platform note:** Linux and Windows are not supported yet; Linux support is planned.

## Overview

At a high level, `agentbox`:

- installs [Homebrew](https://brew.sh/) and core dependencies from [`Brewfile`](./Brewfile)
- creates or reuses a non-admin OpenClaw runner user
- sets macOS system identity and headless power, time, and recovery defaults
- enables classic SSH
- launches OpenClaw Gateway in `system` or `user` service mode
- installs health checks and logs for post-bootstrap verification
- optionally installs SSH public keys and hardens SSH to key-only access
- optionally runs a managed `tailscaled` daemon and connects the Mac to a tailnet
- optionally configures initial OpenClaw model auth

For a more complete look at installed components, see
[ADVANCED.md#what-gets-installed](./ADVANCED.md#what-gets-installed).

## Quickstart

Complete the [Manual Setup Checklist](#manual-setup-checklist) first, then run the hosted bootstrap on
the Mac you are preparing:

```sh
/bin/bash -c "$(curl -fsSL https://agentbox.tanaab.sh/macos.sh)" agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-identity "A Tanaab-based Claw <openclaw>" \
  --openclaw-password "$OPENCLAW_PASSWORD"
```

The OpenClaw runner password is used only when creating the runner account or enabling the optional
user service mode. `agentbox` never prints, persists, generates, or debug-logs that password.

For the complete option and environment-variable contract, run:

```sh
/bin/bash -c "$(curl -fsSL https://agentbox.tanaab.sh/macos.sh)" agentbox --help
```

## Usage

For repeated use, install the hosted script as a local command in a directory you manage on `PATH`:

```sh
mkdir -p "$HOME/.local/bin"
curl -fsSL https://agentbox.tanaab.sh/macos.sh -o "$HOME/.local/bin/agentbox"
chmod +x "$HOME/.local/bin/agentbox"

agentbox --help
```

Run it with flags when you want to keep the command explicit:

```sh
agentbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --openclaw-password "$OPENCLAW_PASSWORD" \
  --hostname TANAABAGENTBOX1
```

Common inputs:

| Option                    | Environment variable             | Description                                                                                          |
| ------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `--hostname`              | `AGENTBOX_HOSTNAME`              | macOS hostname and Tailscale hostname source.                                                        |
| `--tailscale-authkey`     | `AGENTBOX_TAILSCALE_AUTHKEY`     | Tailscale auth key for first join; use `off`, `false`, `no`, `0`, or `null` to skip Tailscale setup. |
| `--authorized-key`        | `AGENTBOX_AUTHORIZED_KEY`        | Public SSH key or public-key file path; providing keys also enables key-only SSH hardening.          |
| `--openclaw-password`     | `AGENTBOX_OPENCLAW_PASSWORD`     | Password used only for OpenClaw runner creation or user-service autologin.                           |
| `--openclaw-identity`     | `AGENTBOX_OPENCLAW_IDENTITY`     | OpenClaw runner identity in `Full Name <shortname>` syntax.                                          |
| `--openclaw-service-mode` | `AGENTBOX_OPENCLAW_SERVICE_MODE` | OpenClaw Gateway supervision mode: `system` or `user`; defaults to `system`.                         |
| `--openclaw-auth-choice`  | `AGENTBOX_OPENCLAW_AUTH_CHOICE`  | Initial OpenClaw model auth choice; defaults to `skip`.                                              |
| `--brewfile`              | `AGENTBOX_BREWFILE`              | Extra Brewfile sources to append after the core `agentbox` Brewfile.                                 |
| `--yes`                   | `NONINTERACTIVE`                 | Skip interactive prompts.                                                                            |
| `--debug`                 | `AGENTBOX_DEBUG`                 | Show debug output with secrets masked.                                                               |

Use [ADVANCED.md](./ADVANCED.md) for the full option guide, payload-resolution details, brewgroup
behavior, OpenClaw auth environment handling, and deeper Tailscale notes.

On rerun, `agentbox` reconciles an existing valid local OpenClaw gateway configuration
non-interactively instead of reopening the onboarding wizard. See
[OpenClaw reruns and later configuration](./ADVANCED.md#reruns-and-later-openclaw-configuration).

## Manual Setup Checklist

Before running `agentbox`:

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
- Decide FileVault deliberately. macOS 26 on Apple silicon supports SSH unlock after restart when
  Remote Login and network connectivity are available, but physical recovery access is still the
  safest assumption for a headless `agentbox`.
- Consider installing an [HDMI dummy plug or headless display adapter](https://www.amazon.com/dp/B0CKKLTWMN?ref=fed_asin_title)
  for smoother headless display behavior.
- Create or choose a preauthorized Tailscale auth key with any desired device tags, or decide to skip
  Tailscale setup.
- Confirm MagicDNS and HTTPS Certificates are enabled in
  [Tailscale DNS settings](https://login.tailscale.com/admin/dns) when the OpenClaw Gateway should be
  exposed through Tailscale Serve.
- Optionally choose SSH public keys for `agentbox` to install for the admin and OpenClaw runner users.

## Verification

At the end of setup, `agentbox` prints a concise health success or failure status. A failed health
check exits nonzero and prints the report command below; `--debug` includes the full health report in
the setup output.

Reboot the Mac and confirm it returns to the expected network state before any GUI login. Then use
the installed health script to check or report host state:

```sh
sudo /opt/tanaab/agentbox/bin/health.sh --check
sudo /opt/tanaab/agentbox/bin/health.sh --report
```

Review the periodic health log when investigating drift:

```sh
tail -n 50 /var/log/tanaab/agentbox/health.log
```

See [ADVANCED.md#verification-details](./ADVANCED.md#verification-details) for health-report field
interpretation and additional post-bootstrap checks.

## Development

This repo uses Bun for repo-local tooling and publishes a Netlify-ready `dist/` directory.

```sh
git clone https://github.com/tanaabased/agentbox.git
cd agentbox
bun install
bun run lint
```

`bun run build` regenerates `dist/` for release-shaped verification. Local agents should not run it
or edit `dist/` unless the task explicitly requires generated output.

Leia examples run in GitHub Actions on fresh macOS runners because the mutating scenarios configure
system settings, Homebrew packages, SSH, launchd, and Tailscale.

## Issues, Questions and Support

Use the [GitHub issue queue](https://github.com/tanaabased/agentbox/issues) for bugs, regressions, or
feature requests.

## Changelog

See [`CHANGELOG.md`](./CHANGELOG.md) for release history and
[GitHub releases](https://github.com/tanaabased/agentbox/releases) for published artifacts.

## Maintainers

- [@pirog](https://github.com/pirog)

## Contributors

<a href="https://github.com/tanaabased/agentbox/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=tanaabased/agentbox" />
</a>

Made with [contrib.rocks](https://contrib.rocks).
