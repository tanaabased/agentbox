import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import {
  access,
  chmod,
  lstat,
  mkdir,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import { delimiter, dirname, isAbsolute, join, resolve } from 'node:path';

export const AGENTBOX_CONFIG_SCHEMA_VERSION = 1;
export const AGENTBOX_INSTALLATION_KEYS = Object.freeze(['stable', 'source']);

const installationKeySet = new Set(AGENTBOX_INSTALLATION_KEYS);
const requiredPayloadPaths = [
  'Brewfile',
  'bin/health.sh',
  'launchd/dev.tanaab.agentbox.health.plist.in',
  'launchd/dev.tanaab.agentbox.tailscaled.plist.in',
  'launchd/dev.tanaab.agentbox.openclaw-gateway.plist.in',
  'assets/default_avatar.png',
];

export class AgentboxInstallationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AgentboxInstallationError';
    this.code = code;
  }
}

function requireHome(env) {
  if (!env.HOME) {
    throw new AgentboxInstallationError(
      'home_missing',
      'HOME is required to resolve agentbox paths.',
    );
  }
  return resolve(env.HOME);
}

function expandHomePath(value, home) {
  if (value === '~') return home;
  if (value.startsWith('~/')) return join(home, value.slice(2));
  return isAbsolute(value) ? value : resolve(home, value);
}

function configError(message) {
  return new AgentboxInstallationError('config_invalid', message);
}

function normalizeVersion(value) {
  return value.replace(/^v/, '');
}

async function pathExists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function payloadRootForScript(scriptPath) {
  const scriptDir = dirname(scriptPath);
  const candidates = [scriptDir, dirname(scriptDir), dirname(dirname(scriptDir))];

  for (const candidate of candidates) {
    const requiredResults = await Promise.all(
      requiredPayloadPaths.map((relativePath) => pathExists(join(candidate, relativePath))),
    );
    if (!requiredResults.every(Boolean)) continue;
    const assets = await readdir(join(candidate, 'assets'));
    if (assets.some((entry) => /^profile.*[.]png$/.test(entry))) return candidate;
  }

  return null;
}

export function resolveAgentboxInstallationPaths(options = {}) {
  const env = options.env || process.env;
  const home = requireHome(env);
  const configRoot = expandHomePath(env.XDG_CONFIG_HOME || join(home, '.config'), home);
  const dataRoot = expandHomePath(env.XDG_DATA_HOME || join(home, '.local', 'share'), home);
  const cacheRoot = expandHomePath(env.XDG_CACHE_HOME || join(home, '.cache'), home);
  const binDir = expandHomePath(options.binDir || join(home, '.local', 'bin'), home);

  return {
    home,
    configDir: join(configRoot, 'agentbox'),
    configFile: join(configRoot, 'agentbox', 'config.json'),
    dataDir: join(dataRoot, 'agentbox'),
    cacheDir: join(cacheRoot, 'agentbox'),
    binDir,
    shimPath: join(binDir, 'agentbox'),
  };
}

export function createAgentboxInstallationConfig(paths) {
  return {
    schemaVersion: AGENTBOX_CONFIG_SCHEMA_VERSION,
    default: null,
    binPath: paths.shimPath,
    installations: {},
  };
}

