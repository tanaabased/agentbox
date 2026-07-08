## {{ UNRELEASED_VERSION }} - [{{ UNRELEASED_DATE }}]({{ UNRELEASED_LINK }})

- Added `--agentbox-version` support for HTTPS tar archive URLs and local tar archives.
- Added `--brewfile` and `AGENTBOX_BREWFILE` for optional extra Bootbox Brewfiles.
- Added `Brewfile.extras` for optional Codex, Codex App, OpenClaw, and Warp casks.
- Added gateway-only OpenClaw onboarding, OpenClaw gateway configuration, an agentbox-owned gateway
  LaunchDaemon, and gateway health checks.
- Added OpenClaw runner user creation, autologin, SSH keys, and health checks.
- Added randomized selection from bundled OpenClaw runner profile images for newly created users.
- Added `openclaw-cli`, `ripgrep`, and Homebrew login-shell `PATH` setup to the base bootstrap.
- Externalized the installed health script and agentbox LaunchDaemon plist bodies into root-level
  `bin/` and `launchd/` directories.
- Updated Tailscale-enabled OpenClaw gateway setup to keep the gateway bound to loopback and expose
  it through Tailscale Serve.
- Updated Tailscale setup to set the OpenClaw runner as the Tailscale operator and verify the
  OpenClaw gateway Serve route during bootstrap and health checks.
- Updated the agentbox-owned `tailscaled` LaunchDaemon to use an explicit state directory under
  `/var/db/tanaab/agentbox/tailscale`.
- Updated repo docs to make OpenClaw gateway host setup the target `agentbox` scope.
- Updated `boot.sh --help` option layout for readability.

## v1.0.0-beta.5 - [June 16, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.5)

- Added `--brewgroup` and `AGENTBOX_BREWGROUP` for configurable Homebrew prefix group-write setup. ([#9](https://github.com/tanaabased/agentbox/pull/9))
- Added `brewgroup:trusted-group` syntax for opt-in trusted group nesting, such as `brewer:staff`. ([#9](https://github.com/tanaabased/agentbox/pull/9))
- Added `health.sh --brewgroup` and brewgroup health report fields for downstream detection and verification. ([#9](https://github.com/tanaabased/agentbox/pull/9))
- Added direct invoking-admin membership in the configured brewgroup when brewgroup setup is enabled. ([#9](https://github.com/tanaabased/agentbox/pull/9))
- Fixed mutating Leia examples to run against the PR checkout and trust the Bun tap used by the agentbox `Brewfile`. ([#9](https://github.com/tanaabased/agentbox/pull/9))

## v1.0.0-beta.4 - [May 24, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.4)

- Added an agentbox-owned system LaunchDaemon for root-level `tailscaled` management. ([#6](https://github.com/tanaabased/agentbox/pull/6))

## v1.0.0-beta.3 - [May 24, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.3)

- Updated Bootbox delegation to run noninteractively after the agentbox wrapper confirmation gate. ([#5](https://github.com/tanaabased/agentbox/pull/5))

## v1.0.0-beta.2 - [May 24, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.2)

- Added CI coverage for `--agentbox-version` release archive installs. ([#4](https://github.com/tanaabased/agentbox/pull/4))
- Added `health.sh --report` and `health.sh --check` as the primary post-bootstrap verification surface. ([#4](https://github.com/tanaabased/agentbox/pull/4))
- Fixed `--agentbox-version` validation for prerelease tags such as `v1.0.0-beta.1`. ([#4](https://github.com/tanaabased/agentbox/pull/4))
- Updated headless macOS health checks to keep real-machine requirements strict while tolerating managed macOS runner gaps. ([#4](https://github.com/tanaabased/agentbox/pull/4))
- Updated README guidance for manual setup, Remote Login, and runtime-install boundaries. ([#4](https://github.com/tanaabased/agentbox/pull/4))

## v1.0.0-beta.1 - [May 24, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.1)

- Added a hosted `boot.sh` bootstrap wrapper for materializing the agentbox profile.
- Added headless macOS setup for system identity, power/firewall defaults, classic SSH, and launchd health.
- Added Netlify distribution, release workflow support, `llms.txt` publishing, and Leia-backed CI examples.
- Added optional Tailscale setup with auth-key joining, hostname derivation, and explicit opt-out support.
- Added SSH authorized-key installation with key-only sshd hardening for the invoking admin user.
