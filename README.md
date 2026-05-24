# agentbox

`agentbox` configures a physically accessible macOS 26+ Mac for headless operation on Tailscale,
with classic SSH and launchd-managed base services ready for future agent hosting.

The hosted `boot.sh` wrapper installs the base tooling it needs, materializes this repo at
`~/tanaab/agentbox`, applies the repo [`Brewfile`](./Brewfile) through
[Bootbox](https://github.com/tanaabased/bootbox), and runs the agentbox setup flow.

> Supports macOS 26 or newer on `x64` and `arm64`. Requires a sudo-capable admin user and a
> Tailscale auth key. Designed for Mac hardware you physically control; Mac VPS behavior is
> unverified.

## Quickstart

Complete the Manual Setup Checklist first, then use the hosted bootstrap script when preparing a
real machine:

```sh
curl -fsSL https://agentbox.boot.tanaab.sh/boot.sh | \
  AGENTBOX_TAILSCALE_AUTHKEY="$TS_AUTHKEY" \
  AGENTBOX_HOSTNAME=TANAABAGENTBOX1 \
  bash
```

This default flow:

- materializes `~/tanaab/agentbox`
- applies the repo [`Brewfile`](./Brewfile)
- configures headless macOS settings, classic SSH, Tailscale, and health launchd
- joins Tailscale using the provided auth key

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

- Decide FileVault deliberately. For a physically controlled headless agentbox, the default
  recommendation is FileVault off, no auto-login, and services started by launchd.
- Temporarily enable Remote Login if needed for initial access. `boot.sh` enables classic SSH
  programmatically.
- Create or choose a preauthorized Tailscale auth key with the intended `tag:agentbox` tag.
- Optionally choose SSH public keys for `boot.sh` to install for the admin user.

## Usage

For repeated use, install the hosted script as a local command in a directory you manage on `PATH`.

```sh
mkdir -p "$HOME/.local/bin"
curl -fsSL https://agentbox.boot.tanaab.sh/boot.sh -o "$HOME/.local/bin/agentboxboot"
chmod +x "$HOME/.local/bin/agentboxboot"

agentboxboot --help
```

Run it with flags when you want to keep the command explicit:

```sh
agentboxboot --tailscale-authkey "$TS_AUTHKEY" --hostname TANAABAGENTBOX1
```

Authorized keys are optional runtime inputs for classic SSH. Supported values are raw public-key
lines, explicit `file:` references, and existing public-key paths:

```sh
agentboxboot \
  --tailscale-authkey "$TS_AUTHKEY" \
  --authorized-key file:~/.ssh/id_ed25519.pub \
  --hostname TANAABAGENTBOX1

agentboxboot \
  --tailscale-authkey "$TS_AUTHKEY" \
  --authorized-key "ssh-ed25519 AAAA... user@example" \
  --authorized-key file:~/.ssh/backup.pub \
  --hostname TANAABAGENTBOX1
```

Use `--agentbox-version` to install a tagged release archive instead of cloning the default branch:

```sh
agentboxboot \
  --tailscale-authkey "$TS_AUTHKEY" \
  --agentbox-version 1.2.3 \
  --hostname TANAABAGENTBOX1
```

The default hostname is `TANAABAGENTBOX1`. The configured hostname is used for macOS system
identity, and Tanaab-prefixed hostnames derive a shorter Tailscale hostname by stripping the leading
`TANAAB` prefix. For example, `TANAABAGENTBOX1` joins Tailscale as `AGENTBOX1`.

Out of scope for this pass: Wi-Fi management, runtime users, SSH password-login hardening, Screen
Sharing or auto-login automation, Caddy, app runtimes, and Tailscale SSH. Remote shell access uses
classic SSH over Tailscale.

## Configuration

The public configuration surface is intentionally small. Prefer environment variables for secrets so
raw values do not land in shell history.

- `AGENTBOX_TAILSCALE_AUTHKEY` or `--tailscale-authkey`: required raw Tailscale auth key.
- `AGENTBOX_HOSTNAME` or `--hostname`: canonical macOS hostname and Tailscale hostname source.
- `AGENTBOX_AUTHORIZED_KEY` or `--authorized-key`: optional public key or public-key file path for
  classic SSH.
- `AGENTBOX_TAILSCALE_TAGS`: Tailscale advertise tags; defaults to `tag:agentbox`.
- `AGENTBOX_VERSION` or `--agentbox-version`: tagged agentbox release archive to install.
- `AGENTBOX_FORCE` or `--force`: replace supported existing targets.
- `AGENTBOX_DEBUG` or `--debug`: show debug output with secrets masked.
- `NONINTERACTIVE`, `CI`, or `--yes`: skip interactive prompts.

Run `boot.sh --help` for the exact current CLI and environment-variable contract.

## After Bootstrap

- In the Tailscale admin console, confirm the node joined with the expected name/tag, decide whether
  node key expiry should be disabled for this infrastructure node, and keep ACLs restrictive.
- Reboot the Mac, then verify it returns to Tailscale before any GUI login.
- Confirm Tailscale service and network status:

```sh
sudo brew services info tailscale
tailscale status
tailscale ip -4
```

- Verify classic SSH over Tailscale from another machine:

```sh
ssh <admin-user>@<tailscale-name-or-ip>
```

- Confirm the health daemon and logs:

```sh
sudo launchctl print system/dev.tanaab.agentbox.health
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
