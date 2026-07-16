import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import {
  lstat,
  mkdir,
  readFile,
  readdir,
  readlink,
  rename,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';

import {
  AgentboxInstallationError,
  inspectConfiguredAgentboxInstallation,
  isDirectoryOnPath,
  loadAgentboxInstallationConfig,
  resolveConfiguredAgentboxInstallation,
  selectAgentboxInstallation,
  validateAgentboxPayload,
  withAgentboxInstallation,
  withDefaultAgentboxInstallation,
  writeAgentboxInstallationConfig,
} from '../../../lib/agentbox-installations.js';

export const AGENTBOX_RELEASE_API_URL =
  'https://api.github.com/repos/tanaabased/agentbox/releases/latest';

function operationError(code, message) {
  return new AgentboxInstallationError(code, message);
}

function normalizeVersion(value) {
  return value.replace(/^v/, '');
}

function assertReleaseTag(tag) {
  if (!/^v?[0-9]+[.][0-9]+[.][0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(tag)) {
    throw operationError('release_invalid', `unsupported agentbox release tag: ${tag}.`);
  }
}

function resolveUserPath(value, env) {
  if (value === '~') return resolve(env.HOME);
  if (value.startsWith('~/')) return resolve(env.HOME, value.slice(2));
  return resolve(value);
}

async function fetchResponse(fetchImpl, url, responseType) {
  const response = await fetchImpl(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'agentbox-installer',
      'X-GitHub-Api-Version': '2026-03-10',
    },
  });
  if (!response.ok) {
    throw operationError(
      'download_failed',
      `request failed with status ${response.status}: ${url}.`,
    );
  }
  return response[responseType]();
}

export async function resolveLatestStableRelease(options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const metadata = await fetchResponse(
    fetchImpl,
    options.releaseApiUrl || AGENTBOX_RELEASE_API_URL,
    'json',
  );
  const tag = metadata.tag_name;
  if (!tag || metadata.draft || metadata.prerelease || !Array.isArray(metadata.assets)) {
    throw operationError('release_invalid', 'latest agentbox release metadata is not stable.');
  }
  assertReleaseTag(tag);

  const archiveName = `agentbox-${tag}.tar.gz`;
  const archive = metadata.assets.find((asset) => asset.name === archiveName);
  if (!archive?.browser_download_url) {
    throw operationError(
      'release_assets_missing',
      `agentbox release ${tag} must include ${archiveName}.`,
    );
  }
  const digestMatch = archive.digest?.match(/^sha256:([a-fA-F0-9]{64})$/);
  if (!digestMatch) {
    throw operationError(
      'release_digest_missing',
      `agentbox release asset ${archiveName} must include a GitHub SHA-256 digest.`,
    );
  }

  return {
    tag,
    archiveName,
    archiveUrl: archive.browser_download_url,
    archiveDigest: digestMatch[1].toLowerCase(),
  };
}

async function fileSha256(path) {
  return createHash('sha256')
    .update(await readFile(path))
    .digest('hex');
}

async function downloadArchive(release, cacheDir, options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const downloadsDir = join(cacheDir, 'downloads');
  const archivePath = join(downloadsDir, release.archiveName);

  await mkdir(downloadsDir, { recursive: true, mode: 0o700 });
  if (await lstat(archivePath).catch(() => null)) {
    if ((await fileSha256(archivePath)) === release.archiveDigest) return archivePath;
    await rm(archivePath, { force: true });
  }

  const archiveContent = Buffer.from(
    await fetchResponse(fetchImpl, release.archiveUrl, 'arrayBuffer'),
  );
  const tempPath = join(downloadsDir, `.${release.archiveName}.${randomUUID()}.tmp`);
  await writeFile(tempPath, archiveContent, { flag: 'wx', mode: 0o600 });
  if ((await fileSha256(tempPath)) !== release.archiveDigest) {
    await rm(tempPath, { force: true });
    throw operationError(
      'release_digest_mismatch',
      `downloaded agentbox release ${release.tag} failed SHA-256 verification.`,
    );
  }
  await rename(tempPath, archivePath);
  return archivePath;
}

export function validateArchiveEntryNames(entries) {
  for (const entry of entries) {
    const normalized = entry.replaceAll('\\', '/').replace(/^([.][/])+/, '');
    const segments = normalized.split('/').filter(Boolean);
    if (normalized.startsWith('/') || /^[A-Za-z]:\//.test(normalized) || segments.includes('..')) {
      throw operationError('archive_unsafe', `unsafe path in agentbox archive: ${entry}.`);
    }
  }
  return entries;
}

