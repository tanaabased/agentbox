import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, readFile, realpath, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  createAgentboxInstallationConfig,
  inspectConfiguredAgentboxInstallation,
  isDirectoryOnPath,
  loadAgentboxInstallationConfig,
  resolveAgentboxInstallationPaths,
  resolveConfiguredAgentboxInstallation,
  validateAgentboxInstallationConfig,
  validateAgentboxPayload,
  withAgentboxInstallation,
  withDefaultAgentboxInstallation,
  writeAgentboxInstallationConfig,
} from '../lib/agentbox-installations.js';

async function createPayload(root, version = 'v1.2.1') {
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
  const scriptPath = join(root, 'macos.sh');
  await writeFile(
    scriptPath,
    `#!/bin/sh\nif [ "\${1:-}" = "--version" ]; then printf '%s\\n' '${version}'; exit 0; fi\nexit 2\n`,
  );
  await chmod(scriptPath, 0o755);
  return scriptPath;
}

describe('lib/agentbox-installations', () => {
  let env;
  let home;

  beforeEach(async () => {
    home = await mkdtemp(join(tmpdir(), 'agentbox-installations-'));
    env = { HOME: home, PATH: `/usr/bin:${join(home, '.local', 'bin')}` };
  });

  afterEach(async () => {
    await rm(home, { recursive: true, force: true });
  });

  it('should resolve standard and XDG paths deterministically', () => {
    const standard = resolveAgentboxInstallationPaths({ env });
    const xdg = resolveAgentboxInstallationPaths({
      env: {
        ...env,
        XDG_CONFIG_HOME: join(home, 'config'),
        XDG_DATA_HOME: join(home, 'data'),
        XDG_CACHE_HOME: join(home, 'cache'),
      },
    });

    assert.equal(standard.configFile, join(home, '.config', 'agentbox', 'config.json'));
    assert.equal(standard.shimPath, join(home, '.local', 'bin', 'agentbox'));
    assert.equal(xdg.configFile, join(home, 'config', 'agentbox', 'config.json'));
    assert.equal(xdg.dataDir, join(home, 'data', 'agentbox'));
    assert.equal(xdg.cacheDir, join(home, 'cache', 'agentbox'));
  });

  it('should return an empty config without writing when no config exists', async () => {
    const loaded = await loadAgentboxInstallationConfig({ env });

    assert.equal(loaded.exists, false);
    assert.deepEqual(loaded.config.installations, {});
    assert.equal(loaded.config.default, null);
    await assert.rejects(readFile(loaded.paths.configFile), { code: 'ENOENT' });
  });

  it('should atomically write and reload a private config', async () => {
    const paths = resolveAgentboxInstallationPaths({ env });
    const payloadPath = await createPayload(join(home, 'source'));
    const config = withAgentboxInstallation(createAgentboxInstallationConfig(paths), 'source', {
      kind: 'source',
      version: 'v1.2.1',
      path: payloadPath,
    });

    await writeAgentboxInstallationConfig(config, { env });
    const loaded = await loadAgentboxInstallationConfig({ env });
    const configMode = (await stat(paths.configFile)).mode & 0o777;
    const directoryMode = (await stat(paths.configDir)).mode & 0o777;

    assert.equal(loaded.exists, true);
    assert.deepEqual(loaded.config, config);
    assert.equal(configMode, 0o600);
    assert.equal(directoryMode, 0o700);
  });

  it('should reject defaults that are not registered', () => {
    const paths = resolveAgentboxInstallationPaths({ env });
    const config = { ...createAgentboxInstallationConfig(paths), default: 'stable' };

    assert.throws(() => validateAgentboxInstallationConfig(config), {
      code: 'config_invalid',
    });
  });

  it('should reject an installations array', () => {
    const paths = resolveAgentboxInstallationPaths({ env });
    const config = { ...createAgentboxInstallationConfig(paths), installations: [] };

    assert.throws(() => validateAgentboxInstallationConfig(config), {
      code: 'config_invalid',
    });
  });

  it('should validate and resolve a complete configured payload', async () => {
    const paths = resolveAgentboxInstallationPaths({ env });
    const payloadPath = await createPayload(join(home, 'source'));
    const payload = await validateAgentboxPayload(join(home, 'source'), { env });
    let config = withAgentboxInstallation(createAgentboxInstallationConfig(paths), 'source', {
      kind: 'source',
      version: payload.version,
      path: payload.path,
    });
    config = withDefaultAgentboxInstallation(config, 'source');
    await writeAgentboxInstallationConfig(config, { env });

    const resolved = await resolveConfiguredAgentboxInstallation({ env });

    assert.equal(payload.path, await realpath(payloadPath));
    assert.equal(resolved.installation.key, 'source');
    assert.equal(resolved.installation.version, 'v1.2.1');
  });

  it('should validate a stamped dist script against its parent payload', async () => {
    const payloadRoot = join(home, 'release');
    const rootScript = await createPayload(payloadRoot);
    const distDir = join(payloadRoot, 'dist');
    const distScript = join(distDir, 'macos.sh');
    await mkdir(distDir, { recursive: true });
    await writeFile(distScript, await readFile(rootScript));
    await chmod(distScript, 0o755);

    const payload = await validateAgentboxPayload(distScript, { env });

    assert.equal(payload.path, await realpath(distScript));
    assert.equal(payload.root, await realpath(payloadRoot));
  });

  it('should require payload entries to be regular files', async () => {
    const payloadRoot = join(home, 'source');
    await createPayload(payloadRoot);
    await rm(join(payloadRoot, 'Brewfile'));
    await mkdir(join(payloadRoot, 'Brewfile'));

    await assert.rejects(validateAgentboxPayload(payloadRoot, { env }), {
      code: 'payload_invalid',
    });
  });

  it('should require valid bundled PNG assets', async () => {
    const payloadRoot = join(home, 'source');
    await createPayload(payloadRoot);
    await writeFile(join(payloadRoot, 'assets', 'profile1.png'), 'not a png\n');

    await assert.rejects(validateAgentboxPayload(payloadRoot, { env }), {
      code: 'payload_invalid',
    });
  });

  it('should reject observed stable versions that differ from config', async () => {
    const paths = resolveAgentboxInstallationPaths({ env });
    const payloadPath = await createPayload(join(home, 'stable'), 'v1.2.2');
    const config = withAgentboxInstallation(createAgentboxInstallationConfig(paths), 'stable', {
      kind: 'release',
      version: 'v1.2.1',
      releaseTag: 'v1.2.1',
      path: payloadPath,
    });
    await writeAgentboxInstallationConfig(config, { env });

    await assert.rejects(resolveConfiguredAgentboxInstallation({ env }), {
      code: 'installation_version_mismatch',
    });
  });

  it('should report a stale configured payload without throwing', async () => {
    const paths = resolveAgentboxInstallationPaths({ env });
    const config = withAgentboxInstallation(createAgentboxInstallationConfig(paths), 'source', {
      kind: 'source',
      version: 'v1.2.1',
      path: join(home, 'missing', 'macos.sh'),
    });
    await writeAgentboxInstallationConfig(config, { env });

    const inspected = await inspectConfiguredAgentboxInstallation({ env });

    assert.equal(inspected.status, 'unavailable');
    assert.equal(inspected.error.code, 'payload_missing');
  });

  it('should identify whether the configured bin directory is on PATH', () => {
    const binDir = join(home, '.local', 'bin');

    assert.equal(isDirectoryOnPath(binDir, env.PATH), true);
    assert.equal(isDirectoryOnPath(binDir, '/usr/bin:/bin'), false);
  });
});
