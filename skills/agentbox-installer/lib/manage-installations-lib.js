import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import {
  chmod,
  lstat,
  mkdir,
  readFile,
  readdir,
  readlink,
  realpath,
  rename,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { delimiter, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import {
  AgentboxInstallationError,
  assertAgentboxInstallationMatchesPayload,
  createAgentboxInstallationConfig,
  inspectConfiguredAgentboxInstallation,
  isDirectoryOnPath,
  loadAgentboxInstallationConfig,
  resolveAgentboxInstallationPaths,
  resolveConfiguredAgentboxInstallation,
  selectAgentboxInstallation,
  validateAgentboxPayload,
  withAgentboxInstallation,
  withDefaultAgentboxInstallation,
  writeAgentboxInstallationConfig,
} from '../../../lib/agentbox-installations.js';

export const AGENTBOX_RELEASE_API_URL =
  'https://api.github.com/repos/tanaabased/agentbox/releases/latest';
const DEFAULT_METADATA_TIMEOUT_MS = 30_000;
const DEFAULT_ARCHIVE_TIMEOUT_MS = 120_000;
const DEFAULT_FETCH_RETRIES = 2;
const DEFAULT_RETRY_DELAY_MS = 250;
const RETRYABLE_HTTP_STATUSES = new Set([429, 502, 503, 504]);

function operationError(code, message) {
  return new AgentboxInstallationError(code, message);
}

function agentboxHandoff(installationKey, defaultKey) {
  return {
    skill: '$tanaab-agentbox',
    installationKey,
    defaultKey,
  };
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

function retryDelayMs(error, attempt, options) {
  if (options.retryDelayMs !== undefined) return options.retryDelayMs;

  const retryAfter = error.retryAfter?.trim();
  if (/^[0-9]+$/.test(retryAfter || '')) return Number(retryAfter) * 1000;
  if (retryAfter) {
    const retryAt = Date.parse(retryAfter);
    if (Number.isFinite(retryAt)) return Math.max(0, retryAt - Date.now());
  }
  return DEFAULT_RETRY_DELAY_MS * 2 ** attempt;
}

function isRetryableDownloadError(error) {
  return (
    error.code === 'download_failed' &&
    (error.status === undefined || RETRYABLE_HTTP_STATUSES.has(error.status))
  );
}

async function fetchResponseOnce(fetchImpl, url, responseType, options) {
  const timeoutMs =
    options.fetchTimeoutMs ||
    (responseType === 'arrayBuffer' ? DEFAULT_ARCHIVE_TIMEOUT_MS : DEFAULT_METADATA_TIMEOUT_MS);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetchImpl(url, {
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'agentbox-installer',
        'X-GitHub-Api-Version': '2026-03-10',
      },
      signal: controller.signal,
    });
    if (!response.ok) {
      const error = operationError(
        'download_failed',
        `request failed with status ${response.status}: ${url}.`,
      );
      error.status = response.status;
      error.retryAfter = response.headers?.get?.('retry-after') || null;
      throw error;
    }
    return await response[responseType]();
  } catch (error) {
    if (controller.signal.aborted) {
      throw operationError('download_timeout', `request timed out after ${timeoutMs}ms: ${url}.`);
    }
    if (error instanceof AgentboxInstallationError) throw error;
    throw operationError('download_failed', `request failed for ${url}: ${error.message}.`);
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchResponse(fetchImpl, url, responseType, options = {}) {
  const retries = options.fetchRetries ?? DEFAULT_FETCH_RETRIES;
  const sleepImpl =
    options.sleepImpl || ((delayMs) => new Promise((resolve) => setTimeout(resolve, delayMs)));

  for (let attempt = 0; ; attempt += 1) {
    try {
      return await fetchResponseOnce(fetchImpl, url, responseType, options);
    } catch (error) {
      if (attempt >= retries || !isRetryableDownloadError(error)) throw error;
      await sleepImpl(retryDelayMs(error, attempt, options));
    }
  }
}

export async function resolveLatestStableRelease(options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const metadata = await fetchResponse(
    fetchImpl,
    options.releaseApiUrl || AGENTBOX_RELEASE_API_URL,
    'json',
    options,
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
    await fetchResponse(fetchImpl, release.archiveUrl, 'arrayBuffer', options),
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
  const result = spawnSync('tar', args, {
    encoding: 'utf8',
    maxBuffer: 8 * 1024 * 1024,
    timeout: DEFAULT_ARCHIVE_TIMEOUT_MS,
  });
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
  const entryDetails = runTar(['-tvzf', archivePath], 'could not inspect agentbox release archive')
    .split(/\r?\n/)
    .filter(Boolean);
  if (entryDetails.some((entry) => !['-', 'd'].includes(entry[0]))) {
    throw operationError(
      'archive_unsafe',
      'agentbox release archive contains links or special files.',
    );
  }
  await mkdir(stagingDir, { recursive: true, mode: 0o700 });
  runTar(['-xzf', archivePath, '-C', stagingDir], 'could not extract agentbox release archive');
  await validateExtractedArchive(stagingDir);
}

async function validateExtractedArchive(root) {
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const entryPath = join(root, entry.name);
    const entryStat = await lstat(entryPath);
    if (entryStat.isSymbolicLink()) {
      throw operationError(
        'archive_unsafe',
        `agentbox release archive contains a link: ${entryPath}.`,
      );
    }
    if (entryStat.isDirectory()) {
      await validateExtractedArchive(entryPath);
      continue;
    }
    if (!entryStat.isFile() || entryStat.nlink !== 1) {
      throw operationError(
        'archive_unsafe',
        `agentbox release archive contains an unsupported entry: ${entryPath}.`,
      );
    }
  }
}

async function assertPayloadContained(stagingDir, payloadRoot) {
  const [resolvedStaging, resolvedPayload] = await Promise.all([
    realpath(stagingDir),
    realpath(payloadRoot),
  ]);
  const relativePath = relative(resolvedStaging, resolvedPayload);
  if (relativePath === '..' || relativePath.startsWith(`..${sep}`) || isAbsolute(relativePath)) {
    throw operationError(
      'archive_unsafe',
      `agentbox release payload resolves outside extraction staging: ${resolvedPayload}.`,
    );
  }
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

async function prepareAgentboxShim(config, options = {}) {
  if (!config.linkCommand) {
    throw operationError(
      'command_link_disabled',
      'refusing to create an agentbox command link because linkCommand is disabled.',
    );
  }
  const selected = selectAgentboxInstallation(config);
  const payload = await validateAgentboxPayload(selected.path, options);
  assertAgentboxInstallationMatchesPayload(selected, payload);
  await assertShimReplaceable(config.binPath);
  await mkdir(dirname(config.binPath), { recursive: true, mode: 0o755 });
  const tempPath = join(dirname(config.binPath), `.agentbox.${randomUUID()}.tmp`);

  try {
    await symlink(selected.path, tempPath);
  } catch (error) {
    await rm(tempPath, { force: true });
    throw error;
  }
  return { shimPath: config.binPath, tempPath };
}

async function commitAgentboxShim(prepared) {
  try {
    await assertShimReplaceable(prepared.shimPath);
    await rename(prepared.tempPath, prepared.shimPath);
  } catch (error) {
    await rm(prepared.tempPath, { force: true });
    throw error;
  }
}

export async function synchronizeAgentboxShim(config, options = {}) {
  const prepared = await prepareAgentboxShim(config, options);
  await commitAgentboxShim(prepared);
  return prepared.shimPath;
}

async function restorePreviousConfig(configPath, options) {
  if (options.previousConfigExists) {
    await writeAgentboxInstallationConfig(options.previousConfig, options);
    return;
  }
  await rm(configPath, { force: true });
}

async function prepareShimMigration(previousConfig, nextConfig) {
  if (
    !previousConfig?.linkCommand ||
    resolve(previousConfig.binPath) === resolve(nextConfig.binPath)
  )
    return null;
  const current = await lstat(previousConfig.binPath).catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (!current) return null;
  if (!current.isSymbolicLink() || !previousConfig.default) {
    throw operationError(
      'shim_migration_conflict',
      `refusing to migrate unmanaged agentbox command at ${previousConfig.binPath}.`,
    );
  }
  const target = await readlink(previousConfig.binPath);
  const resolvedTarget = resolve(dirname(previousConfig.binPath), target);
  const expectedTarget = resolve(selectAgentboxInstallation(previousConfig).path);
  if (resolvedTarget !== expectedTarget) {
    throw operationError(
      'shim_migration_conflict',
      `refusing to migrate stale agentbox command at ${previousConfig.binPath}.`,
    );
  }
  return {
    shimPath: previousConfig.binPath,
    backupPath: join(dirname(previousConfig.binPath), `.agentbox.${randomUUID()}.migration`),
  };
}

async function persistConfig(config, options = {}) {
  const prepared =
    config.default && config.linkCommand && options.synchronizeShim !== false
      ? await prepareAgentboxShim(config, options)
      : null;
  const migration = await prepareShimMigration(options.previousConfig, config);
  let configPath = null;
  let migrationStaged = false;

  try {
    if (migration) {
      await rename(migration.shimPath, migration.backupPath);
      migrationStaged = true;
    }
    configPath = await writeAgentboxInstallationConfig(config, options);
    if (prepared) await commitAgentboxShim(prepared);
    if (migrationStaged) {
      await rm(migration.backupPath, { force: true }).catch(() => {});
      migrationStaged = false;
    }
    return configPath;
  } catch (error) {
    if (prepared) await rm(prepared.tempPath, { force: true });
    const rollbackErrors = [];
    if (configPath) {
      try {
        await restorePreviousConfig(configPath, options);
      } catch (rollbackError) {
        rollbackErrors.push(`config rollback failed: ${rollbackError.message}`);
      }
    }
    if (migrationStaged) {
      try {
        await rename(migration.backupPath, migration.shimPath);
      } catch (rollbackError) {
        rollbackErrors.push(`command shim rollback failed: ${rollbackError.message}`);
      }
    }
    if (rollbackErrors.length > 0) {
      throw operationError(
        'state_inconsistent',
        `agentbox state update failed (${error.message}); ${rollbackErrors.join('; ')}.`,
      );
    }
    throw error;
  }
}

function configuredCommandOptions(config, options) {
  if (options.binDir && options.linkCommand !== true) {
    throw operationError(
      'link_command_required',
      '--bin-dir requires --link-command because command linking is otherwise disabled.',
    );
  }
  return {
    binPath: options.binDir
      ? join(resolveUserPath(options.binDir, options.env || process.env), 'agentbox')
      : config.binPath,
    linkCommand: config.linkCommand || options.linkCommand === true,
  };
}

function commandResult(config, env) {
  return {
    binPath: config.binPath,
    linkCommand: config.linkCommand,
    pathWarning: config.linkCommand && !isDirectoryOnPath(dirname(config.binPath), env.PATH || ''),
  };
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

function stableInstallationMatches(current, payload, release) {
  return Boolean(
    current &&
    current.kind === 'release' &&
    current.path === payload.path &&
    normalizeVersion(current.version) === normalizeVersion(payload.version) &&
    normalizeVersion(current.releaseTag) === normalizeVersion(release.tag),
  );
}

export async function repairInvalidAgentboxInstallationConfig(options = {}) {
  const env = options.env || process.env;
  const paths = resolveAgentboxInstallationPaths({ env });
  let invalidError = null;

  try {
    await loadAgentboxInstallationConfig({ env });
  } catch (error) {
    if (error.code !== 'config_invalid') throw error;
    invalidError = error;
  }
  if (!invalidError) {
    throw operationError(
      'config_valid',
      `refusing to reset valid agentbox installation config at ${paths.configFile}.`,
    );
  }

  const configStat = await lstat(paths.configFile);
  if (!configStat.isFile()) {
    throw operationError(
      'config_repair_unsupported',
      `refusing to repair non-file agentbox installation config at ${paths.configFile}.`,
    );
  }
  const timestamp = (options.now || new Date()).toISOString().replaceAll(':', '-');
  const backupPath = `${paths.configFile}.invalid-${timestamp}-${randomUUID()}.bak`;
  await rename(paths.configFile, backupPath);
  try {
    await chmod(backupPath, 0o600);
    await writeAgentboxInstallationConfig(createAgentboxInstallationConfig(paths), { env });
  } catch (error) {
    try {
      await rm(paths.configFile, { force: true });
      await rename(backupPath, paths.configFile);
    } catch (rollbackError) {
      throw operationError(
        'state_inconsistent',
        `agentbox config repair failed (${error.message}) and rollback failed (${rollbackError.message}).`,
      );
    }
    throw error;
  }

  return {
    status: 'reset',
    configPath: paths.configFile,
    backupPath,
    previousError: { code: invalidError.code, detail: invalidError.message },
  };
}

export async function installStableAgentbox(options = {}) {
  const env = options.env || process.env;
  const loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  const release = await resolveLatestStableRelease(options);
  const installRoot = stableInstallRoot(loaded, { ...options, env });
  const destination = join(installRoot, release.tag);
  let payload = await existingReleasePayload(destination, release, { env });
  let payloadChanged = false;

  if (!payload) {
    const archivePath = await downloadArchive(release, loaded.paths.cacheDir, options);
    const stagingDir = join(installRoot, `.staging-${randomUUID()}`);
    await mkdir(installRoot, { recursive: true, mode: 0o700 });
    try {
      await extractArchive(archivePath, stagingDir);
      const stagedPayload = await findExtractedPayload(stagingDir, { env });
      await assertPayloadContained(stagingDir, stagedPayload.root);
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
      payloadChanged = true;
    } catch (error) {
      await rm(stagingDir, { recursive: true, force: true });
      throw error;
    }
  }

  const currentInstallation = loaded.config.installations.stable;
  const installation = stableInstallationMatches(currentInstallation, payload, release)
    ? currentInstallation
    : {
        kind: 'release',
        version: payload.version,
        path: payload.path,
        releaseTag: release.tag,
        updatedAt: (options.now || new Date()).toISOString(),
      };
  const nextConfig = withAgentboxInstallation(
    loaded.config,
    'stable',
    installation,
    configuredCommandOptions(loaded.config, { ...options, env }),
  );
  const configChanged = !loaded.exists || !isDeepStrictEqual(nextConfig, loaded.config);
  const binPathChanged = resolve(nextConfig.binPath) !== resolve(loaded.config.binPath);
  const shimChanged =
    nextConfig.default && nextConfig.linkCommand
      ? binPathChanged || (await inspectShim(nextConfig)).status !== 'current'
      : false;
  let configPath = loaded.paths.configFile;

  if (configChanged) {
    configPath = await persistConfig(nextConfig, {
      env,
      previousConfig: loaded.config,
      previousConfigExists: loaded.exists,
      synchronizeShim: shimChanged,
    });
  } else if (shimChanged) {
    await synchronizeAgentboxShim(nextConfig, { env });
  }

  const changed = payloadChanged || configChanged || shimChanged;
  const status = payloadChanged ? 'installed' : changed ? 'reconciled' : 'current';

  return {
    status,
    changed,
    payloadChanged,
    configChanged,
    shimChanged,
    key: 'stable',
    version: payload.version,
    path: payload.path,
    default: nextConfig.default,
    configPath,
    ...commandResult(nextConfig, env),
    handoff: agentboxHandoff('stable', nextConfig.default),
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
    configuredCommandOptions(loaded.config, { ...options, env }),
  );
  const configPath = await persistConfig(nextConfig, {
    env,
    previousConfig: loaded.config,
    previousConfigExists: loaded.exists,
  });

  return {
    status: 'registered',
    key: 'source',
    version: payload.version,
    path: payload.path,
    default: nextConfig.default,
    configPath,
    ...commandResult(nextConfig, env),
    handoff: agentboxHandoff('source', nextConfig.default),
  };
}

export async function useAgentboxInstallation(key, options = {}) {
  const env = options.env || process.env;
  const loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  const nextConfig = withDefaultAgentboxInstallation(
    loaded.config,
    key,
    configuredCommandOptions(loaded.config, { ...options, env }),
  );
  const selected = selectAgentboxInstallation(nextConfig);
  const payload = await validateAgentboxPayload(selected.path, { env });
  assertAgentboxInstallationMatchesPayload(selected, payload);
  const configPath = await persistConfig(nextConfig, {
    env,
    previousConfig: loaded.config,
    previousConfigExists: loaded.exists,
  });

  return {
    status: 'selected',
    key,
    path: nextConfig.installations[key].path,
    configuredVersion: nextConfig.installations[key].version,
    version: payload.version,
    configPath,
    ...commandResult(nextConfig, env),
    handoff: agentboxHandoff(key, nextConfig.default),
  };
}

async function inspectShim(config) {
  const expected = config.default ? config.installations[config.default]?.path : null;
  if (!config.linkCommand) {
    return {
      status: 'disabled',
      path: config.binPath,
      target: null,
      expected,
    };
  }
  const current = await lstat(config.binPath).catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (!current) return { status: 'missing', path: config.binPath, target: null };
  if (!current.isSymbolicLink()) {
    return { status: 'conflict', path: config.binPath, target: null };
  }
  const target = await readlink(config.binPath);
  const resolvedTarget = resolve(dirname(config.binPath), target);
  return {
    status: expected && resolvedTarget === resolve(expected) ? 'current' : 'stale',
    path: config.binPath,
    target,
    expected,
  };
}

async function inspectCommandsOnPath(config, env) {
  const commands = [];
  const seenDirectories = new Set();
  const registeredTargets = new Set(
    Object.values(config.installations).map((installation) => resolve(installation.path)),
  );
  const expectedTarget = config.default
    ? resolve(config.installations[config.default]?.path)
    : null;

  for (const rawDirectory of (env.PATH || '').split(delimiter)) {
    if (!rawDirectory) continue;
    const directory = resolve(rawDirectory);
    if (seenDirectories.has(directory)) continue;
    seenDirectories.add(directory);

    const commandPath = join(directory, 'agentbox');
    const commandStat = await lstat(commandPath).catch((error) => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    if (!commandStat) continue;

    const kind = commandStat.isSymbolicLink() ? 'symlink' : commandStat.isFile() ? 'file' : 'other';
    const target = kind === 'symlink' ? await readlink(commandPath) : null;
    const resolvedTarget = target ? resolve(dirname(commandPath), target) : null;
    const configuredPath = resolve(commandPath) === resolve(config.binPath);
    let relation = 'external';

    if (
      config.linkCommand &&
      configuredPath &&
      resolvedTarget &&
      resolvedTarget === expectedTarget
    ) {
      relation = 'managed-current';
    } else if (config.linkCommand && configuredPath) {
      relation = 'managed-conflict';
    } else if (resolvedTarget && registeredTargets.has(resolvedTarget)) {
      relation = 'registered';
    }

    commands.push({
      path: commandPath,
      kind,
      target,
      resolvedTarget,
      relation,
      effective: commands.length === 0,
    });
  }

  return commands;
}

export async function statusAgentboxInstallations(options = {}) {
  const env = options.env || process.env;
  const paths = resolveAgentboxInstallationPaths({ env, binDir: options.binDir });
  let loaded;
  try {
    loaded = await loadAgentboxInstallationConfig({ env, binDir: options.binDir });
  } catch (error) {
    if (error.code !== 'config_invalid') throw error;
    return {
      status: 'invalid_config',
      configPath: paths.configFile,
      error: { code: error.code, detail: error.message },
    };
  }
  const directoryOnPath = isDirectoryOnPath(dirname(loaded.config.binPath), env.PATH || '');
  const installations = {};

  for (const [key, installation] of Object.entries(loaded.config.installations)) {
    try {
      const payload = await validateAgentboxPayload(installation.path, { env });
      assertAgentboxInstallationMatchesPayload({ key, ...installation }, payload);
      installations[key] = {
        ...installation,
        status: 'available',
        path: payload.path,
        configuredVersion: installation.version,
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
    linkCommand: loaded.config.linkCommand,
    installations,
    shim: await inspectShim(loaded.config),
    commandsOnPath: await inspectCommandsOnPath(loaded.config, env),
    path: {
      directory: dirname(loaded.config.binPath),
      configured: loaded.config.linkCommand && directoryOnPath,
      directoryOnPath,
    },
  };
}

export async function resolveAgentboxExecutable(key, options = {}) {
  return resolveConfiguredAgentboxInstallation({ ...options, key });
}

export async function inspectDefaultAgentboxExecutable(options = {}) {
  return inspectConfiguredAgentboxInstallation(options);
}
