import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  access,
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  realpath,
  rm,
  stat,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { loadAgentboxInstallationConfig } from '../lib/agentbox-installations.js';
import {
  installStableAgentbox,
  repairInvalidAgentboxInstallationConfig,
  registerSourceAgentbox,
  resolveLatestStableRelease,
  statusAgentboxInstallations,
  useAgentboxInstallation,
  validateArchiveEntryNames,
} from '../skills/agentbox-installer/scripts/manage-installations-lib.js';

const managerPath = new URL(
  '../skills/agentbox-installer/scripts/manage-installations.js',
  import.meta.url,
).pathname;

async function createPayload(root, version, scriptRelativePath = 'macos.sh') {
  const files = [
    'Brewfile',
    'bin/health.sh',
    'launchd/dev.tanaab.agentbox.health.plist.in',
    'launchd/dev.tanaab.agentbox.tailscaled.plist.in',
    'launchd/dev.tanaab.agentbox.openclaw-gateway.plist.in',
    'assets/default_avatar.png',
    'assets/profile1.png',
  ];
  for (const file of files) {
    const path = join(root, file);
    await mkdir(join(path, '..'), { recursive: true });
    await writeFile(
      path,
      file.endsWith('.png')
        ? Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        : 'fixture\n',
    );
  }
  const scriptPath = join(root, scriptRelativePath);
  await mkdir(join(scriptPath, '..'), { recursive: true });
  await writeFile(
    scriptPath,
    `#!/bin/sh\nif [ "\${1:-}" = "--version" ]; then printf '%s\\n' '${version}'; exit 0; fi\nexit 2\n`,
  );
  await chmod(scriptPath, 0o755);
  return scriptPath;
}

function fakeResponse(body, type) {
  return {
    ok: true,
    status: 200,
    async json() {
      return type === 'json' ? body : JSON.parse(String(body));
    },
    async text() {
      return Buffer.isBuffer(body) ? body.toString('utf8') : String(body);
    },
    async arrayBuffer() {
      const buffer = Buffer.isBuffer(body) ? body : Buffer.from(String(body));
      return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
    },
  };
}

async function createReleaseFetch(home, tag = 'v1.2.1', digestOverride = null, mutate = null) {
  const releaseRoot = join(home, 'release-fixture');
  await createPayload(releaseRoot, tag, 'dist/macos.sh');
  if (mutate) await mutate(releaseRoot);
  const archiveName = `agentbox-${tag}.tar.gz`;
  const archivePath = join(home, archiveName);
  const tarResult = spawnSync('tar', ['-czf', archivePath, '-C', releaseRoot, '.'], {
    encoding: 'utf8',
  });
  if (tarResult.status !== 0) throw new Error(tarResult.stderr);
  const archive = await readFile(archivePath);
  const digest = digestOverride || createHash('sha256').update(archive).digest('hex');
  const archiveUrl = `https://downloads.example/${archiveName}`;
  const metadata = {
    tag_name: tag,
    draft: false,
    prerelease: false,
    assets: [
      {
        name: archiveName,
        browser_download_url: archiveUrl,
        digest: `sha256:${digest}`,
      },
    ],
  };

  return async (url) => {
    if (url.endsWith('/releases/latest')) return fakeResponse(metadata, 'json');
    if (url === archiveUrl) return fakeResponse(archive, 'buffer');
    return { ok: false, status: 404 };
  };
}

