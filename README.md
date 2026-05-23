# AgentBox

`agentbox` is the base provisioning scaffold for preparing an Apple Silicon Mac mini as a secure, headless Tanaab AgentBox.

This repository is currently in its first scaffold pass. It was seeded from an existing bootstrap repo for shell and tooling shape, then stripped of Codex plugin packaging, personal dotfiles, generated hosting output, and old release surfaces.

## Current Status

- `boot.sh` is copied in place as a temporary starting point.
- The AgentBox-specific `boot.sh` rewrite is still pending.
- The repo should stay focused on base-machine setup: macOS settings, standard runtime users, SSH, Tailscale, launchd, and validation.
- Agent runtimes, app-specific setup, trading credentials, committed SSH keys, and public WAN exposure are out of scope.

## Development

```sh
bun install
bun run lint
```

The lint surface is intentionally small while the AgentBox bootstrap shape is being established.
