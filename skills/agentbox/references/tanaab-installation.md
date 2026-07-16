# Tanaab-based installation

Load and apply this profile only when the user explicitly requests a Tanaab-based installation or
the Tanaab profile for the current run. Never infer that choice from the repository, organization,
current user, filesystem paths, prior conversation, an existing Tanaab hostname, or previously
configured values.

This is the baseline Tanaab command for bootstrapping a Mac as an agentbox host. Use the exact
absolute executable path returned by the agentbox installer resolver. Keep secrets in environment
variables instead of inline command arguments.

Confirm before execution that the user intends to install the two bundled authorized public keys
shown below. They are part of this profile's remote-access policy and enable key-only SSH hardening
for the managed users.

Set these before running the command:

```sh
export AGENTBOX_TAILSCALE_AUTHKEY="tskey-auth-..."
export AGENTBOX_OPENCLAW_PASSWORD="..."
```

Replace `/absolute/path/to/configured/agentbox` with the validated `installation.path` returned by
the installer resolver:

```sh
"/absolute/path/to/configured/agentbox" \
  --hostname TANAABAGENTBOX1 \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --authorized-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALZJdeUb/dHlaa65mIhSeTTADqDVJwyIZbx0ir45tEq agentbox1" \
  --authorized-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM+KZCkAQDxca/ukMGMu+AKApN2iowHMKZQ80zsWy3ce mike@tanaab.dev" \
  --brewfile Brewfile.extras \
  --brewgroup brewer:staff \
  --openclaw-identity "Emori One <emori>" \
  --openclaw-password "$AGENTBOX_OPENCLAW_PASSWORD" \
  --openclaw-service-mode system \
  --openclaw-auth-choice openai \
  --openclaw-gateway-port 18789
```

## Notes

- Use `TANAABAGENTBOX1` for the first box, then increment the hostname for additional boxes:
  `TANAABAGENTBOX2`, `TANAABAGENTBOX3`, and so on.
- `--openclaw-identity` uses the local macOS account syntax `Full Name <shortname>`, so the local
  runner is `Emori One <emori>`.
- `--openclaw-auth-choice openai` is the ChatGPT/Codex subscription route. OpenClaw's default OAuth
  flow uses a browser callback; for headless or callback-hostile setups, use OpenClaw's device-code
  login flow after bootstrap. This follow-up may still be required when `--yes` is present.
- Add `--debug` when troubleshooting bootstrap output; agentbox keeps supported secret values masked.
