#!/usr/bin/env node

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const [directory, expectedTag] = process.argv.slice(2);
if (!directory || !expectedTag) {
  throw new Error('Usage: node scripts/check-package.js <extracted-package> <release-tag>');
}

const root = resolve(directory);
const readJson = (path) => JSON.parse(readFileSync(join(root, path), 'utf8'));
const pkg = readJson('package.json');
const plugin = readJson('.codex-plugin/plugin.json');

assert.equal(pkg.name, '@tanaab/agentbox');
assert.notEqual(pkg.private, true, 'The npm package must be publishable');
assert.equal(`v${pkg.version}`, expectedTag, 'The package version must match the release tag');
assert.equal(plugin.name, 'agentbox');
assert.equal(plugin.version, pkg.version, 'The plugin and package versions must agree');
assert.equal(existsSync(join(root, 'node_modules')), false, 'Do not ship node_modules');

for (const path of [
  'assets/composer-icon.svg',
  'assets/icon-large.png',
  'skills/agentbox/SKILL.md',
  'skills/agentbox-installer/SKILL.md',
  'skills/agentbox-doctor/SKILL.md',
  'lib/agentbox-installations.js',
  'scripts/check-plugin-runtime.sh',
  'skills/agentbox-installer/scripts/manage-installations.js',
  'skills/agentbox-doctor/scripts/check-host.js',
]) {
  assert.equal(statSync(join(root, path)).isFile(), true, `Missing package file: ${path}`);
}

for (const path of [
  'scripts/check-plugin-runtime.sh',
  'skills/agentbox-installer/scripts/manage-installations.js',
  'skills/agentbox-doctor/scripts/check-host.js',
]) {
  assert.notEqual(statSync(join(root, path)).mode & 0o111, 0, `Not executable: ${path}`);
}

for (const [command, args] of [
  [join(root, 'scripts/check-plugin-runtime.sh'), []],
  ['bun', [join(root, 'skills/agentbox-installer/scripts/manage-installations.js'), '--help']],
  ['bun', [join(root, 'skills/agentbox-doctor/scripts/check-host.js'), '--help']],
]) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 30_000 });
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
}

process.stdout.write(`Verified extracted ${pkg.name}@${pkg.version} without install scripts.\n`);
