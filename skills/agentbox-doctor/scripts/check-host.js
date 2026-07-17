#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { inspectConfiguredAgentboxInstallation } from '../../../lib/agentbox-installations.js';

import { evaluateHealth, parseHealthReport, unavailableReport } from './check-host-lib.js';

const skillRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const pluginRoot = resolve(skillRoot, '..', '..');
const defaultHealthScript = '/opt/tanaab/agentbox/bin/health.sh';
const healthTimeoutMs = 120_000;

function usage() {
  return `Usage: check-host.js [--help]\n`;
}

function parseArgs(argv) {
  if (argv.length === 0) return { healthScript: defaultHealthScript, help: false };
  if (argv.length === 1 && argv[0] === '--help') {
    return { healthScript: defaultHealthScript, help: true };
  }
  throw new Error(`unknown argument: ${argv[0]}`);
}

function readPluginVersion() {
  try {
    const manifest = JSON.parse(
      readFileSync(resolve(pluginRoot, '.codex-plugin', 'plugin.json'), 'utf8'),
    );
    return manifest.version || null;
  } catch {
    return null;
  }
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function runHealthScript(healthScript) {
  const root = typeof process.getuid === 'function' && process.getuid() === 0;
  const command = root ? healthScript : '/usr/bin/sudo';
  const args = root ? ['--report'] : ['-n', healthScript, '--report'];

  return spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
    timeout: healthTimeoutMs,
  });
}

let options;
try {
  options = parseArgs(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error.message}\n\n${usage()}`);
  process.exit(2);
}

if (options.help) {
  process.stdout.write(usage());
  process.exit(0);
}

const pluginVersion = readPluginVersion();
if (!existsSync(options.healthScript)) {
  printJson(
    unavailableReport('not_installed', 'The installed agentbox health script was not found.', {
      healthScript: options.healthScript,
      pluginVersion,
    }),
  );
  process.exit(2);
}

const result = runHealthScript(options.healthScript);
if (result.error) {
  const timedOut = result.error.code === 'ETIMEDOUT';
  printJson(
    unavailableReport(
      timedOut ? 'timeout' : 'unavailable',
      timedOut
        ? `The installed health script did not finish within ${healthTimeoutMs / 1000} seconds.`
        : `Could not execute the health script: ${result.error.message}`,
      {
        healthScript: options.healthScript,
        pluginVersion,
      },
    ),
  );
  process.exit(2);
}
if (result.status !== 0) {
  const authorizationRequired =
    /(password is required|no password was provided|a terminal is required)/i.test(
      result.stderr || '',
    );
  printJson(
    unavailableReport(
      authorizationRequired ? 'authorization_required' : 'unavailable',
      authorizationRequired
        ? 'Reusable sudo authorization is not available in this terminal.'
        : `The installed health script exited with status ${result.status}.`,
      {
        healthScript: options.healthScript,
        pluginVersion,
      },
    ),
  );
  process.exit(2);
}

const installer = await inspectConfiguredAgentboxInstallation();
const report = evaluateHealth(parseHealthReport(result.stdout), {
  healthScript: options.healthScript,
  installer,
  pluginVersion,
});
printJson(report);
process.exit(report.status === 'unhealthy' ? 1 : 0);
