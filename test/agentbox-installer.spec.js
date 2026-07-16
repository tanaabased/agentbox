import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  realpath,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { loadAgentboxInstallationConfig } from '../lib/agentbox-installations.js';
import {
  installStableAgentbox,
  registerSourceAgentbox,
  resolveLatestStableRelease,
  statusAgentboxInstallations,
  useAgentboxInstallation,
  validateArchiveEntryNames,
} from '../skills/agentbox-installer/scripts/manage-installations-lib.js';

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
    await writeFile(path, 'fixture\n');
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

async function createReleaseFetch(home, tag = 'v1.2.1', digestOverride = null) {
  const releaseRoot = join(home, 'release-fixture');
  await createPayload(releaseRoot, tag, 'dist/macos.sh');
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

  it('should install stable atomically and keep repeated installs current', async () => {
    const fetchImpl = await createReleaseFetch(home);
    const first = await installStableAgentbox({
      env,
      fetchImpl,
      now: new Date('2026-07-16T12:00:00Z'),
    });
    const second = await installStableAgentbox({
      env,
      fetchImpl,
      now: new Date('2026-07-16T12:01:00Z'),
    });
    const loaded = await loadAgentboxInstallationConfig({ env });
    const status = await statusAgentboxInstallations({ env });

    assert.equal(first.status, 'installed');
    assert.equal(second.status, 'current');
    assert.equal(loaded.config.default, 'stable');
    assert.equal(loaded.config.installations.stable.path, await realpath(first.path));
    assert.equal(await readlink(loaded.config.binPath), first.path);
    assert.equal(status.shim.status, 'current');
    assert.equal(status.path.configured, true);
    assert.deepEqual(first.handoff, {
      skill: '$tanaab-agentbox',
      installationKey: 'stable',
    });
  });

  it('should register source and switch the default without copying it', async () => {
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    const registered = await registerSourceAgentbox(sourcePath, { env });
    const loaded = await loadAgentboxInstallationConfig({ env });
    const selected = await useAgentboxInstallation('source', { env });

    assert.equal(registered.default, 'source');
    assert.equal(loaded.config.installations.source.path, await realpath(sourcePath));
    assert.equal(selected.key, 'source');
    assert.equal(await readlink(selected.binPath), await realpath(sourcePath));
    assert.deepEqual(selected.handoff, {
      skill: '$tanaab-agentbox',
      installationKey: 'source',
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

  it('should refuse to replace an existing non-symlink command', async () => {
    const binDir = join(home, '.local', 'bin');
    const sourcePath = await createPayload(join(home, 'source'), 'v1.3.0-dev');
    await mkdir(binDir, { recursive: true });
    await writeFile(join(binDir, 'agentbox'), 'not managed\n');

    await assert.rejects(registerSourceAgentbox(sourcePath, { env }), {
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
      await assert.rejects(registerSourceAgentbox(sourcePath, { env }), { code: 'EACCES' });
    } finally {
      await chmod(binDir, 0o700);
    }
    const loaded = await loadAgentboxInstallationConfig({ env });
    assert.equal(loaded.exists, false);
  });
});
