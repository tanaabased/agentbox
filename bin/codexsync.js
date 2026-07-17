#!/usr/bin/env bun

import { resolve } from 'node:path';

import { runCodexsyncCheck, writeCodexsyncLine } from '../lib/codexsync-check.js';
import {
  CODEXSYNC_COMMANDS,
  DEFAULT_REPO_ROOT,
  MANAGED_PLUGIN_PATHS,
  resolveCodexsyncContext,
} from '../lib/codexsync-context.js';
import { runCodexsyncSync } from '../lib/codexsync-sync.js';
import { validatePlugin } from '../lib/plugin-validation.js';

function usage(context) {
  return `Usage: codexsync <check|sync|validate> [options]

Validate the agentbox Codex plugin or refresh an existing installed cache.

Commands:
  check      Compare source with the exact-version installed plugin cache.
  sync       Refresh an existing exact-version plugin cache from source.
  validate   Validate the plugin manifest, declared resources, and bundled skills.

Options:
  --repo-root PATH   Source repository root. [default: ${context.repoRoot}]
  --cache-path PATH  Installed cache path for check or sync. [default: ${context.cachePath}]
  -V, --version      Show the package version.
  -h, --help         Show this help.

Managed paths:
${MANAGED_PLUGIN_PATHS.map((managedPath) => `  ${managedPath}`).join('\n')}

sync never creates a missing plugin cache; install agentbox through Codex first.
`;
}

function optionValue(argument, name) {
  if (argument === name) return null;
  if (argument.startsWith(`${name}=`)) return argument.slice(name.length + 1);
  return undefined;
}

function parseArguments(argv) {
  const parsed = {
    cachePathOverride: null,
    command: null,
    help: false,
    repoRoot: DEFAULT_REPO_ROOT,
    version: false,
  };
  const positionals = [];

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '-h' || argument === '--help') {
      parsed.help = true;
      continue;
    }
    if (argument === '-V' || argument === '--version') {
      parsed.version = true;
      continue;
    }

    const repoRootValue = optionValue(argument, '--repo-root');
    if (repoRootValue !== undefined) {
      const value = repoRootValue ?? argv[++index];
      if (!value) throw new Error('--repo-root requires a path');
      parsed.repoRoot = resolve(value);
      continue;
    }
    const cachePathValue = optionValue(argument, '--cache-path');
    if (cachePathValue !== undefined) {
      const value = cachePathValue ?? argv[++index];
      if (!value) throw new Error('--cache-path requires a path');
      parsed.cachePathOverride = resolve(value);
      continue;
    }
    if (argument.startsWith('-')) throw new Error(`unknown option: ${argument}`);
    positionals.push(argument);
  }

  [parsed.command] = positionals;
  if (positionals.length > 1) {
    throw new Error(`unexpected positional arguments: ${positionals.slice(1).join(', ')}`);
  }
  return parsed;
}

async function runValidation(context) {
  const parseYaml = globalThis.Bun?.YAML?.parse;
  if (typeof parseYaml !== 'function') {
    writeCodexsyncLine(
      context.stderr,
      'error agentbox plugin validation requires Bun with YAML support',
    );
    return false;
  }

  const result = await validatePlugin({ parseYaml, repoRoot: context.repoRoot });
  for (const check of result.checks) writeCodexsyncLine(context.stdout, `check ${check}`);
  if (!result.ok) {
    writeCodexsyncLine(context.stderr);
    writeCodexsyncLine(context.stderr, 'agentbox plugin validation failed:');
    for (const failure of result.failures) writeCodexsyncLine(context.stderr, `- ${failure}`);
    return false;
  }
  writeCodexsyncLine(context.stdout, 'done agentbox plugin validation passed');
  return true;
}

async function main() {
  let parsed;
  try {
    parsed = parseArguments(process.argv.slice(2));
  } catch (error) {
    writeCodexsyncLine(process.stderr, `error ${error.message}`);
    return false;
  }

  if (parsed.command === 'validate' && !parsed.help && !parsed.version) {
    return runValidation({
      repoRoot: parsed.repoRoot,
      stderr: process.stderr,
      stdout: process.stdout,
    });
  }

  const context = await resolveCodexsyncContext(parsed);
  if (parsed.help) {
    process.stdout.write(usage(context));
    return true;
  }
  if (parsed.version) {
    writeCodexsyncLine(process.stdout, context.packageJson.version);
    return true;
  }
  if (!parsed.command) {
    writeCodexsyncLine(
      process.stderr,
      `error expected a command (${CODEXSYNC_COMMANDS.join(', ')})`,
    );
    writeCodexsyncLine(process.stderr);
    process.stderr.write(usage(context));
    return false;
  }
  if (!CODEXSYNC_COMMANDS.includes(parsed.command)) {
    writeCodexsyncLine(process.stderr, `error unknown command: ${parsed.command}`);
    return false;
  }

  if (parsed.command === 'check') return (await runCodexsyncCheck(context)).ok;
  if (parsed.command === 'sync') return (await runCodexsyncSync(context)).ok;
  return runValidation(context);
}

try {
  if (!(await main())) process.exitCode = 1;
} catch (error) {
  writeCodexsyncLine(process.stderr, `error codexsync failed unexpectedly: ${error.message}`);
  process.exitCode = 1;
}
