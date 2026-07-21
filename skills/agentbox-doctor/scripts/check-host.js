#!/usr/bin/env bun

import {
  closeSync,
  constants,
  existsSync,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
} from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { inspectConfiguredAgentboxInstallation } from '../../../lib/agentbox-installations.js';

import {
  evaluateHealth,
  unavailableReport,
  validatePublishedHealthReport,
  validatePublishedHealthReportMetadata,
} from './check-host-lib.js';

const skillRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const pluginRoot = resolve(skillRoot, '..', '..');
const defaultHealthScript = '/opt/tanaab/agentbox/bin/health.sh';
const defaultHealthReport = '/var/db/tanaab/agentbox/health-report';

function usage() {
  return `Usage: check-host.js [--help]\n`;
}

function parseArgs(argv) {
  if (argv.length === 0) return { help: false };
  if (argv.length === 1 && argv[0] === '--help') {
    return { help: true };
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

function snapshotMetadata(stats, isSymbolicLink = false) {
  return {
    gid: stats.gid,
    isFile: stats.isFile(),
    isSymbolicLink,
    mode: stats.mode,
    size: stats.size,
    uid: stats.uid,
  };
}

function readPublishedHealthReport() {
  let pathStats;
  try {
    pathStats = lstatSync(defaultHealthReport);
  } catch (error) {
    return {
      ok: false,
      status: 'report_unavailable',
      detail:
        error.code === 'ENOENT'
          ? 'The agentbox-published health report was not found.'
          : `The agentbox-published health report could not be inspected: ${error.message}`,
      waitForPublication: error.code === 'ENOENT',
    };
  }

  const pathMetadata = snapshotMetadata(pathStats, pathStats.isSymbolicLink());
  const pathValidation = validatePublishedHealthReportMetadata(pathMetadata);
  if (!pathValidation.ok) return pathValidation;

  let descriptor;
  try {
    descriptor = openSync(defaultHealthReport, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
    const descriptorMetadata = snapshotMetadata(fstatSync(descriptor));
    const descriptorValidation = validatePublishedHealthReportMetadata(descriptorMetadata);
    if (!descriptorValidation.ok) return descriptorValidation;

    return validatePublishedHealthReport(readFileSync(descriptor, 'utf8'), descriptorMetadata);
  } catch (error) {
    return {
      ok: false,
      status: 'report_unavailable',
      detail: `The agentbox-published health report could not be read safely: ${error.message}`,
    };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
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
if (!existsSync(defaultHealthScript)) {
  printJson(
    unavailableReport('not_installed', 'The installed agentbox health script was not found.', {
      healthReport: defaultHealthReport,
      healthScript: defaultHealthScript,
      pluginVersion,
    }),
  );
  process.exit(2);
}

const snapshot = readPublishedHealthReport();
const installer =
  snapshot.ok || snapshot.status === 'report_stale'
    ? await inspectConfiguredAgentboxInstallation()
    : null;
if (!snapshot.ok) {
  printJson(
    unavailableReport(snapshot.status, snapshot.detail, {
      healthAgeSeconds: snapshot.healthAgeSeconds,
      healthReport: defaultHealthReport,
      healthScript: defaultHealthScript,
      healthTimestamp: snapshot.healthTimestamp,
      installedVersion: snapshot.installedVersion,
      installer,
      pluginVersion,
      remediationSummary: snapshot.waitForPublication
        ? 'Wait through one five-minute health interval after boot or installation. If the report is still unavailable, rerun agentbox to reconcile the health LaunchDaemon.'
        : undefined,
    }),
  );
  process.exit(2);
}

const report = evaluateHealth(snapshot.values, {
  healthAgeSeconds: snapshot.healthAgeSeconds,
  healthReport: defaultHealthReport,
  healthScript: defaultHealthScript,
  installer,
  pluginVersion,
});
printJson(report);
process.exit(report.status === 'unhealthy' ? 1 : 0);
