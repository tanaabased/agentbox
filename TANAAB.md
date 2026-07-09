# Tanaab-based Installation

This is the baseline Tanaab command for bootstrapping a Mac as an `agentbox` host. It assumes the
`agentbox` command is already installed on `PATH` and that secrets are supplied through environment
variables instead of inline command arguments.

Set these before running the command:

```sh
export AGENTBOX_TAILSCALE_AUTHKEY="tskey-auth-..."
export AGENTBOX_OPENCLAW_PASSWORD="..."
```

```sh
agentbox \
  --hostname TANAABAGENTBOX1 \
  --tailscale-authkey "$AGENTBOX_TAILSCALE_AUTHKEY" \
  --authorized-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALZJdeUb/dHlaa65mIhSeTTADqDVJwyIZbx0ir45tEq agentbox1" \
  --authorized-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM+KZCkAQDxca/ukMGMu+AKApN2iowHMKZQ80zsWy3ce mike@tanaab.dev" \
  --brewfile Brewfile.extras \
  --brewgroup brewer:staff \
  --openclaw-identity "Emori One <emori>" \
  --openclaw-password "$AGENTBOX_OPENCLAW_PASSWORD" \
  --openclaw-service-mode user \
  --openclaw-auth-choice openai \
  --openclaw-gateway-port 18789
```

**Notes**

- Use `TANAABAGENTBOX1` for the first box, then increment the hostname for additional boxes:
  `TANAABAGENTBOX2`, `TANAABAGENTBOX3`, and so on.
- `--openclaw-identity` uses the local macOS account syntax `Full Name <shortname>`, so the local
  runner is `Emori One <emori>`.
- `--openclaw-auth-choice openai` is the ChatGPT/Codex subscription route. OpenClaw's default OAuth
  flow uses a browser callback; for headless or callback-hostile setups, use OpenClaw's device-code
  login flow after bootstrap.
