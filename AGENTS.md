# Repo Guidance For `agentbox`

This root `AGENTS.md` is the repo-local override for Codex work in this repository. Keep
repo-specific agent policy here and do not duplicate it in nested `AGENTS.md` files unless
explicitly asked.

## Purpose

- This repo owns the path from a physically accessible macOS 26.x Mac to a managed OpenClaw host:
  headless access, macOS settings, base packages, SSH/Tailscale connectivity, non-sudo OpenClaw
  runner-user setup, launchd health, recovery, security hardening, and OpenClaw gateway onboarding.
- The boundary ends when the Mac has a working OpenClaw gateway and is ready for agent workspaces to
  be layered on top.
- Future global OpenClaw plugin installation belongs here when it is host-level substrate rather than
  workspace-specific agent behavior.
- Do not add EMORI-specific setup, per-agent dotfiles, trading credentials, app-specific
  services, agent-specific plugin installs, router port forwarding, or public WAN exposure here.

## Source Of Truth

- `boot.sh` is the shipped shell entrypoint and main bootstrap surface.
- `Brewfile` is the source of truth for base Homebrew packages.
- `Brewfile.extras` is an optional personal-tooling Brewfile for operator apps, not part of the
  core host contract.
- `bin/health.sh` is the source health script installed to `/opt/tanaab/agentbox/bin/health.sh`.
- `launchd/*.plist.in` files are source LaunchDaemon templates rendered by `boot.sh` with
  machine-specific paths and binary locations.
- `README.md` is the human-facing setup, usage, and post-bootstrap surface.
- `examples/**/README.md` files are Leia-backed executable contract specs consumed in CI.
- `dist/` is generated publish output for Netlify hosting and release preparation.
- `scripts/build-dist.js`, `site/`, `netlify.toml`, release workflows, and the committed `dist/`
  files own the hosted-script publishing surface.

## Naming And Style

- In markdown and docs prose, stylize this project as `agentbox`.
- Preserve literal identifiers exactly as written, including commands, paths, hostnames, environment
  variables, labels, generated strings, repository names, and URLs.

## Build Artifacts

- Do not edit, regenerate, stage, or commit files under `dist/` during local agent work.
- `dist/` is CI/release-owned output. GitHub Actions may regenerate and stamp it during build,
  test, release, or hosting workflows.
- Make source changes in `boot.sh`, `site/`, or `scripts/build-dist.js`; leave `dist/` unchanged
  unless the user explicitly asks for a local generated-artifact update.
- Keep `/llms.txt` concise in `site/llms.txt`; `scripts/build-dist.js` copies it into `dist/`.
  Do not hand-edit `dist/llms.txt` or add full-context variants unless the hosted docs surface
  becomes larger.
- If a local command accidentally changes `dist/`, restore those files before committing.
- Treat `boot.sh` as the source entrypoint and `dist/boot.sh` as the release-shaped hosted artifact
  prepared by build and release workflows.
- Preserve the source script's single top-level `SCRIPT_VERSION` assignment pattern so release
  stamping with `version-injector` keeps working.
- Do not run `bun run build` locally unless the user explicitly asks for local generated-output
  verification. Prefer GitHub Actions for build/release artifact validation.

## CLI Contract

- Keep `--help` as the public CLI contract surface.
- When changing option names, environment variables, help text, failure wording, version output,
  debug output, planning output, or status messages, update affected README usage/configuration
  content and Leia examples in the same change.
- Any `boot.sh` public interface change must check `README.md`, `examples/inputs`, and the
  affected mutating examples.
- Any machine behavior change in `boot.sh` must check README setup/after-bootstrap guidance plus
  the affected mutating Leia scenarios.
- Keep planned-action output aligned with actual execution order.
- Treat CLI help order as a readability convention, not a Leia-enforced contract. Prefer related
  bootstrap options near each other and keep generic controls such as `--force`, `--debug`,
  `--version`, `--help`, and `--yes` together near the bottom. Prefer alphabetical ordering for
  README/configuration reference lists unless they intentionally mirror help output.
- Keep `--brewfile` as an extra-Brewfile append surface. The core agentbox `Brewfile` must remain
  first in the delegated Bootbox Brewfile list.
- Treat `bin/health.sh` and its installed runtime copy as the source of truth for machine health
  verification. README and Leia should prefer `health.sh --check` for macOS/SSH/Tailscale state,
  while keeping repo materialization, Brewfile satisfaction, and live SSH-login proof as direct
  checks.