describe('skills/agentbox-installer/scripts/manage-installations-lib', function () {
  this.timeout(10_000);

  let env;
  let home;

  beforeEach(async () => {
    home = await mkdtemp(join(tmpdir(), 'agentbox-installer-'));
    env = { HOME: home, PATH: `/usr/bin:${join(home, '.local', 'bin')}` };
  });

  afterEach(async () => {
    await rm(home, { recursive: true, force: true });
  });

  it('should expose only the opt-in command-link flag', () => {
    const result = spawnSync('bun', [managerPath, '--help'], { encoding: 'utf8' });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /--link-command/);
    assert.doesNotMatch(result.stdout, /--no-link-command/);
  });

  it('should require command linking for a custom bin directory', () => {
    const result = spawnSync(
      'bun',
      [managerPath, 'use', 'source', '--bin-dir', join(home, 'bin')],
      { encoding: 'utf8', env: { ...process.env, HOME: home } },
    );

    assert.equal(result.status, 2);
    assert.match(result.stderr, /--bin-dir requires --link-command/);
  });

  it('should require the archive asset for stable releases', async () => {
    const fetchImpl = async () =>
      fakeResponse(
        {
          tag_name: 'v1.2.1',
          draft: false,
          prerelease: false,
          assets: [],
        },
        'json',
      );

    await assert.rejects(resolveLatestStableRelease({ fetchImpl }), {
      code: 'release_assets_missing',
    });
  });

  it('should require a GitHub SHA-256 digest for the archive asset', async () => {
    const fetchImpl = async () =>
      fakeResponse(
        {
          tag_name: 'v1.2.1',
          draft: false,
          prerelease: false,
          assets: [
            {
              name: 'agentbox-v1.2.1.tar.gz',
              browser_download_url: 'https://downloads.example/agentbox-v1.2.1.tar.gz',
              digest: null,
            },
          ],
        },
        'json',
      );

    await assert.rejects(resolveLatestStableRelease({ fetchImpl }), {
      code: 'release_digest_missing',
    });
  });

  it('should reject archive traversal paths', () => {
    assert.throws(() => validateArchiveEntryNames(['./dist/macos.sh', '../escape']), {
      code: 'archive_unsafe',
    });
  });

  it('should time out stalled release requests', async () => {
    const fetchImpl = async (_url, request) =>
      new Promise((_resolve, reject) => {
        request.signal.addEventListener('abort', () => reject(new Error('aborted')));
      });

    await assert.rejects(resolveLatestStableRelease({ fetchImpl, fetchTimeoutMs: 5 }), {
      code: 'download_timeout',
    });
  });

  it('should reject links extracted from a release archive', async () => {
    const fetchImpl = await createReleaseFetch(home, 'v1.2.1', null, async (releaseRoot) => {
      await symlink('/tmp', join(releaseRoot, 'unsafe-link'));
    });

    await assert.rejects(installStableAgentbox({ env, fetchImpl }), {
      code: 'archive_unsafe',
    });
  });

  it('should install stable atomically without linking a command by default', async () => {
    const fetchImpl = await createReleaseFetch(home);
    const first = await installStableAgentbox({
      env,
      fetchImpl,
      now: new Date('2026-07-16T12:00:00Z'),
    });
    const configBefore = await readFile(first.configPath, 'utf8');
    const configStatBefore = await stat(first.configPath);
    const second = await installStableAgentbox({
      env,
      fetchImpl,
      now: new Date('2026-07-16T12:01:00Z'),
    });
    const loaded = await loadAgentboxInstallationConfig({ env });
    const status = await statusAgentboxInstallations({ env });

    assert.equal(first.status, 'installed');
    assert.equal(first.changed, true);
    assert.equal(first.payloadChanged, true);
    assert.equal(first.configChanged, true);
    assert.equal(first.shimChanged, false);
    assert.equal(first.linkCommand, false);
    assert.equal(second.status, 'current');
    assert.equal(second.changed, false);
    assert.equal(second.payloadChanged, false);
    assert.equal(second.configChanged, false);
    assert.equal(second.shimChanged, false);
    assert.equal(await readFile(second.configPath, 'utf8'), configBefore);
    assert.equal((await stat(second.configPath)).ino, configStatBefore.ino);
    await assert.rejects(lstat(second.binPath), { code: 'ENOENT' });
    assert.equal(loaded.config.default, 'stable');
    assert.equal(loaded.config.installations.stable.path, await realpath(first.path));
    assert.equal(loaded.config.installations.stable.updatedAt, '2026-07-16T12:00:00.000Z');
    assert.equal(loaded.config.linkCommand, false);
    assert.equal(status.shim.status, 'disabled');
    assert.equal(status.path.configured, false);
    assert.equal(status.path.directoryOnPath, true);
    assert.deepEqual(status.commandsOnPath, []);
    assert.deepEqual(first.handoff, {
      skill: '$tanaab-agentbox',
      installationKey: 'stable',
      defaultKey: 'stable',
    });
  });

  it('should reconcile a missing stable command without rewriting config', async () => {
    const fetchImpl = await createReleaseFetch(home);
    const installed = await installStableAgentbox({
      env,
      fetchImpl,
      linkCommand: true,
      now: new Date('2026-07-16T12:00:00Z'),
    });
    const configBefore = await readFile(installed.configPath, 'utf8');
    await rm(installed.binPath);

    const reconciled = await installStableAgentbox({
      env,
      fetchImpl,
      now: new Date('2026-07-16T12:01:00Z'),
    });

    assert.equal(reconciled.status, 'reconciled');
    assert.equal(reconciled.changed, true);
    assert.equal(reconciled.payloadChanged, false);
    assert.equal(reconciled.configChanged, false);
    assert.equal(reconciled.shimChanged, true);
    assert.equal(await readFile(reconciled.configPath, 'utf8'), configBefore);
    assert.equal(await readlink(reconciled.binPath), installed.path);
  });

  it('should report reconciliation when an existing stable payload is newly registered', async () => {
    const fetchImpl = await createReleaseFetch(home);
    const installed = await installStableAgentbox({ env, fetchImpl, linkCommand: true });
    await rm(installed.configPath);
    await rm(installed.binPath);

    const reconciled = await installStableAgentbox({
      env,
      fetchImpl,
      linkCommand: true,
      now: new Date('2026-07-16T12:01:00Z'),
    });

    assert.equal(reconciled.status, 'reconciled');
    assert.equal(reconciled.changed, true);
    assert.equal(reconciled.payloadChanged, false);
    assert.equal(reconciled.configChanged, true);
    assert.equal(reconciled.shimChanged, true);
    assert.equal(await readlink(reconciled.binPath), installed.path);
  });

  it('should preserve a requested non-default selector in the handoff', async () => {
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    await registerSourceAgentbox(sourcePath, { env });
    const fetchImpl = await createReleaseFetch(home);

    const installed = await installStableAgentbox({ env, fetchImpl });

    assert.equal(installed.default, 'source');
    assert.deepEqual(installed.handoff, {
      skill: '$tanaab-agentbox',
      installationKey: 'stable',
      defaultKey: 'source',
    });
  });

  it('should register source and switch the default without copying it', async () => {
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    const registered = await registerSourceAgentbox(sourcePath, { env });
    const loaded = await loadAgentboxInstallationConfig({ env });
    await assert.rejects(lstat(registered.binPath), { code: 'ENOENT' });
    await writeFile(
      sourcePath,
      '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then printf "%s\\n" "v1.4.0-dev"; exit 0; fi\nexit 2\n',
    );
    const selected = await useAgentboxInstallation('source', { env, linkCommand: true });
    const status = await statusAgentboxInstallations({ env });

    assert.equal(registered.default, 'source');
    assert.equal(registered.linkCommand, false);
    assert.equal(loaded.config.installations.source.path, await realpath(sourcePath));
    assert.equal(selected.key, 'source');
    assert.equal(selected.configuredVersion, 'v1.3.0-dev');
    assert.equal(selected.version, 'v1.4.0-dev');
    assert.equal(selected.linkCommand, true);
    assert.equal(await readlink(selected.binPath), await realpath(sourcePath));
    assert.equal(status.commandsOnPath.length, 1);
    assert.equal(status.commandsOnPath[0].relation, 'managed-current');
    assert.equal(status.commandsOnPath[0].effective, true);
    assert.deepEqual(selected.handoff, {
      skill: '$tanaab-agentbox',
      installationKey: 'source',
      defaultKey: 'source',
    });
  });

  it('should remove the old managed shim when changing bin directories', async () => {
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    const firstBin = join(home, 'bin-one');
    const secondBin = join(home, 'bin-two');
    const registered = await registerSourceAgentbox(sourcePath, {
      env,
      binDir: firstBin,
      linkCommand: true,
    });

    const selected = await useAgentboxInstallation('source', {
      env,
      binDir: secondBin,
      linkCommand: true,
    });

    await assert.rejects(access(registered.binPath), { code: 'ENOENT' });
    assert.equal(await readlink(selected.binPath), await realpath(sourcePath));
  });

  it('should report and repair invalid config without discarding the original', async () => {
    const configDir = join(home, '.config', 'agentbox');
    const configPath = join(configDir, 'config.json');
    await mkdir(configDir, { recursive: true });
    await writeFile(configPath, '{invalid json\n');

    const status = await statusAgentboxInstallations({ env });
    const repaired = await repairInvalidAgentboxInstallationConfig({
      env,
      now: new Date('2026-07-16T12:00:00Z'),
    });
    const loaded = await loadAgentboxInstallationConfig({ env });

    assert.equal(status.status, 'invalid_config');
    assert.equal(repaired.status, 'reset');
    assert.equal(await readFile(repaired.backupPath, 'utf8'), '{invalid json\n');
    assert.equal((await stat(repaired.backupPath)).mode & 0o777, 0o600);
    assert.equal(loaded.config.default, null);
    await assert.rejects(repairInvalidAgentboxInstallationConfig({ env }), {
      code: 'config_valid',
    });
  });

  it('should leave config untouched when digest verification fails', async () => {
    const fetchImpl = await createReleaseFetch(home, 'v1.2.1', '0'.repeat(64));

    await assert.rejects(installStableAgentbox({ env, fetchImpl }), {
      code: 'release_digest_mismatch',
    });
    const loaded = await loadAgentboxInstallationConfig({ env });
    assert.equal(loaded.exists, false);
  });

  it('should preserve and report an existing PATH command when linking is omitted', async () => {
    const binDir = join(home, '.local', 'bin');
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    await mkdir(binDir, { recursive: true });
    await writeFile(join(binDir, 'agentbox'), 'not managed\n');

    const registered = await registerSourceAgentbox(sourcePath, { env });
    const status = await statusAgentboxInstallations({ env });

    assert.equal(registered.linkCommand, false);
    assert.equal(await readFile(join(binDir, 'agentbox'), 'utf8'), 'not managed\n');
    assert.deepEqual(status.commandsOnPath, [
      {
        path: join(binDir, 'agentbox'),
        kind: 'file',
        target: null,
        resolvedTarget: null,
        relation: 'external',
        effective: true,
      },
    ]);
  });

  it('should refuse to replace an existing non-symlink command when linking is requested', async () => {
    const binDir = join(home, '.local', 'bin');
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    await mkdir(binDir, { recursive: true });
    await writeFile(join(binDir, 'agentbox'), 'not managed\n');

    await assert.rejects(registerSourceAgentbox(sourcePath, { env, linkCommand: true }), {
      code: 'shim_conflict',
    });
    const loaded = await loadAgentboxInstallationConfig({ env });
    assert.equal(loaded.exists, false);
  });

  it('should leave config untouched when the command shim cannot be staged', async () => {
    const binDir = join(home, '.local', 'bin');
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    await mkdir(binDir, { recursive: true });
    await chmod(binDir, 0o500);

    try {
      await assert.rejects(registerSourceAgentbox(sourcePath, { env, linkCommand: true }), {
        code: 'EACCES',
      });
    } finally {
      await chmod(binDir, 0o700);
    }
    const loaded = await loadAgentboxInstallationConfig({ env });
    assert.equal(loaded.exists, false);
  });
});
