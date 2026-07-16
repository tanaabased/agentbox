#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { evaluateHealth, parseHealthReport, unavailableReport } from './check-host-lib.js';

const skillRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const pluginRoot = resolve(skillRoot, '..', '..');
const defaultHealthScript = '/opt/tanaab/agentbox/bin/health.sh';

function usage() {
  return `Usage: check-host.js [--report-file PATH]\n\nOptions:\n  --report-file PATH  Evaluate a saved health report without sudo.\n  --help              Show this help.\n`;
}

function parseArgs(argv) {
  const options = {
    healthScript: defaultHealthScript,
    reportFile: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help') return { ...options, help: true };
    if (argument !== '--report-file') throw new Error(`unknown argument: ${argument}`);

    const value = argv[index + 1];
    if (!value) throw new Error(`${argument} requires a path`);
    options.reportFile = resolve(value);
    index += 1;
  }

  return options;
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
let rawReport;

if (options.reportFile) {
  try {
    rawReport = readFileSync(options.reportFile, 'utf8');
  } catch (error) {
    printJson(
      unavailableReport('unavailable', `Could not read report file: ${error.message}`, {
        pluginVersion,
      }),
    );
    process.exit(2);
  }
} else {
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
    printJson(
      unavailableReport(
        'unavailable',
        `Could not execute the health script: ${result.error.message}`,
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
  rawReport = result.stdout;
}

const report = evaluateHealth(parseHealthReport(rawReport), {
  healthScript: options.reportFile ? null : options.healthScript,
  pluginVersion,
});
printJson(report);
process.exit(report.status === 'unhealthy' ? 1 : 0);
