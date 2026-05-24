## {{ UNRELEASED_VERSION }} - [{{ UNRELEASED_DATE }}]({{ UNRELEASED_LINK }})

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
