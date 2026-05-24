# agentbox

`agentbox` prepares a physically accessible macOS 26.x Mac for secure headless operation. It
installs a small base profile with Homebrew packages, classic SSH, optional Tailscale access, and
launchd-managed health checks so the machine is ready for whatever agent runtime you add later.

`agentbox` prepares the admin side of the Mac. Install agent runtimes and
application workloads later as **non-admin, non-sudo users**.

**What it does**

- Materializes this repo at `~/tanaab/agentbox` through the hosted `boot.sh` wrapper.
- Applies the repo [`Brewfile`](./Brewfile) through
  [Bootbox](https://github.com/tanaabased/bootbox).
- Sets macOS system identity and headless power/firewall defaults.
- Enables classic SSH, installs optional authorized keys, and hardens sshd to key-only login when
  keys are provided.
- Installs Tailscale from Homebrew and optionally joins the tailnet.
- Installs a launchd health check under `/opt/tanaab/agentbox`.

**What it does not do**

- Install an agent runtime, app stack, Caddy, or project-specific services.
- Create runtime users or manage user passwords.
- Configure Wi-Fi, Screen Sharing, auto-login, Tailscale SSH, or router port forwarding.
- Open public WAN access to SSH or future services.

**Caveats**

- Supports macOS 26.x on `x64` and `arm64`; newer major versions are blocked until validated.
- Requires a sudo-capable admin user.
- Designed for Mac hardware you physically control; Mac VPS behavior is unverified.
- Tailscale is recommended and enabled by default, but can be skipped with a falsey auth-key value.
- Authorized keys enable SSH key-only hardening. Bad keys can lock out remote SSH, so keep physical
  or admin recovery access available.

## Quickstart

Complete the [Manual Setup Checklist](#manual-setup-checklist) first, then run the hosted bootstrap
script on the Mac you are preparing:

```sh
curl -fsSL https://agentbox.boot.tanaab.sh/boot.sh | \
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

- Decide FileVault deliberately. For a physically controlled headless agentbox, the default
  recommendation is FileVault off, no auto-login, and services started by launchd.
- Consider installing an HDMI dummy plug / headless display adapter, such as
  [this example](https://www.amazon.com/dp/B0CKKLTWMN?ref=fed_asin_title), for smoother headless
  display behavior.
- Temporarily enable Remote Login if needed for initial access. `boot.sh` enables classic SSH
  programmatically.
- Create or choose a preauthorized Tailscale auth key with any desired device tags, or decide to
  skip Tailscale setup.
- Optionally choose SSH public keys for `boot.sh` to install for the admin user.

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
for the invoking admin user and hardens SSH to key-only access for that user. Supported values are
public-key lines, explicit `file:` references, and existing public-key paths:

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

Use `--agentbox-version` to install a tagged release archive instead of cloning the default branch:

```sh
agentbootbox \
  --tailscale-authkey "$TS_AUTHKEY" \
  --agentbox-version 1.2.3 \
  --hostname TANAABAGENTBOX1
```

## Tailscale

Tailscale is the recommended remote access path, but it is not mandatory. When enabled, `boot.sh`
starts `tailscaled`, checks whether the Mac is already joined, and only requires an auth key for a
first join.

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

After joining, use the Tailscale admin console to confirm the node name, decide whether node key
expiry should be disabled for this infrastructure node, and keep ACLs restrictive.

If your tailnet uses MagicDNS or another friendly DNS name, such as `tanaab.net`, verify the node is
reachable through that name as well as its Tailscale IP.

## Configuration

The public configuration surface is intentionally small. Prefer environment variables for secrets so
they do not land in shell history.

- `AGENTBOX_TAILSCALE_AUTHKEY` or `--tailscale-authkey`: Tailscale auth key for first join; use
  `off`, `false`, `no`, `0`, or `null` to skip Tailscale setup.
- `AGENTBOX_HOSTNAME` or `--hostname`: canonical macOS hostname and Tailscale hostname source.
- `AGENTBOX_AUTHORIZED_KEY` or `--authorized-key`: optional public key or public-key file path for
  classic SSH; providing keys also enables key-only SSH hardening.
- `AGENTBOX_VERSION` or `--agentbox-version`: tagged agentbox release archive to install.
- `AGENTBOX_FORCE` or `--force`: replace supported existing targets.
- `AGENTBOX_DEBUG` or `--debug`: show debug output with secrets masked.
- `NONINTERACTIVE`, `CI`, or `--yes`: skip interactive prompts.

Run `boot.sh --help` for the exact current CLI and environment-variable contract.

## Verification

- Reboot the Mac and confirm it returns to the expected network state before any GUI login.
- If Tailscale is enabled, confirm service and network status:

```sh
sudo brew services info tailscale
tailscale status
tailscale ip -4
```

- If authorized keys were provided, verify key-based SSH over Tailscale or LAN from another machine
  before closing the local/admin recovery session:

```sh
ssh -o PreferredAuthentications=publickey <admin-user>@<tailscale-name-or-ip>
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
