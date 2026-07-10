# Repo Guidance For `agentbox`

This root file should stay short and apply to most repo work. Put narrower policy closer to the files
it governs, such as `examples/AGENTS.md` for Leia examples.

## Purpose

`agentbox` prepares a physically accessible Mac to become a managed, headless OpenClaw host with
a working OpenClaw Gateway, reasonable security defaults, and optional Tailscale access.

## Scope

In scope:

- macOS host setup: identity, headless settings, recovery posture, classic SSH, and base packages.
- Tailscale daemon setup, tailnet join, MagicDNS resolver support, and Tailscale Serve.
- Non-admin OpenClaw runner setup, gateway onboarding, service supervision, and health checks.
- Host-level security hardening and recovery options.

Out of scope:

- Agent, persona, or workspace-specific setup.
- Per-agent dotfiles, shell themes, app preferences, project credentials, and trading or workload
  services.
- Router port forwarding, public WAN exposure, and unrelated machine administration.

## Long-Term Direction

This is directional guidance, not the current public contract:

- Evolve from a one-shot bootstrap script toward an `agentbox` management CLI with reusable
  subcommands and shared implementation logic.
- Keep the hosted shell entrypoint as the install/bootstrap path until an explicit replacement is
  designed.
- Plan for macOS and Linux support over time; Windows remains unsupported unless the product contract
  changes.
- Prefer a future Bun-based CLI when implementation moves beyond shell-friendly orchestration.
- Organize future commands around stable concerns such as dependencies, system configuration,
  connectivity/serving, OpenClaw, services/units, health, and status.
- Use this direction to shape new abstractions, but do not start large rewrites or future-platform
  work unless the task explicitly calls for it.

## Source Map

- `macos.sh`: shipped macOS entrypoint and main bootstrap script.
- `unsupported.sh`: hosted fallback for unsupported or unknown platforms.
- `Brewfile`: core Homebrew packages; `Brewfile.extras`: optional operator tooling.
- `bin/health.sh`: source for `/opt/tanaab/agentbox/bin/health.sh` and the machine health contract.
- `launchd/*.plist.in`: source LaunchDaemon templates rendered by `macos.sh`.
- `README.md`: main setup and usage entrypoint; `ADVANCED.md`: deeper operator reference.
- `examples/**/README.md`: Leia-backed executable CI contracts.
- `site/llms.txt`, `scripts/build-dist.js`, `netlify.toml`: hosted-script and metadata publishing
  sources.
- `dist/`: committed generated publish output, owned by CI/release workflows.

## Critical Rules

- Style the product, repository, and CLI name as lowercase `agentbox` in all prose and user-facing
  output, including at the start of a sentence. Never render the brand as `AgentBox`; preserve
  uppercase only where required by case-sensitive identifiers such as `AGENTBOX_*` environment
  variables, constants, and fixture hostnames.
- Do not edit, regenerate, stage, or commit `dist/` during routine local work. Change source inputs
  and leave generated output to CI unless the user explicitly asks.
- Do not run `bun run build` locally unless the user explicitly asks for generated-output
  verification. Preserve the single top-level `SCRIPT_VERSION` assignment in `macos.sh`.
- Keep `/llms.txt` concise in `site/llms.txt`; `scripts/build-dist.js` copies it into `dist/`.
- Keep `--help` as the public CLI contract. Public option, env-var, help, status, debug, or
  failure-text changes must check `README.md`, `ADVANCED.md`, and affected examples.
- Do not add user documentation for small interaction, presentation, or internal orchestration
  changes by default. Document behavior needed to choose inputs, complete setup, interpret results,
  or operate and recover the host.
- Preserve the public `AGENTBOX_*` namespace. Do not leak upstream Bootbox names into the public
  `agentbox` interface.
- Never commit Tailscale auth keys, SSH private keys, API tokens, passwords, machine-specific secret
  files, or generated `authorized_keys` files. Preserve masking in debug, help, planning, and error
  output.
- Keep SSH password-login hardening coupled to provided authorized keys. Do not disable password
  login for runs that did not configure key-based access.
- Treat Tailscale tag assignment as auth-key and tailnet-policy configuration, not an `agentbox` CLI
  input.

## `macos.sh` Invariants

- Preserve the macOS support gate and sudo preflight before Bootbox download, repo materialization,
  Brewfile application, or other machine mutation.
- Keep Bootbox delegation noninteractive; the `agentbox` wrapper owns the confirmation gate.
- Keep payload resolution aligned with the running `macos.sh` and do not fall back to cloning the
  default branch.
- Preserve formula-based Tailscale install and the managed daemon model; do not reintroduce the GUI
  cask or Tailscale SSH mode unless the product contract changes.
- Preserve classic SSH and managed sshd hardening through `/etc/ssh/sshd_config.d/agentbox.conf`.
  Do not patch `/etc/ssh/sshd_config` directly.
- Keep the OpenClaw runner non-admin, require a user-provided or prompted password for runner
  creation/autologin, and never print, persist, generate, or debug-log that password.
- Preserve existing OpenClaw runner profile pictures; apply bundled profile assets only when the user
  has no configured picture.
- Keep real-machine health checks strict. Managed macOS runner skips must be recorded in state, set
  only from known runner environments, and narrowly scoped.
- Prefer targeted edits to `macos.sh`; avoid whole-file rewrites unless the script contract is being
  intentionally replaced.

## Examples And Leia

- Examples are executable Leia specs consumed in CI, not prose-only docs.
- Keep `examples/inputs` non-mutating; mutating examples should prove behavior domains rather than
  every input spelling.
- See `examples/AGENTS.md` before editing examples.

## Validation

- Prefer the narrowest reliable checks for the touched area.
- For routine local validation, use `bun run lint`; run `git diff --check` when whitespace or
  generated text churn is plausible.
- Run `bun install` when dependencies are missing before linting; keep `bun.lock` when Bun updates
  it.
- Do not delete local `node_modules/` after validation; it is ignored and local-only.
- Do not run `macos.sh`, `dist/macos.sh`, mutating Leia examples, or `bun run build` as routine local
  validation unless the user explicitly asks.
- If `macos.sh`, Leia, or `bun run build` is intentionally skipped because of task scope or repo
  policy, say so plainly.

## References

- `README.md`, `ADVANCED.md`, `CHANGELOG.md`
- `examples/`, `examples/AGENTS.md`
- `bin/health.sh`
- `site/llms.txt`, `scripts/build-dist.js`
