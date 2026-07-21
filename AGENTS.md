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
- `launchd/*.plist.in`: source launchd service templates rendered by `macos.sh`.
- `.codex-plugin/plugin.json`, `skills/`: Codex plugin metadata and installable skill surface.
- `assets/composer-icon.svg`, `assets/icon-large.png`: Codex plugin interface assets.
- `bin/codexsync.js`, `lib/codexsync-*.js`: package-level plugin validation and installed cache
  comparison or refresh tooling.
- `README.md`: main setup and usage entrypoint; `ADVANCED.md`: deeper operator reference;
  `CODEX.md`: optional Codex plugin installation and workflow guide.
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
- Keep the source versions in `package.json` and `.codex-plugin/plugin.json` aligned. Release
  workflows must stamp both `dist/macos.sh` and the plugin manifest from the same release tag.
- GitHub Releases publish `agentbox-<tag>.tar.gz` from the complete release-shaped repository. Keep
  the plugin manifest, skills, plugin assets, and runtime payload files in that archive.
- Keep `--help` as the public CLI contract. Public option, env-var, help, status, debug, or
  failure-text changes must check `README.md`, `ADVANCED.md`, and affected examples.
- Keep documentation ownership explicit: `README.md` leads with hosted bootstrap and common usage,
  `ADVANCED.md` owns manual host and operator details, and `CODEX.md` owns the optional plugin surface.
  Link between them instead of duplicating complete contracts.
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

- Preserve the macOS support gate and a non-prompting sudo capability check before Bootbox download,
  payload materialization, Brewfile application, or other machine mutation. This early check verifies
  `/usr/bin/sudo` and the invoking admin account without establishing a sudo timestamp.
- For interactive runs, establish the managed agentbox sudo session after Bootbox applies Brewfiles
  because Homebrew invalidates prior sudo timestamps. For CI and other non-interactive runs, require
  reusable non-interactive sudo before Bootbox and delegate that session with
  `BOOTBOX_EXTERNAL_SUDO=1`.
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
- Keep Mocha `test/**/*.spec.js` limited to JavaScript units. Do not use JavaScript subprocess
  harnesses to execute shell scripts as unit tests.
- Put shell CLI, script, file-mutation, permission, exit-status, and other functional or end-to-end
  behavior in the narrowest owning Leia example. Use shellcheck and `bash -n` only as supporting
  static checks.
- A JavaScript unit test may read shell-owned declarations when the JavaScript mapping or parser is
  the subject under test, but it must not execute the shell script as the tested behavior.
- Keep `examples/inputs` non-mutating; mutating examples should prove behavior domains rather than
  every input spelling.
- See `examples/AGENTS.md` before editing examples.

## JavaScript And Plugin Skills

- Keep skill-owned JavaScript entrypoints and support modules under the owning
  `skills/<skill>/scripts/` directory. Do not hoist them merely because the full repository ships in
  the plugin archive.
- Keep repository unit tests under `test/` as `*.spec.js` files and use the shared Mocha test shape.
- Keep the repo-owned Codex plugin contract in `lib/plugin-validation.js` and run it through
  `bun run codex:validate`. Limit that validator to loader-facing requirements for a valid Codex
  plugin: a parseable manifest, valid declared local resources, parseable optional app and MCP
  configuration, and bundled skills with required `name` and `description` frontmatter. Do not use it
  to enforce Tanaab authoring conventions, documentation links, prompt content, release version
  alignment, GitHub workflow wiring, or general dependency and runtime-version policy. Keep
  validation read-only and separate from cache synchronization.
- Treat `.codex-plugin/`, `.mcp.json`, `AGENTS.md`, `ADVANCED.md`, `CODEX.md`, `README.md`, `assets/`,
  `bin/codexsync.js`, `lib/`, `package.json`, `scripts/check-plugin-runtime.sh`, and `skills/` as the
  managed Codex plugin cache surface for `bun run codex:check` and `bun run codex:sync`.
- Keep plugin cache refresh installation-aware. `codex:check` must report an absent exact-version
  cache as neutral `not_installed`; `codex:sync` must refuse to create it. A source symlink or an
  older cached version does not authorize initialization of the current cache.
- Reserve root `bin/` for a real package-level CLI. Hoist runtime modules to root `lib/` only after
  reuse across at least two live skills or when they become a repo-wide contract.
- Require Bun-dependent plugin skills to run `scripts/check-plugin-runtime.sh` before invoking their
  JavaScript helpers. Keep this preflight read-only and do not install or repair Bun automatically.
- Keep plugin skill ownership distinct: `agentbox` plans and runs bootstrap or reconciliation,
  `agentbox-installer` manages configured executables, and `agentbox-doctor` inspects installed host
  health without mutation.
- Check `CODEX.md` and `site/llms.txt` when plugin installation, runtime prerequisites, bundled skill
  ownership, or public invocation guidance changes.
- Keep the installer-managed `agentbox` command link opt-in. Omission of `--link-command` on a fresh
  config must not create, replace, or remove PATH commands; status may inspect PATH entries but must
  not execute discovered commands.
- Never load or apply `skills/agentbox/references/tanaab-installation.md` unless the user explicitly
  requests the Tanaab-based installation profile for the current run. Do not infer it from identity,
  repository context, hostnames, paths, prior conversation, or existing configuration.
- Keep agentbox doctor bound to `/opt/tanaab/agentbox/bin/health.sh`. If that installed health script
  is absent, report that agentbox is not installed; never fall back to a source or configured
  installer copy. Read health only from the fixed agentbox-published
  `/var/db/tanaab/agentbox/health-report`; never accept arbitrary saved reports, execute the health
  script, or invoke sudo from Doctor.

## Validation

- Prefer the narrowest reliable checks for the touched area.
- For routine local validation, use `bun run lint`; run `git diff --check` when whitespace or
  generated text churn is plausible.
- Run `bun run test` for JavaScript unit changes. Shell behavior belongs in Leia, not Mocha.
- Run `bun run codex:validate` for plugin manifest, skill metadata, plugin asset, or plugin workflow
  changes.
- For managed plugin changes, run `bun run codex:check`. If it reports drift, run
  `bun run codex:sync` and then `bun run codex:check` again before committing. If it reports
  `not_installed`, do not sync; report that cache refresh was skipped because the plugin is not
  installed.
- Repeat the cache check after a rebase, cherry-pick, amendment, conflict resolution, or commit-time
  edit changes managed plugin files. A commit that does not change file content does not require a
  redundant post-commit sync.
- Run `bun install` when dependencies are missing before linting; keep `bun.lock` when Bun updates
  it.
- Do not delete local `node_modules/` after validation; it is ignored and local-only.
- Do not run `macos.sh`, `dist/macos.sh`, mutating Leia examples, or `bun run build` as routine local
  validation unless the user explicitly asks.
- If plugin cache sync, a Codex restart, `macos.sh`, Leia, or `bun run build` is intentionally skipped
  because of task scope, installation state, or repo policy, say so plainly.

## References

- `README.md`, `ADVANCED.md`, `CODEX.md`, `CHANGELOG.md`
- `examples/`, `examples/AGENTS.md`
- `bin/health.sh`
- `site/llms.txt`, `scripts/build-dist.js`
