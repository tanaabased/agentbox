# Codex Plugin

The `agentbox` Codex plugin is an optional companion to the hosted bootstrap script. It adds guided
workflows for selecting an `agentbox` executable, planning or running bootstrap and reconciliation,
and inspecting an installed host. The hosted script remains the primary setup path and does not
require Codex.

## Requirements

- Use a Codex surface that supports plugins, such as Codex in the ChatGPT desktop app or Codex CLI.
- Install Bun `>=1.3.0 <1.4.0` on the Mac where the plugin workflows will run.
- Run bootstrap, reconciliation, and doctor workflows on the Mac being managed. The plugin does not
  provide remote fleet orchestration.

See the official [Plugins](https://learn.chatgpt.com/docs/plugins) documentation for currently
supported Codex surfaces and plugin-browser behavior.

## Installation

Each Codex-enabled GitHub Release includes a complete `agentbox-<tag>.tar.gz` archive containing the
plugin manifest, skills, runtime helpers, and bootstrap payload.

1. Download the archive for the desired version from
   [GitHub Releases](https://github.com/tanaabased/agentbox/releases).
   Verify its SHA-256 value against the digest GitHub publishes for that release asset.
2. Extract it into an empty personal plugin directory:

```sh
mkdir -p "$HOME/.codex/plugins/agentbox"
tar -xzf "$HOME/Downloads/agentbox-<tag>.tar.gz" \
  -C "$HOME/.codex/plugins/agentbox"
```

When updating, replace the existing plugin directory with the new archive instead of overlaying
files from different versions.

3. Create or update `~/.agents/plugins/marketplace.json`. If the file already exists, merge the
   `agentbox` object into its existing `plugins` array instead of replacing the file:

```json
{
  "name": "personal",
  "interface": {
    "displayName": "Personal Plugins"
  },
  "plugins": [
    {
      "name": "agentbox",
      "source": {
        "source": "local",
        "path": "./.codex/plugins/agentbox"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Tanaab-based"
    }
  ]
}
```

The source path is relative to the personal marketplace root. See the official
[Build plugins](https://learn.chatgpt.com/docs/build-plugins) documentation for the marketplace
format and local-plugin behavior.

4. Restart the ChatGPT desktop app and install `agentbox` from the Plugins view, or open `/plugins`
   in a new Codex CLI session and install it from the personal marketplace.
5. Start a new task or CLI session so the installed skills are available.

## Plugin Workflows

The plugin keeps executable management, host mutation, and health diagnosis in separate skills:

| Skill                        | Owns                                                                                 | Does not own                                          |
| ---------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------- |
| `$tanaab-agentbox-installer` | Installing or updating stable releases, registering source checkouts, and selection. | Running bootstrap or diagnosing the installed host.   |
| `$tanaab-agentbox`           | Planning and running bootstrap or reconciliation with the selected executable.       | Installing executables or improvising health repairs. |
| `$tanaab-agentbox-doctor`    | Read-only local health inspection and focused remediation recommendations.           | Running bootstrap, reconciliation, or repairs.        |

### Configure an Executable

Use the installer when Codex does not yet have a configured stable release or source checkout:

```text
Use $tanaab-agentbox-installer to install the latest stable agentbox release and select it as the default.
```

The installer verifies stable release archives with the digest published by GitHub. Creating an
`agentbox` command on `PATH` is opt-in and is not required for the other plugin skills.

### Bootstrap or Reconcile a Host

Use the primary skill to gather inputs, resolve the configured executable, present the mutation
summary, and run `agentbox` after confirmation:

```text
Use $tanaab-agentbox to plan an interactive bootstrap for this Mac.
```

For an existing host, ask it to reconcile the installation instead. The skill preserves secret
environment-variable references, lets `agentbox` own sudo and hidden-password prompts, and does not
silently add noninteractive or force flags.

### Diagnose Host Health

After bootstrap or reconciliation succeeds, use the doctor on the local agentbox host:

```text
Use $tanaab-agentbox-doctor to inspect this local agentbox host.
```

The doctor reads `/opt/tanaab/agentbox/bin/health.sh`, groups the result into host, access,
dependencies, OpenClaw, Tailscale, and monitoring status, and explains failures and warnings. It
uses non-prompting sudo first and asks before refreshing authorization when root-readable state is
unavailable.

The doctor recommends repairs but does not execute them. Apply a recommended command or handoff only
after a separate confirmation, then rerun the doctor to verify the result.

## Version Alignment

The installed health script is authoritative for the host version. The doctor warns when the plugin
and installed host versions differ or when its check catalog does not fully match the installed
health contract. Align the plugin and host versions before relying on version-specific remediation
details.

For direct health commands without Codex, see
[Verification Details](./ADVANCED.md#verification-details).
