---
name: tanaab-agentbox
description: Tanaab-based workflow to plan, configure, and run agentbox bootstrap or reconciliation using the configured installation.
license: MIT
metadata:
  type: workflow
  owner: tanaab
  tags:
    - tanaab
    - workflow
    - operations
---

# agentbox

## Overview

Plan and run an agentbox bootstrap or reconciliation with explicit, secret-safe inputs. Resolve the
executable from the agentbox installation config, use the selected executable's current help output
as the option contract, preserve user choices across command assembly, and hand completed hosts to
the doctor workflow for verification.

## When to Use

- Explain how to run agentbox or what its bootstrap changes on a supported Mac.
- Gather inputs and assemble a first-bootstrap command.
- Rerun agentbox to reconcile an existing host with an explicitly requested desired state.
- Run the explicitly requested Tanaab-based installation profile.

## When Not to Use

- Do not install, update, register, or select an agentbox executable; use
  `$tanaab-agentbox-installer`.
- Do not diagnose host health or improvise repairs from raw output; use `$tanaab-agentbox-doctor`.
- Do not use this skill for general OpenClaw, Tailscale, Homebrew, SSH, or macOS administration that
  is unrelated to an agentbox run.
- Do not load or apply the Tanaab-based installation profile unless the user explicitly requests it
  for the current run.

## Preconditions

- General explanations may use the bundled repository guidance without running on the target host.
  Before execution, run on the macOS host being prepared or reconciled.
- Before execution, require macOS 26.x on `arm64` or `x86_64`, a sudo-capable administrator, network
  access, and physical or administrator recovery access.
- Run the shared [plugin runtime preflight](../../scripts/check-plugin-runtime.sh) before consulting
  installation config for exact option guidance, command planning, or execution. General
  explanations do not require Bun or installation config. If preflight fails when required, stop and
  relay its bare-Mac or existing-host guidance.
- Treat the agentbox installation config as the sole executable authority. Never fall back to a
  command found on `PATH`, a source checkout, another configured key, or the hosted script.
- Keep passwords and auth keys out of chat, command literals, debug output, and displayed plans.

## Workflow

### Executable Resolution

1. Run `../../scripts/check-plugin-runtime.sh` from this skill directory. Stop when it fails.
2. Run `bun ../agentbox-installer/scripts/manage-installations.js status` from this skill directory.
3. If status is `invalid_config`, offer to use `$tanaab-agentbox-installer` for its backup-and-reset
   recovery workflow. Do not attempt resolution or edit config directly. Preserve the requested
   selector and gathered inputs when resuming after repair.
4. If the user explicitly requests `stable` or `source`, run
   `bun ../agentbox-installer/scripts/manage-installations.js resolve <key>`.
5. Otherwise, run `bun ../agentbox-installer/scripts/manage-installations.js resolve` to select the
   configured `default`.
6. If config is absent, `default` is unset, or the requested key is unavailable, offer to use
   `$tanaab-agentbox-installer`. Do not run that mutating workflow without confirmation. When the
   user approves it, preserve the requested selector and gathered inputs, complete the installer
   workflow, then rerun resolution and resume this workflow.
7. Treat `stable` and `source` as the only supported installation selectors. Do not interpret an
   arbitrary semantic version as a configured installation key.
8. Use only the returned absolute `installation.path`. Before planning a run, execute that path with
   `--version` and `--help`; stop if either command fails.

### Input Decisions

- Reuse choices already supplied in the current request. Do not ask the user to restate them.
- Preserve the selected executable key. Do not silently switch from `stable` to `source`, or the
  reverse, when validation fails.
- Use the executable's documented defaults unless the user requests an override. Explain defaults
  that materially affect access, accounts, or service ownership.
- For a first bootstrap, resolve these decisions before execution:
  - Hostname, or acceptance of the displayed default.
  - Tailscale enrollment with an auth key already available in the environment, or explicit skip.
  - SSH authorized-key files or public keys, or no key installation. Explain that providing keys
    enables key-only SSH hardening for managed users.
  - OpenClaw runner identity, or acceptance of the displayed default.
  - OpenClaw runner password through agentbox's hidden prompt or an existing environment variable.
  - Initial OpenClaw model-auth choice, or explicit acceptance of `skip`.
- Use `system` gateway service mode, port `18789`, and the default Homebrew group unless the user asks
  for alternatives.
- Ask about extra Brewfiles only when the request implies additional operator software or supplies a
  Brewfile source.
- Treat `--force`, `--debug`, custom brew groups, user service mode, custom gateway ports, and
  `--openclaw-auth-env` as advanced overrides rather than routine questions.