## Secrets And Logging

- Never commit Tailscale auth keys, SSH private keys, API tokens, passwords, or machine-specific
  generated secret files.
- Do not commit machine-specific SSH `authorized_keys` files. Pass public authorized keys at
  bootstrap with `AGENTBOX_AUTHORIZED_KEY` or repeatable `--authorized-key`.
- Keep SSH password-login hardening coupled to provided authorized keys; do not disable password
  login for runs that did not configure key-based access.
- Treat real `AGENTBOX_TAILSCALE_AUTHKEY` values as runtime-only secrets. Mask them in CLI output
  and prefer environment variable usage over CLI flags in secret-sensitive examples. Explicit
  falsey values disable Tailscale setup and are not secrets.
- Treat Tailscale tag assignment as auth-key and tailnet-policy configuration, not an agentbox CLI
  input.
- Preserve token masking in debug output and do not reintroduce raw argument logging.
- Do not add the Tailscale GUI cask unless the project intentionally changes away from headless
  daemon setup.

## Leia Example Style

- Leia examples under `examples/` are CI-owned executable scenarios. They may mutate GitHub-hosted
  macOS runners, but should not be treated as routine local validation.
- Prefer direct command pipelines, command substitutions, and deterministic inline values over
  writing files just to inspect them later.
- Do not capture command output into shell variables just to grep it later. Leia failure output must
  surface useful stdout/stderr in CI; prefer direct commands, `cmd --report`, or
  `cmd | tee /dev/stderr | grep ...` when an assertion needs both matching and diagnostics. If
  capture is needed to preserve a failing command's status, print the captured output before
  assertions.
- For health-report assertions, print and match the targeted `--report` lines before running the
  final `--check` gate so CI logs show the health mismatch that caused the failure.
- Prefer behavior-focused Leia `# should` labels over scenario labels. Avoid repeating the example
  name or setup style in every block; use words like `custom`, `default`, `configured`,
  `provided`, `preexisting`, or `source` only when that distinction is meaningful inside the same
  README.
- Keep OpenClaw runner account creation checks focused on identity and home-directory state. Assert
  privilege, autologin, SSH, and group membership in separate health-backed or domain-specific
  blocks. Only test runner profile pictures when preserving an existing picture is the scenario
  contract.
- Keep each Leia `# should` block focused on one small observable contract. Split blocks whose
  title needs `and`/`or`, mixes unrelated domains, or grows past roughly 12-15 command lines unless
  the block is one coherent multiline command.
- Treat Leia block size as a readability convention, not as an enforced ordering or lint rule.
- Do not give setup fixture commands standalone `# should` blocks unless the fixture state itself is
  the contract. Put `mkdir -p "$TMPDIR"` beside the first fixture that writes into `TMPDIR`.
- Use fixed, readable local resource names in GitHub-hosted macOS examples when the resource exists
  only on the ephemeral runner. Keep externally registered or shared resources, especially Tailscale
  hostnames, unique per scenario and run.
- Mutating Leia examples should run `boot.sh` once unless the example is explicitly about rerun,
  idempotency, or payload resolution behavior.
- Defaults-focused examples should avoid overriding agentbox-owned default values, while still
  providing required CI inputs such as payload paths, passwords, secrets, and unique shared-resource
  names.
- Treat example placement as a small taxonomy:
  `inputs` owns non-mutating public interface checks; `defaults` owns the baseline happy-path
  bootstrap with default agentbox-owned settings; named domain examples own focused behavior such
  as Tailscale, Homebrew, SSH, OpenClaw, users, rerun, or payload resolution.
- When adding coverage, prefer extending the narrowest existing example that owns the behavior. Add
  a new example when the behavior needs incompatible bootstrap inputs, crosses enough domains that
  it would blur an existing example, or intentionally needs another successful `boot.sh` run.
- Keep `examples/inputs` non-mutating. It owns help text, displayed defaults, input validation, and
  option/env precedence checks. Mutating examples should prove behavior domains such as Tailscale,
  Homebrew, SSH, OpenClaw, users, rerun, or payload resolution rather than re-testing every input
  spelling.
- Treat each blank-line-separated Leia block as a separate script. Do not rely on shell variables,
  functions, or working-directory changes persisting across `should` blocks.