export function validateAgentboxInstallationConfig(config) {
  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    throw configError('agentbox installation config must be an object.');
  }
  if (config.schemaVersion !== AGENTBOX_CONFIG_SCHEMA_VERSION) {
    throw configError(
      `agentbox installation config schemaVersion must be ${AGENTBOX_CONFIG_SCHEMA_VERSION}.`,
    );
  }
  if (!isAbsolute(config.binPath || '')) {
    throw configError('agentbox installation config binPath must be an absolute path.');
  }
  if (!config.installations || typeof config.installations !== 'object') {
    throw configError('agentbox installation config installations must be an object.');
  }

  for (const [key, installation] of Object.entries(config.installations)) {
    if (!installationKeySet.has(key)) {
      throw configError(`unsupported agentbox installation key: ${key}.`);
    }
    if (!installation || typeof installation !== 'object' || Array.isArray(installation)) {
      throw configError(`agentbox installation ${key} must be an object.`);
    }
    const expectedKind = key === 'stable' ? 'release' : 'source';
    if (installation.kind !== expectedKind) {
      throw configError(`agentbox installation ${key} kind must be ${expectedKind}.`);
    }
    if (!isAbsolute(installation.path || '')) {
      throw configError(`agentbox installation ${key} path must be absolute.`);
    }
    if (typeof installation.version !== 'string' || !installation.version.trim()) {
      throw configError(`agentbox installation ${key} version must be a non-empty string.`);
    }
    if (key === 'stable') {
      if (typeof installation.releaseTag !== 'string' || !installation.releaseTag.trim()) {
        throw configError('agentbox installation stable releaseTag must be a non-empty string.');
      }
      if (normalizeVersion(installation.version) !== normalizeVersion(installation.releaseTag)) {
        throw configError('agentbox installation stable version must match its releaseTag.');
      }
    }
  }

  if (config.default !== null && !installationKeySet.has(config.default)) {
    throw configError('agentbox installation config default must be stable, source, or null.');
  }
  if (config.default !== null && !config.installations[config.default]) {
    throw configError(`default agentbox installation ${config.default} is not registered.`);
  }

  return config;
}

export async function loadAgentboxInstallationConfig(options = {}) {
  const paths = resolveAgentboxInstallationPaths(options);

  try {
    const config = JSON.parse(await readFile(paths.configFile, 'utf8'));
    validateAgentboxInstallationConfig(config);
    return { config, exists: true, paths };
  } catch (error) {
    if (error.code === 'ENOENT') {
      return { config: createAgentboxInstallationConfig(paths), exists: false, paths };
    }
    if (error instanceof SyntaxError) {
      throw configError(`could not parse ${paths.configFile}: ${error.message}`);
    }
    throw error;
  }
}

export async function writeAgentboxInstallationConfig(config, options = {}) {
  validateAgentboxInstallationConfig(config);
  const paths = resolveAgentboxInstallationPaths(options);
  const tempPath = join(paths.configDir, `.config.${randomUUID()}.tmp`);

  await mkdir(paths.configDir, { recursive: true, mode: 0o700 });
  await chmod(paths.configDir, 0o700);
  try {
    await writeFile(tempPath, `${JSON.stringify(config, null, 2)}\n`, {
      encoding: 'utf8',
      flag: 'wx',
      mode: 0o600,
    });
    await chmod(tempPath, 0o600);
    await rename(tempPath, paths.configFile);
    await chmod(paths.configFile, 0o600);
  } catch (error) {
    await rm(tempPath, { force: true });
    throw error;
  }

  return paths.configFile;
}

export function withAgentboxInstallation(config, key, installation, options = {}) {
  if (!installationKeySet.has(key)) {
    throw configError(`unsupported agentbox installation key: ${key}.`);
  }
  const nextConfig = {
    ...config,
    binPath: options.binPath || config.binPath,
    installations: {
      ...config.installations,
      [key]: { ...installation },
    },
  };
  if (nextConfig.default === null && options.makeDefault !== false) nextConfig.default = key;
  validateAgentboxInstallationConfig(nextConfig);
  return nextConfig;
}

export function withDefaultAgentboxInstallation(config, key) {
  if (!config.installations[key]) {
    throw new AgentboxInstallationError(
      'installation_missing',
      `agentbox installation ${key} is not registered.`,
    );
  }
  const nextConfig = { ...config, default: key };
  validateAgentboxInstallationConfig(nextConfig);
  return nextConfig;
}

export function selectAgentboxInstallation(config, key = config.default) {
  validateAgentboxInstallationConfig(config);
  if (!key) {
    throw new AgentboxInstallationError(
      'installation_unconfigured',
      'no default agentbox installation is configured.',
    );
  }
  if (!installationKeySet.has(key)) {
    throw new AgentboxInstallationError(
      'installation_key_invalid',
      `unsupported agentbox installation key: ${key}.`,
    );
  }
  const installation = config.installations[key];
  if (!installation) {
    throw new AgentboxInstallationError(
      'installation_missing',
      `agentbox installation ${key} is not registered.`,
    );
  }
  return { key, ...installation };
}

