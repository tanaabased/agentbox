# Repo Guidance For `agentbox`

This root `AGENTS.md` is the repo-local override for Codex work in this repository.

## Purpose

- This repo exists to prepare an Apple Silicon Mac mini as a secure, headless Tanaab AgentBox foundation.
- Keep the repo focused on the base machine: macOS settings, local users, SSH, Tailscale, launchd, recovery, and validation.
- Do not add agent runtime setup, trading credentials, app-specific services, router port forwarding, or public WAN exposure here.

## Source Of Truth

- `boot.sh` is currently copied from the source scaffold only as a shell-entrypoint starting point.
- Do not preserve copied source behavior as an AgentBox requirement. The AgentBox-specific `boot.sh` rewrite is a separate task.
- `README.md` should stay human-facing and concise.
- Future machine setup details should live in focused docs or scripts instead of being hidden in broad prose.

## Codex Plugin Boundary

- This repo is not a Codex plugin.
- Do not add plugin manifests, MCP manifests, cache sync helpers, skill bundles, or marketplace metadata.
- Do not add package scripts for plugin validation or cache syncing unless the repo intentionally becomes a plugin later.

## Secret And SSH Material

- Do not commit SSH private keys, SSH public keys, Tailscale auth keys, API tokens, passwords, or generated secret files.
- SSH and Tailscale material should come from 1Password-backed setup flows.
- Keep real `.env` files untracked.

## Validation Policy

- Prefer the narrowest reliable checks for the touched surface.
- For the current scaffold, `bun run lint` is the expected local validation.
- Do not run or validate the copied `boot.sh` machine-bootstrap behavior until the AgentBox rewrite starts.
