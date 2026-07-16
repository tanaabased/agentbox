---
name: tanaab-agentbox-installer
description: Tanaab-based workflow to install, register, update, select, and resolve stable or source agentbox installations.
license: MIT
metadata:
  type: workflow
  owner: tanaab
  tags:
    - tanaab
    - workflow
    - automation
---

# agentbox installer

## Overview

Manage a deterministic user-level agentbox installation contract. Install the latest stable release,
register a source checkout, select the default, and maintain the lowercase `agentbox` command shim
without running the host bootstrap itself.

## When to Use

- Install or update the locally pinned stable agentbox release.
- Register an existing agentbox source checkout without copying it.
- Switch the default executable between `stable` and `source`.
- Inspect installation, command-shim, or PATH readiness.
- Resolve the exact executable another agentbox skill should use.

## When Not to Use

- Do not use this skill to bootstrap or mutate an agentbox host; use `$tanaab-agentbox` after an
  executable is configured.
- Do not use it to diagnose the installed host health contract; use `$tanaab-agentbox-doctor`.
- Do not treat `latest` or `edge` as installation keys. `update stable` is the explicit latest-release
  operation, and `source` is the moving development choice.
- Do not install an unverified release when GitHub omits the archive asset's SHA-256 digest or the
  downloaded bytes do not match it.

## Preconditions

- Run the shared [plugin runtime preflight](../../scripts/check-plugin-runtime.sh) and require it to
  succeed before invoking Bun. If it fails, stop, relay its explanation, and do not install Bun.
- Require `tar`, HTTPS access to GitHub Releases for stable operations, and a writable user home.
- Use `${XDG_CONFIG_HOME:-~/.config}/agentbox/config.json` for configuration.
- Use `${XDG_DATA_HOME:-~/.local/share}/agentbox/releases/` for stable payloads unless the user chooses
  another install root.
- Use `${XDG_CACHE_HOME:-~/.cache}/agentbox/` for verified download caching.
- Default the command shim to `~/.local/bin/agentbox`; warn rather than editing shell configuration
  when that directory is not on `PATH`.

## Workflow

1. Run `../../scripts/check-plugin-runtime.sh` from this skill directory. Stop without invoking Bun
   when it fails.
2. Run `bun scripts/manage-installations.js status` from this skill directory before deciding on a
   mutation. This command is offline and read-only.
3. For `install stable` or `update stable`, explain the release destination, config path, command
   shim, network access, and GitHub digest requirement. Get confirmation, then run
   `bun scripts/manage-installations.js install stable` or the equivalent `update stable` command.
   Retain older verified release payloads and downloads as inert rollback cache. Do not expose them as
   installation keys, use them as fallback executables, or remove them without an explicit cleanup
   request.
4. For source registration, resolve the requested checkout and explain that it remains a moving
   external path. Get confirmation, then run
   `bun scripts/manage-installations.js register source <path>`.
5. For default changes, verify the requested key is already available, get confirmation, then run
   `bun scripts/manage-installations.js use <stable|source>`.
6. Use `--install-root <path>` only when the user requests a nonstandard release location. Use
   `--bin-dir <path>` only when they request a nonstandard command directory.
7. Use `bun scripts/manage-installations.js resolve [stable|source]` when another skill needs the
   deterministic executable path. Omitting the key resolves `default`.
8. Present the returned JSON status. If `pathWarning` is true, explain that installation succeeded
   but the command directory is not currently on `PATH`; do not edit shell startup files.
9. When the user is preparing or reconciling a host, use the returned `handoff` to resume
   `$tanaab-agentbox` with the configured default key. Do not start host bootstrap automatically when
   executable management was the complete request.

## Checkpoints

- Before any mutation, confirm the exact operation and destination paths.
- Before replacing the command shim, stop if the destination is a regular file; never overwrite it.
- Before registering source, require a complete payload with executable `macos.sh`, Brewfile,
  health script, launchd templates, and bundled assets.
- Before installing stable, require the matching release archive and a valid GitHub SHA-256 digest.
  A failed download, extraction, version, or digest check must leave config unchanged.

## Completion Criteria

- The requested `stable` or `source` entry exists with an absolute validated path and observed
  version.
- `default` names a registered installation, never a duplicated raw path.
- The config was written atomically with private permissions.
- `~/.local/bin/agentbox`, or the requested alternative, is a symlink to the selected executable.
- Stable payloads remain complete release directories under a versioned location.
- No sudo command or agentbox host bootstrap was run.
- Any requested host follow-up was handed to `$tanaab-agentbox` with the configured default key.

## Bundled Resources

- [Installation manager](scripts/manage-installations.js): deterministic skill entrypoint.
- [Installer operations](scripts/manage-installations-lib.js): release, source, shim, and status
  orchestration.
- [Shared installation contract](../../lib/agentbox-installations.js): XDG paths, config schema,
  atomic writes, payload validation, and resolution shared with other skills.
- [Plugin runtime preflight](../../scripts/check-plugin-runtime.sh): non-mutating Bun availability
  gate shared by Bun-dependent skills.
- Repository unit tests under `test/`: cover stable/source management and the shared contract.

## Validation

- Run `bun run test` from the repository root.
- Run the Tanaab skill validator with `--skill-dir skills/agentbox-installer --type workflow`.
- Run `bun run lint` and `git diff --check`.
