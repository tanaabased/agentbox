import assert from 'node:assert/strict';
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  rm,
  stat,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { runCodexsyncCheck } from '../lib/codexsync-check.js';
import { resolveCodexsyncContext } from '../lib/codexsync-context.js';
import { runCodexsyncSync } from '../lib/codexsync-sync.js';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const codexsyncPath = join(repoRoot, 'bin', 'codexsync.js');
const packageJson = JSON.parse(await readFile(join(repoRoot, 'package.json'), 'utf8'));
const packageVersion = packageJson.version;

function captureStream() {
  return {
    output: '',
    write(chunk) {
      this.output += String(chunk);
    },
  };
}

async function createContext(root, options = {}) {
  const sourceRoot = join(root, 'source');
  const cachePath = join(root, 'cache', '1.0.0');
  await mkdir(sourceRoot, { recursive: true });
  await writeFile(join(sourceRoot, 'managed.txt'), 'source\n');
  const stdout = captureStream();
  const stderr = captureStream();

  return {
    cachePath,
    managedPaths: ['managed.txt'],
    packageJson: { version: '1.0.0' },
    pluginCacheRoot: dirname(cachePath),
    pluginJson: { name: 'agentbox' },
    repoRoot: sourceRoot,
    stderr,
    stdout,
    ...options,
  };
}

async function markCacheInstalled(context) {
  const manifestDir = join(context.cachePath, '.codex-plugin');
  await mkdir(manifestDir, { recursive: true });
  await writeFile(
    join(manifestDir, 'plugin.json'),
    `${JSON.stringify({ name: context.pluginJson.name, version: context.packageJson.version })}\n`,
  );
}

describe('codexsync cache management', function () {
  this.timeout(10_000);
  const roots = [];

  afterEach(async () => {
    await Promise.all(roots.splice(0).map((root) => rm(root, { force: true, recursive: true })));
  });

  async function createRoot() {
    const root = await mkdtemp(join(tmpdir(), 'agentbox-codexsync-'));
    roots.push(root);
    return root;
  }

  it('should resolve the versioned pirostore cache path from plugin metadata', async () => {
    const context = await resolveCodexsyncContext({ homeDir: '/tmp/example-home', repoRoot });
    const overridden = await resolveCodexsyncContext({
      cachePathOverride: '/tmp/custom-cache/agentbox',
      repoRoot,
    });

    assert.equal(
      context.cachePath,
      `/tmp/example-home/.codex/plugins/cache/pirostore/agentbox/${packageVersion}`,
    );
    assert.ok(context.managedPaths.includes('CODEX.md'));
    assert.equal(overridden.pluginCacheRoot, '/tmp/custom-cache');
  });

  it('should treat a missing exact-version cache as not installed', async () => {
    const root = await createRoot();
    const context = await createContext(root);
    await mkdir(join(context.pluginCacheRoot, '0.9.0'), { recursive: true });

    const result = await runCodexsyncCheck(context);

    assert.equal(result.ok, true);
    assert.equal(result.status, 'not_installed');
    assert.deepEqual(result.inspection.installedVersions, ['0.9.0']);
    assert.match(context.stdout.output, /not installed for version 1\.0\.0/);
    assert.match(context.stdout.output, /other cache versions found: 0\.9\.0/);
    await assert.rejects(lstat(context.cachePath), { code: 'ENOENT' });
  });

  it('should refuse to create a missing plugin cache during sync', async () => {
    const root = await createRoot();
    const context = await createContext(root);

    const result = await runCodexsyncSync(context);

    assert.equal(result.ok, false);
    assert.equal(result.status, 'not_installed');
    assert.match(context.stderr.output, /refusing to create a plugin cache/);
    await assert.rejects(lstat(context.cachePath), { code: 'ENOENT' });
  });

  it('should refuse an empty exact-version directory as a first-sync target', async () => {
    const root = await createRoot();
    const context = await createContext(root);
    await mkdir(context.cachePath, { recursive: true });

    const check = await runCodexsyncCheck(context);
    const sync = await runCodexsyncSync(context);

    assert.equal(check.status, 'not_installed');
    assert.equal(sync.status, 'not_installed');
    assert.match(context.stdout.output, /cached plugin manifest is missing/);
    await assert.rejects(lstat(join(context.cachePath, 'managed.txt')), { code: 'ENOENT' });
  });

  it('should synchronize only managed paths in an existing cache', async () => {
    const root = await createRoot();
    const context = await createContext(root);
    await markCacheInstalled(context);
    await writeFile(join(context.cachePath, 'managed.txt'), 'stale\n');
    await writeFile(join(context.cachePath, 'unmanaged.txt'), 'preserve\n');

    const before = await runCodexsyncCheck(context);
    const synced = await runCodexsyncSync(context);
    const after = await runCodexsyncCheck(context);

    assert.equal(before.status, 'drifted');
    assert.equal(synced.status, 'current');
    assert.equal(after.status, 'current');
    assert.equal(await readFile(join(context.cachePath, 'managed.txt'), 'utf8'), 'source\n');
    assert.equal(await readFile(join(context.cachePath, 'unmanaged.txt'), 'utf8'), 'preserve\n');
  });

  it('should preserve file modes and symlink targets', async () => {
    const root = await createRoot();
    const context = await createContext(root, { managedPaths: ['managed.txt', 'managed-link'] });
    const sourcePath = join(context.repoRoot, 'managed.txt');
    await chmod(sourcePath, 0o755);
    await symlink('managed.txt', join(context.repoRoot, 'managed-link'));
    await markCacheInstalled(context);

    const result = await runCodexsyncSync(context);

    assert.equal(result.ok, true);
    assert.equal((await stat(join(context.cachePath, 'managed.txt'))).mode & 0o777, 0o755);
    assert.equal(await readlink(join(context.cachePath, 'managed-link')), 'managed.txt');
  });

  it('should expose help and version through the package CLI', () => {
    const help = spawnSync('bun', [codexsyncPath, '--help'], { encoding: 'utf8' });
    const version = spawnSync('bun', [codexsyncPath, '--version'], { encoding: 'utf8' });

    assert.equal(help.status, 0, help.stderr);
    assert.match(help.stdout, /sync never creates a missing plugin cache/);
    assert.equal(version.status, 0, version.stderr);
    assert.equal(version.stdout.trim(), packageVersion);
  });

  it('should keep CLI check neutral and CLI sync failing when the cache is absent', async () => {
    const root = await createRoot();
    const cachePath = join(root, 'missing-cache');
    const sharedArgs = ['--repo-root', repoRoot, '--cache-path', cachePath];
    const check = spawnSync('bun', [codexsyncPath, 'check', ...sharedArgs], { encoding: 'utf8' });
    const sync = spawnSync('bun', [codexsyncPath, 'sync', ...sharedArgs], { encoding: 'utf8' });

    assert.equal(check.status, 0, check.stderr);
    assert.match(check.stdout, /not installed/);
    assert.equal(sync.status, 1);
    assert.match(sync.stderr, /install agentbox through Codex first/);
    await assert.rejects(lstat(cachePath), { code: 'ENOENT' });
  });
});
