## {{ UNRELEASED_VERSION }} - [{{ UNRELEASED_DATE }}]({{ UNRELEASED_LINK }})

### Breaking Changes

- Removed `--openclaw-service-mode` and `AGENTBOX_OPENCLAW_SERVICE_MODE`; macOS now supports only OpenClaw's native user LaunchAgent. [#19](https://github.com/tanaabased/agentbox/issues/19)

### New Features

- Added Aqua-only first-login Gateway activation with private retry state, user-owned logs, and native LaunchAgent RPC verification. [#19](https://github.com/tanaabased/agentbox/issues/19)
- Added default runtime-user autologin with FileVault and policy preflight checks, plus `--openclaw-autologin off` for manual-login hosts. [#19](https://github.com/tanaabased/agentbox/issues/19)

### Improvements

- Updated agentbox-managed native Gateways with durable mDNS and ownership environment while preserving healthy unmanaged services. [#19](https://github.com/tanaabased/agentbox/issues/19)
- Updated Doctor to inspect a root-published periodic health snapshot without sudo. [#23](https://github.com/tanaabased/agentbox/issues/23)
- Updated Gateway conflict reconciliation to back up administrator state and refuse unexpected port owners. [#19](https://github.com/tanaabased/agentbox/issues/19)
- Updated Gateway diagnostics and health to cover the native runtime log and its permissions. [#19](https://github.com/tanaabased/agentbox/issues/19)
- Updated health and Doctor output with autologin readiness, GUI, finalizer, native LaunchAgent, conflict, and targeted remediation details. [#19](https://github.com/tanaabased/agentbox/issues/19)

### Bug Fixes

- Fixed Homebrew brewgroup access to repair descendant drift on every run and report later drift in health. [#21](https://github.com/tanaabased/agentbox/issues/21)

### Bug Fixes

- Fixed Homebrew brewgroup access to repair descendant drift on every run and report later drift in health. [#21](https://github.com/tanaabased/agentbox/issues/21) [#25](https://github.com/tanaabased/agentbox/pull/25)

## v1.0.0-beta.7 - [July 17, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.7)

### Breaking Changes

- Changed bootstrap and reconciliation to enforce the `MODEL L3-37` fallback gateway identity, bundled avatar, and Tanaab seam color, replacing any existing custom fallback branding. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Changed OpenClaw `system` service mode to remove native gateway LaunchAgents for both the runner and invoking administrator, and configure the admin app for attach-only access to the managed gateway. [#17](https://github.com/tanaabased/agentbox/pull/17)

### Codex Plugin

- Added an optional Codex plugin, distributed in GitHub release archives, with `$tanaab-agentbox-installer`, `$tanaab-agentbox`, and `$tanaab-agentbox-doctor` workflows. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Added grouped, version-aware local host diagnosis with bounded checks and focused repair recommendations that require separate confirmation. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Added verified stable-release and source-checkout management with private atomic configuration, invalid-config recovery, and opt-in `agentbox` command linking. [#17](https://github.com/tanaabased/agentbox/pull/17)

### New Features

- Added authenticated OpenClaw Dashboard launch guidance after successful setup, including the exact runner command needed to open it. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Added managed OpenClaw Gateway discovery and access alignment through mDNS hostname matching, explicit Tailscale identity authentication, and system-mode admin-app port and token synchronization when available. [#17](https://github.com/tanaabased/agentbox/pull/17)

### Improvements

- Updated post-bootstrap health with concise status output and broader checks for OpenClaw app and service state, log permissions, Tailscale identity persistence, and gateway authentication. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Updated OpenClaw reruns to reconcile valid local gateway configuration noninteractively instead of reopening onboarding. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Updated sudo orchestration to keep the early capability gate nonprompting, authorize interactive runs after Bootbox and Homebrew, and delegate a reusable session through noninteractive Bootbox work. [#17](https://github.com/tanaabased/agentbox/pull/17)

### Bug Fixes

- Fixed managed OpenClaw Gateway log ownership and permissions for the non-admin runner service. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Fixed managed `tailscaled` state ownership and persistence so its identity survives daemon restarts. [#17](https://github.com/tanaabased/agentbox/pull/17)
- Fixed stopped, already-authenticated Tailscale identities to resume without requiring a new auth key. [#17](https://github.com/tanaabased/agentbox/pull/17)

## v1.0.0-beta.6 - [July 9, 2026](https://github.com/tanaabased/agentbox/releases/tag/v1.0.0-beta.6)

### Breaking Changes

- Removed `--agentbox-version`; use source-relative payloads, release archives, or `AGENTBOX_PAYLOAD_DIR` instead. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Removed `--skip-openclaw-autologin`; system mode no longer needs autologin, and `user` mode owns it. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Renamed the hosted macOS entrypoint from `boot.sh` to `macos.sh`. [#16](https://github.com/tanaabased/agentbox/pull/16)

### New Features

- Added `--brewfile` and `AGENTBOX_BREWFILE` for optional extra Bootbox Brewfiles. [#13](https://github.com/tanaabased/agentbox/pull/13)
- Added `--openclaw-auth-env` for provider auth choices not yet known to agentbox. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Added `--openclaw-gateway-port` for configuring the local OpenClaw Gateway port. [#13](https://github.com/tanaabased/agentbox/pull/13)
- Added `--openclaw-service-mode` with default system supervision and optional OpenClaw user service mode. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Added automatic payload resolution for source checkouts, CI payloads, and release-matched archives. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Added base OpenClaw host tooling, including `openclaw-cli`, `ripgrep`, and login-shell Homebrew `PATH`. [#13](https://github.com/tanaabased/agentbox/pull/13)
- Added gateway-only OpenClaw onboarding with loopback binding and optional Tailscale Serve exposure. [#13](https://github.com/tanaabased/agentbox/pull/13)
- Added OpenClaw runner user creation, SSH access, profile image setup, and health checks. [#13](https://github.com/tanaabased/agentbox/pull/13)
- Added `unsupported.sh` as the hosted fallback for unsupported or unknown platforms. [#16](https://github.com/tanaabased/agentbox/pull/16)

### Improvements

- Updated health reports to cover service mode, gateway readiness, Tailscale Serve, MagicDNS settings, and resolver drift.
- Updated OpenClaw system services to use generated runner-owned service environment files. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Updated setup docs with a shorter README and new `ADVANCED.md` operator reference.
- Updated Tailscale setup to manage an agentbox-owned `tailscaled` state directory. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Updated Tailscale setup to set the OpenClaw runner as operator and configure a scoped MagicDNS resolver. [#15](https://github.com/tanaabased/agentbox/pull/15)

### Bug Fixes

- Fixed debug color rendering. [#10](https://github.com/tanaabased/agentbox/pull/10)
- Fixed OpenClaw gateway launch environment alignment with OpenClaw service markers and macOS CA settings. [#15](https://github.com/tanaabased/agentbox/pull/15)
- Fixed Tailscale Serve setup to fail early when MagicDNS or HTTPS Certificates are missing. [#15](https://github.com/tanaabased/agentbox/pull/15)

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