function runTar(args, detail) {
  const result = spawnSync('tar', args, { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw operationError('archive_invalid', `${detail}: ${result.stderr?.trim() || 'tar failed'}.`);
  }
  return result.stdout;
}

async function extractArchive(archivePath, stagingDir) {
  const entries = runTar(['-tzf', archivePath], 'could not list agentbox release archive')
    .split(/\r?\n/)
    .filter(Boolean);
  validateArchiveEntryNames(entries);
  await mkdir(stagingDir, { recursive: true, mode: 0o700 });
  runTar(['-xzf', archivePath, '-C', stagingDir], 'could not extract agentbox release archive');
}

async function findExtractedPayload(stagingDir, options = {}) {
  const candidates = [stagingDir];
  const entries = await readdir(stagingDir, { withFileTypes: true });
  const directories = entries.filter((entry) => entry.isDirectory());
  if (directories.length === 1) candidates.push(join(stagingDir, directories[0].name));

  for (const candidate of candidates) {
    for (const scriptPath of [join(candidate, 'dist', 'macos.sh'), join(candidate, 'macos.sh')]) {
      try {
        return await validateAgentboxPayload(scriptPath, options);
      } catch (error) {
        if (!['payload_missing', 'payload_invalid'].includes(error.code)) throw error;
      }
    }
  }
  throw operationError(
    'archive_invalid',
    'agentbox release archive does not contain a valid payload.',
  );
}

async function assertShimReplaceable(shimPath) {
  const current = await lstat(shimPath).catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (current && !current.isSymbolicLink()) {
    throw operationError(
      'shim_conflict',
      `refusing to replace non-symlink agentbox command at ${shimPath}.`,
    );
  }
}

export async function synchronizeAgentboxShim(config) {
  const selected = selectAgentboxInstallation(config);
  await validateAgentboxPayload(selected.path);
  await assertShimReplaceable(config.binPath);
  await mkdir(dirname(config.binPath), { recursive: true, mode: 0o755 });
  const tempPath = join(dirname(config.binPath), `.agentbox.${randomUUID()}.tmp`);

  try {
    await symlink(selected.path, tempPath);
    await rename(tempPath, config.binPath);
  } catch (error) {
    await rm(tempPath, { force: true });
    throw error;
  }
  return config.binPath;
}

async function persistConfig(config, options = {}) {
  if (config.default) await assertShimReplaceable(config.binPath);
  const configPath = await writeAgentboxInstallationConfig(config, options);
  if (config.default) await synchronizeAgentboxShim(config);
  return configPath;
}

function configuredBinPath(config, options) {
  if (!options.binDir) return config.binPath;
  return join(resolveUserPath(options.binDir, options.env || process.env), 'agentbox');
}

function stableInstallRoot(loaded, options) {
  if (options.installRoot) return resolveUserPath(options.installRoot, options.env || process.env);
  const existingPath = loaded.config.installations.stable?.path;
  if (existingPath) return dirname(dirname(dirname(existingPath)));
  return join(loaded.paths.dataDir, 'releases');
}

async function existingReleasePayload(destination, release, options) {
  const scriptPath = join(destination, 'dist', 'macos.sh');
  const existing = await lstat(scriptPath).catch(() => null);
  if (!existing) return null;
  const payload = await validateAgentboxPayload(scriptPath, options);
  if (normalizeVersion(payload.version) !== normalizeVersion(release.tag)) {
    throw operationError(
      'release_conflict',
      `existing release directory ${destination} reports ${payload.version}, not ${release.tag}.`,
    );
  }
  return payload;
}

export async function installStableAgentbox(options = {}) {
  const env = options.env || process.env;
  const loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  const release = await resolveLatestStableRelease(options);
  const installRoot = stableInstallRoot(loaded, { ...options, env });
  const destination = join(installRoot, release.tag);
  let payload = await existingReleasePayload(destination, release, { env });
  let changed = false;

  if (!payload) {
    const archivePath = await downloadArchive(release, loaded.paths.cacheDir, options);
    const stagingDir = join(installRoot, `.staging-${randomUUID()}`);
    await mkdir(installRoot, { recursive: true, mode: 0o700 });
    try {
      await extractArchive(archivePath, stagingDir);
      const stagedPayload = await findExtractedPayload(stagingDir, { env });
      if (normalizeVersion(stagedPayload.version) !== normalizeVersion(release.tag)) {
        throw operationError(
          'release_version_mismatch',
          `agentbox release ${release.tag} contains script version ${stagedPayload.version}.`,
        );
      }
      await rename(stagedPayload.root, destination);
      if (stagedPayload.root !== stagingDir) {
        await rm(stagingDir, { recursive: true, force: true });
      }
      payload = await validateAgentboxPayload(join(destination, 'dist', 'macos.sh'), { env });
      changed = true;
    } catch (error) {
      await rm(stagingDir, { recursive: true, force: true });
      throw error;
    }
  }

  const nextConfig = withAgentboxInstallation(
    loaded.config,
    'stable',
    {
      kind: 'release',
      version: payload.version,
      path: payload.path,
      releaseTag: release.tag,
      updatedAt: (options.now || new Date()).toISOString(),
    },
    { binPath: configuredBinPath(loaded.config, { ...options, env }) },
  );
  const configPath = await persistConfig(nextConfig, { env });

  return {
    status: changed ? 'installed' : 'current',
    changed,
    key: 'stable',
    version: payload.version,
    path: payload.path,
    default: nextConfig.default,
    configPath,
    binPath: nextConfig.binPath,
    pathWarning: !isDirectoryOnPath(dirname(nextConfig.binPath), env.PATH || ''),
  };
}

export async function registerSourceAgentbox(inputPath, options = {}) {
  const env = options.env || process.env;
  const loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  const payload = await validateAgentboxPayload(inputPath, { env });
  const nextConfig = withAgentboxInstallation(
    loaded.config,
    'source',
    {
      kind: 'source',
      version: payload.version,
      path: payload.path,
      updatedAt: (options.now || new Date()).toISOString(),
    },
    { binPath: configuredBinPath(loaded.config, { ...options, env }) },
  );
  const configPath = await persistConfig(nextConfig, { env });

  return {
    status: 'registered',
    key: 'source',
    version: payload.version,
    path: payload.path,
    default: nextConfig.default,
    configPath,
    binPath: nextConfig.binPath,
    pathWarning: !isDirectoryOnPath(dirname(nextConfig.binPath), env.PATH || ''),
  };
}

export async function useAgentboxInstallation(key, options = {}) {
  const env = options.env || process.env;
  const loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  let nextConfig = withDefaultAgentboxInstallation(loaded.config, key);
  nextConfig = { ...nextConfig, binPath: configuredBinPath(nextConfig, { ...options, env }) };
  await validateAgentboxPayload(selectAgentboxInstallation(nextConfig).path, { env });
  const configPath = await persistConfig(nextConfig, { env });

  return {
    status: 'selected',
    key,
    path: nextConfig.installations[key].path,
    version: nextConfig.installations[key].version,
    configPath,
    binPath: nextConfig.binPath,
    pathWarning: !isDirectoryOnPath(dirname(nextConfig.binPath), env.PATH || ''),
  };
}

async function inspectShim(config) {
  const current = await lstat(config.binPath).catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (!current) return { status: 'missing', path: config.binPath, target: null };
  if (!current.isSymbolicLink()) {
    return { status: 'conflict', path: config.binPath, target: null };
  }
  const target = await readlink(config.binPath);
  const expected = config.default ? config.installations[config.default]?.path : null;
  return {
    status: target === expected ? 'current' : 'stale',
    path: config.binPath,
    target,
    expected,
  };
}

export async function statusAgentboxInstallations(options = {}) {
  const env = options.env || process.env;
  const loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  const installations = {};

  for (const [key, installation] of Object.entries(loaded.config.installations)) {
    try {
      const payload = await validateAgentboxPayload(installation.path, { env });
      installations[key] = {
        ...installation,
        status: 'available',
        path: payload.path,
        version: payload.version,
      };
    } catch (error) {
      installations[key] = {
        ...installation,
        status: 'unavailable',
        error: { code: error.code || 'unknown', detail: error.message },
      };
    }
  }

  return {
    status: loaded.exists ? 'configured' : 'unconfigured',
    configPath: loaded.paths.configFile,
    default: loaded.config.default,
    installations,
    shim: await inspectShim(loaded.config),
    path: {
      directory: dirname(loaded.config.binPath),
      configured: isDirectoryOnPath(dirname(loaded.config.binPath), env.PATH || ''),
    },
  };
}

export async function resolveAgentboxExecutable(key, options = {}) {
  return resolveConfiguredAgentboxInstallation({ ...options, key });
}

export async function inspectDefaultAgentboxExecutable(options = {}) {
  return inspectConfiguredAgentboxInstallation(options);
}
