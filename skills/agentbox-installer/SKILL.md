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

- Do not use this skill to bootstrap or mutate an agentbox host.
- Do not use it to diagnose the installed host health contract; use `$tanaab-agentbox-doctor`.
- Do not treat `latest` or `edge` as installation keys. `update stable` is the explicit latest-release
  operation, and `source` is the moving development choice.
- Do not install an unverified release when its SHA-256 asset is absent or mismatched.

## Preconditions

- Require Bun, `tar`, HTTPS access to GitHub Releases for stable operations, and a writable user home.
- Use `${XDG_CONFIG_HOME:-~/.config}/agentbox/config.json` for configuration.
- Use `${XDG_DATA_HOME:-~/.local/share}/agentbox/releases/` for stable payloads unless the user chooses
  another install root.
- Use `${XDG_CACHE_HOME:-~/.cache}/agentbox/` for verified download caching.
- Default the command shim to `~/.local/bin/agentbox`; warn rather than editing shell configuration
  when that directory is not on `PATH`.

## Workflow

1. Run `bun scripts/manage-installations.js status` from this skill directory before deciding on a
   mutation. This command is offline and read-only.
2. For `install stable` or `update stable`, explain the release destination, config path, command
   shim, network access, and checksum requirement. Get confirmation, then run
   `bun scripts/manage-installations.js install stable` or the equivalent `update stable` command.
3. For source registration, resolve the requested checkout and explain that it remains a moving
   external path. Get confirmation, then run
   `bun scripts/manage-installations.js register source <path>`.
4. For default changes, verify the requested key is already available, get confirmation, then run
   `bun scripts/manage-installations.js use <stable|source>`.
5. Use `--install-root <path>` only when the user requests a nonstandard release location. Use
   `--bin-dir <path>` only when they request a nonstandard command directory.
6. Use `bun scripts/manage-installations.js resolve [stable|source]` when another skill needs the
   deterministic executable path. Omitting the key resolves `default`.
7. Present the returned JSON status. If `pathWarning` is true, explain that installation succeeded
   but the command directory is not currently on `PATH`; do not edit shell startup files.

## Checkpoints

- Before any mutation, confirm the exact operation and destination paths.
- Before replacing the command shim, stop if the destination is a regular file; never overwrite it.
- Before registering source, require a complete payload with executable `macos.sh`, Brewfile,
  health script, launchd templates, and bundled assets.
- Before installing stable, require the matching release archive and `.sha256` asset. A failed
  download, extraction, version, or checksum check must leave config unchanged.

## Completion Criteria

- The requested `stable` or `source` entry exists with an absolute validated path and observed
  version.
- `default` names a registered installation, never a duplicated raw path.
- The config was written atomically with private permissions.
- `~/.local/bin/agentbox`, or the requested alternative, is a symlink to the selected executable.
- Stable payloads remain complete release directories under a versioned location.
- No sudo command or agentbox host bootstrap was run.

## Bundled Resources

- [Installation manager](scripts/manage-installations.js): deterministic skill entrypoint.
- [Installer operations](scripts/manage-installations-lib.js): release, source, shim, and status
  orchestration.
- [Shared installation contract](../../lib/agentbox-installations.js): XDG paths, config schema,
  atomic writes, payload validation, and resolution shared with other skills.
- Repository unit tests under `test/`: cover stable/source management and the shared contract.

## Validation

- Run `bun run test` from the repository root.
- Run the Tanaab skill validator with `--skill-dir skills/agentbox-installer --type workflow`.
- Run `bun run lint` and `git diff --check`.