export async function validateAgentboxPayload(inputPath, options = {}) {
  const home = requireHome(options.env || process.env);
  const expandedPath = expandHomePath(inputPath, home);
  const inputStat = await lstat(expandedPath).catch((error) => {
    if (error.code === 'ENOENT') {
      throw new AgentboxInstallationError(
        'payload_missing',
        `agentbox path does not exist: ${expandedPath}.`,
      );
    }
    throw error;
  });
  const scriptCandidate = inputStat.isDirectory() ? join(expandedPath, 'macos.sh') : expandedPath;
  const scriptPath = await realpath(scriptCandidate).catch((error) => {
    if (error.code === 'ENOENT') {
      throw new AgentboxInstallationError(
        'payload_missing',
        `agentbox script does not exist: ${scriptCandidate}.`,
      );
    }
    throw error;
  });
  const payloadRoot = await payloadRootForScript(scriptPath);

  await access(scriptPath, constants.X_OK).catch(() => {
    throw new AgentboxInstallationError(
      'payload_not_executable',
      `agentbox script is not executable: ${scriptPath}.`,
    );
  });
  if (!payloadRoot) {
    throw new AgentboxInstallationError(
      'payload_invalid',
      `could not find the required agentbox payload files relative to ${scriptPath}.`,
    );
  }

  const versionResult = spawnSync(scriptPath, ['--version'], {
    encoding: 'utf8',
    timeout: 10_000,
  });
  const version = versionResult.stdout?.trim();
  if (versionResult.error || versionResult.status !== 0 || !version) {
    throw new AgentboxInstallationError(
      'payload_version_invalid',
      `could not read agentbox version from ${scriptPath}.`,
    );
  }

  return { path: scriptPath, root: payloadRoot, version };
}

export function assertAgentboxInstallationMatchesPayload(installation, payload) {
  if (installation.kind !== 'release') return payload;
  const expectedVersion = installation.releaseTag || installation.version;
  if (normalizeVersion(payload.version) !== normalizeVersion(expectedVersion)) {
    throw new AgentboxInstallationError(
      'installation_version_mismatch',
      `configured stable agentbox ${expectedVersion} reports ${payload.version} at ${payload.path}.`,
    );
  }
  return payload;
}

export async function resolveConfiguredAgentboxInstallation(options = {}) {
  const loaded = await loadAgentboxInstallationConfig(options);
  const selected = selectAgentboxInstallation(loaded.config, options.key);
  const payload = await validateAgentboxPayload(selected.path, options);
  assertAgentboxInstallationMatchesPayload(selected, payload);

  return {
    configPath: loaded.paths.configFile,
    binPath: loaded.config.binPath,
    default: loaded.config.default,
    installation: {
      ...selected,
      path: payload.path,
      configuredVersion: selected.version,
      version: payload.version,
    },
  };
}

export async function inspectConfiguredAgentboxInstallation(options = {}) {
  let paths = null;
  try {
    paths = resolveAgentboxInstallationPaths(options);
    const loaded = await loadAgentboxInstallationConfig(options);
    if (!loaded.exists || !loaded.config.default) {
      return {
        status: 'unconfigured',
        configPath: loaded.paths.configFile,
        binPath: loaded.config.binPath,
        default: null,
        installation: null,
      };
    }
    return {
      status: 'available',
      ...(await resolveConfiguredAgentboxInstallation(options)),
    };
  } catch (error) {
    return {
      status: error.code === 'config_invalid' ? 'invalid_config' : 'unavailable',
      configPath: paths?.configFile || null,
      binPath: paths?.shimPath || null,
      error: {
        code: error.code || 'unknown',
        detail: error.message,
      },
    };
  }
}

export function isDirectoryOnPath(directory, pathValue = process.env.PATH || '') {
  const expected = resolve(directory);
  return pathValue
    .split(delimiter)
    .filter(Boolean)
    .some((entry) => resolve(entry) === expected);
}
