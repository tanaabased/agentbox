---
name: tanaab-agentbox-doctor
description: Tanaab-based workflow to inspect a local agentbox host, group installed health checks, and recommend the smallest scoped remediation for failures.
license: MIT
metadata:
  type: workflow
  owner: tanaab
  tags:
    - tanaab
    - workflow
    - validation
---

# agentbox doctor

## Overview

Inspect one local macOS agentbox host using its installed health contract. Present a compact grouped
status report, explain only failures and warnings by default, and recommend the smallest known
remediation without changing the host.

## When to Use

- Diagnose whether an installed agentbox host is healthy.
- Summarize host, access, dependency, OpenClaw, Tailscale, and monitoring checks without dumping the
  complete health report.
- Turn a failing agentbox health check into a focused command or manual recovery step.
- Recheck a host after an operator has applied a repair.

## When Not to Use

- Do not use this skill to install, upgrade, or rerun agentbox; hand bootstrap or reconciliation to
  `$tanaab-agentbox`.
- Do not use it for remote fleet inventory; it owns one local macOS host.
- Do not use it for general OpenClaw or Tailscale troubleshooting that is unrelated to the agentbox
  health contract.
- Do not execute a recommended repair as part of this skill. Ask for separate confirmation first.

## Preconditions

- Run on the macOS host being diagnosed.
- Run the shared [plugin runtime preflight](../../scripts/check-plugin-runtime.sh) and require it to
  succeed before invoking Bun. If it fails, stop, relay its explanation, and do not install Bun.
- Require the installed health script at `/opt/tanaab/agentbox/bin/health.sh`.
- Prefer an existing sudo timestamp. The probe uses `sudo -n` and never opens its own password
  prompt.
- Treat the installed health script as authoritative for that host version. Do not substitute the
  plugin's source copy.

## Workflow

1. Run `../../scripts/check-plugin-runtime.sh` from this skill directory. Stop without invoking Bun
   when it fails.
2. Run `bun scripts/check-host.js` from this skill directory.
3. If the result status is `authorization_required`, explain that the health state is root-readable,
   ask before running `/usr/bin/sudo -v`, and then rerun the probe. Do not silently fall back to a
   partial report.
4. If the result status is `not_installed`, stop the doctor workflow and use the returned handoff to
   direct the user to `$tanaab-agentbox` for bootstrap or reconciliation. Do not route directly to the
   installer solely because the installed health script is missing; the primary workflow will use
   `$tanaab-agentbox-installer` if executable config is also absent.
5. Present the overall status and the installed agentbox version first.
6. When installer metadata is configured, present its selected key, path, and version as the
   preferred executable for later reconciliation. Never use it as the health probe.
7. Present one line for each group: Host, Access and accounts, Dependencies, OpenClaw, Tailscale, and
   Monitoring.
8. Omit passing leaf checks unless the user asks for detail. List every returned issue and warning
   with its explanation and remediation.
9. Render remediation commands as code, but do not execute them. Manual and reconcile remediations
   are intentional when a direct command would require unavailable secrets or original install
   inputs.
10. For a `reconcile` remediation, use its handoff to `$tanaab-agentbox` and preserve the returned
    installation key when present. Do not run reconciliation without separate user confirmation.
11. If the report contains a contract mismatch or plugin/host version warning, say that the installed
    health contract may be newer than this skill's check catalog and avoid claiming the host is fully
    healthy.

## Checkpoints

- Before sudo authorization, confirm the user is willing to refresh the current terminal's sudo
  timestamp.
- Before presenting a command, verify it came from the probe's remediation object rather than being
  improvised from raw output.
- Before any later repair execution, get separate confirmation and explain the exact mutation.

## Completion Criteria

- The probe completed against the installed health script or returned a clear unavailable status.
- Every active health group is represented in the summary.
- Every surfaced failure or warning includes a focused remediation or an explicit manual recovery
  boundary.
- Every bootstrap or reconcile outcome identifies `$tanaab-agentbox` as the owning workflow.
- No password, token, auth key, or raw secret-bearing configuration was printed.
- No host mutation was performed by the doctor workflow.

## Bundled Resources

- [Health probe](scripts/check-host.js): runs the installed health report and emits normalized JSON.
- [Probe library](scripts/check-host-lib.js): parses and evaluates health output.
- [Plugin runtime preflight](../../scripts/check-plugin-runtime.sh): non-mutating Bun availability
  gate shared by Bun-dependent skills.
- Repository unit tests under `test/`: cover grouping, conditions, warnings, and contract drift.
- [Check catalog](references/checks.json): maps installed checks to user-facing groups.
- [Remediation catalog](references/remediations.json): owns focused repair recommendations.

## Validation

- Run `bun run test` from the repository root.
- Run the Tanaab skill validator with `--skill-dir skills/agentbox-doctor --type workflow`.
- Run the repository's `bun run lint` and `git diff --check` checks.
