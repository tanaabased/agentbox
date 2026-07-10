# Leia Example Guidance

This file applies when editing `examples/**/README.md`. These README files are executable Leia specs
consumed in CI, and many scenarios mutate GitHub-hosted macOS runners.

## General Style

- Prefer behavior-focused `# should` labels over scenario labels.
- Keep each `# should` block focused on one observable contract. Split blocks whose title needs
  `and`/`or`, mixes unrelated domains, or grows past roughly 12-15 command lines unless the block is
  one coherent multiline command.
- Treat each blank-line-separated Leia block as a separate script. Do not rely on shell variables,
  functions, or working-directory changes persisting across `should` blocks.
- Prefer direct command pipelines, command substitutions, and deterministic inline values over
  writing files just to inspect them later.
- Do not capture command output into shell variables just to grep it later. If capture is needed to
  preserve a failing command's status, print the captured output before assertions.
- For health-report assertions, print and match targeted `--report` lines before running the final
  `--check` gate so CI logs show the mismatch that caused the failure.

## Example Placement

- `inputs` owns non-mutating public interface checks: help text, displayed defaults, input
  validation, and option/env precedence.
- `defaults` owns the baseline happy-path bootstrap with default `agentbox`-owned settings.
- Named domain examples own focused behavior such as Tailscale, Homebrew, SSH, OpenClaw, users,
  rerun, and payload resolution.
- Add coverage to the narrowest existing example that owns the behavior. Add a new example only when
  the behavior needs incompatible bootstrap inputs, crosses enough domains to blur an existing
  example, or intentionally needs another successful `agentbox` run.

## Mutating Examples

- Mutating examples should run the prepared `agentbox` entrypoint once unless the example is
  explicitly about rerun, idempotency, or payload resolution behavior.
- Use fixed, readable local resource names for resources that exist only on ephemeral runners. Keep
  externally registered or shared resources, especially Tailscale hostnames, unique per scenario and
  run.
- Do not add preemptive cleanup or destroy blocks just to reset machine state; each matrix job starts
  on a fresh hosted VM.
- Prefer `--retry 0` for mutating examples so partial bootstrap failures are not retried on the same
  VM.
- Do not add expected-failure probes to mutating bootstrap examples when the failure can occur after
  machine state changes. Keep failure-contract checks in non-mutating CLI examples or make them fail
  during input validation before bootstrap side effects.

## Shell Fixtures

- Use `TMPDIR` for durable fixtures, unavoidable logs, and helper internals only.
- Keep generated SSH public/private key fixtures in `TMPDIR`; they are real test inputs, not scratch
  assertion files.
- When a mutating example provides authorized keys, verify localhost SSH login with the generated
  private key fixture instead of only inspecting `authorized_keys`.
- Leia embeds executable command blocks in JavaScript template literals. Inside those blocks, do not
  use literal backticks or braced shell expansions such as `${VAR}`.
- Use `$(command)` instead of backtick command substitution and `$VAR` instead of `${VAR}`. When
  braces are required for shell semantics, move that logic into a checked-in example-local helper.
- These restrictions do not apply to Markdown fences or inline code outside executable blocks;
  shell tests using `[ ... ]` or `[[ ... ]]` remain safe.
- Do not give setup fixture commands standalone `# should` blocks unless the fixture state itself is
  the contract. Put `mkdir -p "$TMPDIR"` beside the first fixture that writes into `TMPDIR`.

## Domain Checks

- Keep OpenClaw runner account creation checks focused on identity and home-directory state. Assert
  privilege, autologin, SSH, and group membership in separate health-backed or domain-specific
  blocks.
- Only test runner profile pictures when preserving an existing picture is the scenario contract.
- Defaults-focused examples should avoid overriding `agentbox`-owned default values while still
  providing required CI inputs such as payload paths, passwords, secrets, and unique shared-resource
  names.