- Avoid braced shell variable expansions such as `${VAR}` in Leia examples when plain `$VAR` works.
  Leia parsing has been brittle around braces; restructure commands instead of adding braces just
  for readability.
- Use `TMPDIR` for durable fixtures, unavoidable logs, and helper internals only.
- Keep generated SSH public/private key fixtures in `TMPDIR`; they are real test inputs, not scratch
  assertion files.
- When a mutating example provides authorized keys, verify localhost SSH login with the generated
  private key fixture instead of only inspecting `authorized_keys`.
- Do not add preemptive cleanup or destroy blocks to GitHub-hosted macOS examples just to reset
  machine state; each matrix job starts on a fresh hosted VM. Prefer `--retry 0` for mutating Leia
  examples so partial bootstrap failures are not retried on the same VM.
- Do not add expected-failure probes to mutating bootstrap examples when the failure can occur after
  machine state changes. Keep failure-contract checks in non-mutating CLI examples or make them fail
  during input validation before bootstrap side effects.

## Validation Policy

- Prefer the narrowest reliable checks for the touched surface.
- For routine local validation, use `bun run lint`.
- Run `git diff --check` when whitespace or generated text churn is plausible.
- Run `bun install` when dependencies are missing before linting, and keep `bun.lock` as a tracked
  dependency artifact when Bun updates it.
- Do not delete local `node_modules/` after validation; it is ignored and local-only.
- Do not run `boot.sh`, `dist/boot.sh`, or Leia examples as routine local validation unless the
  user explicitly asks for local execution. Non-mutating help checks are acceptable when a
  README/development task specifically calls for them.
- If `boot.sh`, Leia, or `bun run build` is intentionally skipped because of task scope or repo
  policy, say so explicitly.

## Release And Distribution

- Netlify publishes committed `dist/`, but local agents should not update it directly; CI/release
  workflows own generated `dist/` changes.
- Release workflows use the Bootbox-style shell-script distribution flow. Keep `dist/boot.sh` as
  the stamped hosted entrypoint.
- Do not add unrelated package archives or upload behavior unless the release contract explicitly
  changes.
- Generated hosting changes should check `scripts/build-dist.js`, `site/`, `dist/`, `netlify.toml`,
  and release workflow assumptions together.

## `boot.sh` Invariants

- Preserve sudo preflight before Bootbox download, repo materialization, Brewfile application, or
  other machine mutation.
- Preserve the macOS 26.x support gate before sudo preflight, and keep the unsupported-major
  override hidden from normal help and README docs.
- Keep `BOOTBOX_URL` fixed and preserve Bootbox `TANAAB_*` environment isolation unless Bootbox's
  interface changes.
- Keep Bootbox delegation noninteractive; the agentbox wrapper owns the user-facing confirmation
  gate.
- Preserve the public `AGENTBOX_*` namespace and do not leak upstream Bootbox names into the
  agentbox public interface.
- Keep agentbox payload resolution aligned with the running `boot.sh`: use an explicit hidden
  payload directory for CI/development, source-relative payloads for source checkouts, and matching
  release tag archives for hosted release scripts. Do not fall back to cloning the default branch.
- Preserve `AGENTBOX_HOSTNAME` as the canonical hostname input and, when Tailscale is enabled, the
  current TANAAB-prefixed Tailscale hostname derivation.
- Preserve formula-based Tailscale install and recommended setup, while allowing explicit falsey
  auth-key values to skip Tailscale setup. Keep classic SSH as the access model, and do not
  reintroduce the Tailscale GUI cask or Tailscale SSH mode.
- Preserve managed sshd hardening through `/etc/ssh/sshd_config.d/agentbox.conf`; do not patch
  `/etc/ssh/sshd_config` directly.
- Keep the OpenClaw runner user non-admin, require a user-provided or prompted password for account
  creation/autologin, and never print, persist, generate, or debug-log that password.
- Preserve existing OpenClaw runner profile pictures; only apply a bundled `assets/profile*.png`
  image when the user has no configured picture.
- Keep agentbox health checks strict for real machines. Managed macOS runner health skips must be
  recorded in the generated state file, set only from known runner environments, and kept narrowly
  scoped to unavailable virtualized/managed settings.
- Prefer targeted edits to `boot.sh`; avoid whole-file rewrites unless the script contract is being
  intentionally replaced.
