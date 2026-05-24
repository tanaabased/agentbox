# Repo Guidance For `agentbox`

This root `AGENTS.md` is the repo-local override for Codex work in this repository. Keep
repo-specific agent policy here and do not duplicate it in nested `AGENTS.md` files unless
explicitly asked.

## Purpose

- This repo prepares a physically accessible macOS 26+ Mac as a headless Tanaab agentbox base
  profile.
- Keep the repo focused on base-machine setup: macOS settings, SSH, Tailscale, launchd, recovery,
  and validation.
- Do not add agent runtime setup, trading credentials, app-specific services, router port
  forwarding, or public WAN exposure here.

## Source Of Truth

- `boot.sh` is the shipped shell entrypoint and main bootstrap surface.
- `Brewfile` is the source of truth for base Homebrew packages.
- `README.md` is the human-facing setup, usage, and post-bootstrap surface.
- `examples/**/README.md` files are Leia-backed executable contract specs consumed in CI.
- `dist/` is generated publish output for Netlify hosting and release preparation.
- `scripts/build-dist.js`, `site/`, `netlify.toml`, release workflows, and the committed `dist/`
  files own the hosted-script publishing surface.

## Build Artifacts

- Do not edit, regenerate, stage, or commit files under `dist/` during local agent work.
- `dist/` is CI/release-owned output. GitHub Actions may regenerate and stamp it during build,
  test, release, or hosting workflows.
- Make source changes in `boot.sh`, `site/`, or `scripts/build-dist.js`; leave `dist/` unchanged
  unless the user explicitly asks for a local generated-artifact update.
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
- Any `boot.sh` public interface change must check `README.md`, `examples/cli-contract`, and the
  affected mutating examples.
- Any machine behavior change in `boot.sh` must check README setup/after-bootstrap guidance plus
  the affected `envvars`, `options`, or `version` Leia scenarios.
- Keep planned-action output aligned with actual execution order.

## Secrets And Logging

- Never commit Tailscale auth keys, SSH private keys, API tokens, passwords, or machine-specific
  generated secret files.
- Do not commit machine-specific SSH `authorized_keys` files. Pass public authorized keys at
  bootstrap with `AGENTBOX_AUTHORIZED_KEY` or repeatable `--authorized-key`.
- Treat real `AGENTBOX_TAILSCALE_AUTHKEY` values as runtime-only secrets. Mask them in CLI output
  and prefer environment variable usage over CLI flags in secret-sensitive examples. Explicit
  falsey values disable Tailscale setup and are not secrets.
- Preserve token masking in debug output and do not reintroduce raw argument logging.
- Do not add the Tailscale GUI cask unless the project intentionally changes away from headless
  daemon setup.

## Leia Example Style

- Leia examples under `examples/` are CI-owned executable scenarios. They may mutate GitHub-hosted
  macOS runners, but should not be treated as routine local validation.
- Prefer direct command pipelines, command substitutions, and deterministic inline values over
  writing files just to inspect them later.
- Use `TMPDIR` for durable fixtures, unavoidable logs, and helper internals only.
- Keep generated SSH public/private key fixtures in `TMPDIR`; they are real test inputs, not scratch
  assertion files.
- Put repeated destructive runner cleanup in `scripts/cleanup-agentbox-runner.sh` instead of
  duplicating cleanup blocks across README scenarios.

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
- Keep `BOOTBOX_URL` fixed and preserve Bootbox `TANAAB_*` environment isolation unless Bootbox's
  interface changes.
- Preserve the public `AGENTBOX_*` namespace and do not leak upstream Bootbox names into the
  agentbox public interface.
- Keep the default public source as `https://github.com/tanaabased/agentbox.git`, the fixed target
  as `~/tanaab/agentbox`, and skip-or-replace behavior controlled by `--force`.
- Keep `--agentbox-version` aligned with GitHub tag archive installs.
- Preserve `AGENTBOX_HOSTNAME` as the canonical hostname input and, when Tailscale is enabled, the
  current TANAAB-prefixed Tailscale hostname derivation.
- Preserve formula-based Tailscale install and recommended setup, while allowing explicit falsey
  auth-key values to skip Tailscale setup. Keep classic SSH as the access model, and do not
  reintroduce the Tailscale GUI cask or Tailscale SSH mode.
- Prefer targeted edits to `boot.sh`; avoid whole-file rewrites unless the script contract is being
  intentionally replaced.
