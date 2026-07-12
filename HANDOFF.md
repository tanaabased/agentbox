# agentbox PR #17 handoff

This file transfers the working context for the current `agentbox` branch to another Codex instance.
It summarizes the decisions and implementation work completed in the branch and the constraints that
should guide any follow-up.

## Repository state

- Repository: `tanaabased/agentbox`
- Branch: `pirog-oc4`
- Pull request: [#17](https://github.com/tanaabased/agentbox/pull/17), currently a draft against `main`
- Feature head before this handoff commit: `6b064c4`
- The worktree was clean before adding this file.
- Compare the complete feature with `git diff origin/main...HEAD`.
- Review the branch history with `git log --reverse --oneline origin/main..HEAD`.

On another computer, resume with:

```sh
git clone git@github.com:tanaabased/agentbox.git
cd agentbox
git switch pirog-oc4
git pull --rebase origin pirog-oc4
```

Read `AGENTS.md` before changing the repository and `examples/AGENTS.md` before changing any Leia
example.

## Product and implementation boundaries

- Spell the product and CLI as lowercase `agentbox` in prose and output.
- `macos.sh` is the shipped macOS bootstrap source. Do not run it locally as routine validation; it
  mutates the machine.
- Do not edit, build, stage, or commit `dist/` during routine work. CI owns generated publish output.
- Keep changes narrow and preserve the single top-level `SCRIPT_VERSION` assignment.
- Leia examples are executable integration specifications. Many mutate fresh GitHub-hosted macOS
  runners and are intentionally not run on a development Mac.
- Routine local validation is `bun run lint`, targeted shell parsing, and `git diff --check`.
- Long term, the project should become a Bun-based management CLI with subcommands, but that work is
  deferred until the planned Bun update. Do not begin that rewrite as part of this branch.

## What this branch accomplished

### Sudo and Bootbox flow

The sudo ordering is intentional and should not be moved back without revisiting the Homebrew
interaction:

1. Before Bootbox download, payload materialization, Brewfile application, or other mutation,
   `agentbox` performs only a non-prompting capability check: `/usr/bin/sudo` must exist and the
   invoking user must be a macOS administrator.
2. Interactive runs show the plan and let Bootbox apply Brewfiles before establishing the managed
   agentbox sudo session. Homebrew invalidates the existing sudo timestamp, so authenticating before
   Bootbox would commonly make the user enter the password twice.
3. After Bootbox finishes, interactive runs establish sudo authorization and start the keepalive for
   the remaining privileged work.
4. CI and explicitly non-interactive runs cannot prompt. They must have reusable non-interactive sudo
   before Bootbox and delegate that session through `BOOTBOX_EXTERNAL_SUDO=1`.

Additional sudo behavior now includes:

- clearer initial and reauthorization messages;
- a managed keepalive with recovery for interactive timestamp loss;
- actionable failure when sudo accepts authentication but policy prevents reusable authorization;
- `HOMEBREW_NO_ASK=1` on every internal Bootbox invocation so Homebrew cannot introduce an
  unexpected password prompt beneath the agentbox interaction layer;
- Bootbox remains non-interactive because agentbox owns the confirmation gate.

The current sudo behavior is codified in `AGENTS.md`; preserve those invariants.

### Final sudo test strategy

Several attempts to drive a real password prompt through a pseudo-terminal on GitHub Actions hung or
failed for runner-specific reasons. The final design deliberately avoids pretending that hosted CI is
a reliable interactive terminal:

- `examples/sudo/README.md` creates a real password-required macOS administrator and uses real
  `/usr/bin/sudo`.
- It verifies the important non-interactive safety boundary: unavailable reusable sudo fails before
  Bootbox applies Brewfiles or agentbox installs its payload.
- It does not attempt to enter a real password interactively in GitHub Actions.
- Successful end-to-end bootstrap and health behavior remain covered by the domain examples.
- `CI` is forwarded explicitly through the switched-user test because `sudo` strips it; this was a
  test-environment correction, not a broader functional change to interaction detection.
- The earlier binary stubs, Expect driver, and overly unit-like sudo fixtures were removed.

Do not restore the old interactive test unless there is a genuinely controllable runner environment.
A small sudo spy was discussed, but the final branch does not use one because the narrower real-sudo
negative test proves the contract without hanging.

### Tailscale service and rerun repairs

The branch tightened the managed Tailscale service model:

- repaired ownership and permissions for managed Tailscale state;
- expanded health reporting and examples around those permissions;
- removes conflicting Homebrew or official Tailscale launchd jobs when reconciling the managed
  daemon;
- resumes an existing stopped identity with `tailscale up` instead of requiring a new auth key;
- aborts on a joined identity whose hostname differs from the agentbox-derived expected hostname,
  rather than silently keeping an inconsistent identity.

The rerun example now exercises a stopped existing identity, conflicting launchd state, preserved
gateway logs, and final health recovery.

### OpenClaw gateway ownership and reruns

The branch repairs OpenClaw gateway log ownership and keeps the logs private to the runner while
preserving existing content during reconciliation.

Interactive onboarding behavior is now rerun-aware:

- first setup still permits OpenClaw's normal interactive onboarding when a terminal is available;
- before a later run, agentbox validates the runner's OpenClaw config and reads `gateway.mode` as the
  OpenClaw runner;
- a valid config with `gateway.mode=local` is reconciled through non-interactive onboarding instead
  of reopening the wizard;
- missing, invalid, or non-local configuration keeps the visible onboarding path so repair is not
  hidden;
- all gateway-owned settings are still passed during reconciliation, including service mode,
  loopback bind, port, Tailscale exposure, and token authentication.

The onboarding command continues to use gateway token auth and
`--suppress-gateway-token-output`. Do not generate a second token, duplicate it into agentbox service
environment files, or print it after setup.

### OpenClaw mDNS name

For agentbox-owned `system` service mode, the generated owner-only gateway service environment now
sets:

```text
OPENCLAW_MDNS_HOSTNAME=<validated agentbox hostname>
```

This aligns OpenClaw's Bonjour/mDNS advertisement with the hostname configured through agentbox.
Native `user` service mode remains OpenClaw-managed and intentionally does not receive this
agentbox-specific override.

### Health completion UX

The full health report is no longer printed during every normal completion:

- agentbox captures `health.sh --check` output;
- `--debug` includes the multiline health report through `debug_multi`;
- success prints a concise green `agentbox setup succeeded` status;
- failure prints a concise red failure status, exits nonzero, and shows the manual
  `sudo /opt/tanaab/agentbox/bin/health.sh --report` command.

The helper was named `debug_multi` for consistency with the existing `warn_multi` and `abort_multi`
surface.

### OpenClaw dashboard and gateway token UX

The gateway token is owned by the OpenClaw runner's configuration. A useful manual finding was that:

```sh
sudo -iu emori "$(brew --prefix)/bin/openclaw" config get gateway.auth.token
```

runs correctly as the runner, but OpenClaw intentionally returns a redacted value. Logging into the
runner account directly does not change that behavior.

The supported browser flow is:

```sh
sudo -iu emori "$(brew --prefix)/bin/openclaw" dashboard
```

Replace `emori` with the configured runner short name. `openclaw dashboard` uses the runner-owned
configuration, opens the authenticated loopback Dashboard, and copies its authenticated URL. The
`--no-open` form copies the URL without launching a browser; copying may be unavailable in a purely
headless or SSH-only session, and OpenClaw does not print the hidden token as a fallback.

This matters because Tailscale Serve can authenticate the tailnet Control UI request with Tailscale
identity headers, while a direct loopback request does not carry those headers and therefore needs
the gateway token.

The final completion output now prints the fully resolved admin-side dashboard command only after
health succeeds. It substitutes the actual runner username and Homebrew prefix rather than showing
environment variables or placeholders. `README.md` documents the default command, and `ADVANCED.md`
documents direct-runner use, admin use, `--no-open`, clipboard limitations, and redaction. Leia
assertions verify both default and custom-runner output without launching a browser.

Relevant upstream references:

- [OpenClaw config CLI](https://docs.openclaw.ai/cli/config)
- [OpenClaw dashboard CLI](https://docs.openclaw.ai/cli/dashboard)
- [OpenClaw Tailscale behavior](https://docs.openclaw.ai/gateway/tailscale)

## Explicit non-decisions

- Do not move the interactive sudo authorization before Bootbox solely to make ordering look simpler;
  that recreates the double-password experience after Homebrew clears the timestamp.
- Do not add machine-wide `AGENTBOX_*` shell environment variables merely to shorten the documented
  dashboard command. `/etc/paths.d/00-agentbox-homebrew` is only a PATH mechanism, not an arbitrary
  environment file.
- The owner-only OpenClaw service environment is for the gateway process, not a global admin-shell
  discovery contract.
- If machine discovery or dashboard access becomes a repeated operator action, prefer a future
  `agentbox status`, `agentbox env`, or `agentbox dashboard` subcommand after the Bun CLI work.
- Do not print or document raw-file extraction of the gateway token. The native dashboard workflow
  avoids leaking secrets into terminal output or logs.
- No Caddy integration or alternate local gateway proxy was added.

## Validation and testing posture

For the most recent code and documentation changes, local non-mutating validation passed:

```sh
bash -n macos.sh bin/health.sh
bun run lint
git diff --check
```

The agentbox bootstrap, OpenClaw dashboard, and mutating Leia examples were not run locally because
they change machine state. GitHub Actions is the intended environment for the Leia matrix.

When editing executable Leia blocks, remember that Leia embeds them in JavaScript template literals:

- do not use literal backticks;
- avoid braced expansions such as `${VAR}`;
- use `$(command)` and `$VAR` where possible;
- follow the complete locality and fixture rules in `examples/AGENTS.md`.

## Useful commit landmarks

- `404b355` fixes managed Tailscale daemon ownership.
- `19f427b` fixes OpenClaw gateway log ownership.
- `31f4ba9` moves interactive sudo authorization after Bootbox.
- `0f74b7a` separates early sudo capability checks from authorization.
- `8220465` begins the real-sudo end-to-end coverage direction.
- `c00754d` reduces sudo coverage to the stable hosted-CI contract.
- `3e56a2a` forwards `CI` into the switched-user sudo example.
- `966aabf` resumes stopped Tailscale identities.
- `c0c11fe` reconciles valid OpenClaw reruns non-interactively.
- `92b2625` aligns the system-mode OpenClaw mDNS hostname.
- `d1d776e` simplifies post-bootstrap health output.
- `6b064c4` adds the dashboard completion and documentation flow.

## Recommended next step

There is no known unfinished implementation from this session. On the next computer:

1. pull `pirog-oc4`;
2. read this file plus the two `AGENTS.md` guidance files;
3. inspect PR #17 and its latest CI after this handoff-only commit;
4. address any concrete failure or review feedback without reopening the settled sudo, token, or
   service-environment decisions unless new evidence requires it;
5. otherwise review the complete diff against `main` and prepare the PR for merge.