- Use `--yes` only when the user explicitly requests a noninteractive run and all required inputs are
  available without prompting.

### Secret Handling

- Ask whether required secret environment variables are populated; never ask the user to paste
  their values into chat.
- Check only presence, never values, and do not print the environment while checking.
- Display secret-bearing arguments as quoted environment-variable references such as
  `"$AGENTBOX_TAILSCALE_AUTHKEY"` and `"$AGENTBOX_OPENCLAW_PASSWORD"`.
- Never invent, generate, persist, transform, or forward a password, Tailscale auth key, API key, or
  gateway token.
- Prefer agentbox's hidden password prompt for an interactive run when no password environment
  variable is already available.

### Execution

1. Classify the request as explanation, command planning, first bootstrap, or reconciliation rerun.
2. For a general explanation that does not require the selected executable's exact option contract,
   use the bundled repository guidance and do not run runtime preflight or consult installation
   config. Load the Tanaab-based reference only when that profile was explicitly requested.
3. For exact option guidance, command planning, first bootstrap, or reconciliation, resolve and
   validate the executable through **Executable Resolution**.
4. If the user explicitly requests a Tanaab-based installation, load
   [Tanaab-based installation](references/tanaab-installation.md). Otherwise, do not read or apply
   that reference.
5. Gather only unresolved choices from **Input Decisions** and verify secret presence without
   exposing values.
6. Assemble one command using the exact resolved executable path. Preserve repeated options such as
   `--authorized-key` and `--brewfile` in user-specified order.
7. Present the command with secret environment-variable references intact. Summarize consequential
   behavior: account creation, SSH hardening, Tailscale enrollment, Homebrew group changes, OpenClaw
   service ownership, and any nondefault authentication or port choice.
8. For a normal interactive run, launch agentbox and use its own displayed plan as the final
   confirmation gate. Do not add `--yes` merely to avoid terminal interaction.
9. For a user-requested `--yes` run, obtain explicit confirmation of the assembled command and
   summarized mutations before launching it.
10. Let agentbox own sudo and hidden password prompts. Never attempt to supply either password on the
    user's behalf.
11. Preserve the complete exit status and actionable failure text. Do not claim success from partial
    output.
12. After a successful run, use `$tanaab-agentbox-doctor` for installed-host verification. Do not
    substitute this skill's own ad hoc health checks.

### Tanaab-Based Boundary

- Require an explicit request for the Tanaab-based installation or Tanaab profile on every run.
- Never infer that choice from the repository owner, organization, current user, filesystem paths,
  prior conversation, an existing Tanaab hostname, or previously configured values.
- Before execution, state that the profile installs its bundled authorized public keys and confirm
  that this is the requested access policy.
- Keep the profile's environment-variable references secret-safe and retain its OpenAI browser or
  device-code follow-up caveat even for `--yes` runs.

## Checkpoints

- Before running agentbox, confirm the resolved installation key, executable path, hostname,
  Tailscale choice, SSH-key choice, runner identity, service mode, and auth choice.
- Before adding `--yes`, confirm that every required prompt has a supplied noninteractive input and
  that the user accepts the complete mutation summary.
- Before using `--force`, identify the exact replacement operation that requires it and get separate
  confirmation.
- If the executable's `--help` output conflicts with this skill, follow the executable and report the
  contract drift.

## Completion Criteria

- The requested explanation or command plan is complete, or agentbox exited successfully after the
  user accepted its plan.
- When executable resolution was required, it came from the requested configured key or configured
  `default` without fallback.
- Every explicit input is represented exactly once, except intentionally repeatable options.
- No secret value or administrator password was printed, persisted, or passed through chat.
- A successful host run is handed to `$tanaab-agentbox-doctor` for verification.

## Bundled Resources

- [Tanaab-based installation](references/tanaab-installation.md): explicit-only personal installation
  profile.
- [Plugin runtime preflight](../../scripts/check-plugin-runtime.sh): non-mutating Bun availability
  gate shared by Bun-dependent skills.
- [Installer manager](../agentbox-installer/scripts/manage-installations.js): authoritative config
  status and executable resolution surface.
- [Main usage guide](../../README.md): public quickstart and common input contract.
- [Advanced reference](../../ADVANCED.md): detailed option behavior, security boundaries, and
  recovery notes.

## Validation

- Run the Tanaab skill validator with `--skill-dir skills/agentbox --type workflow`.
- Compare the decision surface with `./macos.sh --help` without running a bootstrap.
- Run `bun run test`, `bun run lint`, and `git diff --check` from the repository root.
