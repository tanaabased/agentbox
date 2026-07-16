import { lstat, readFile, readdir, realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));

export const CODEXSYNC_COMMANDS = Object.freeze(['check', 'sync', 'validate']);
export const CODEXSYNC_MARKETPLACE = 'pirostore';
export const DEFAULT_REPO_ROOT = resolve(MODULE_DIR, '..');
export const MANAGED_PLUGIN_PATHS = Object.freeze([
  '.codex-plugin',
  '.mcp.json',
  'AGENTS.md',
  'ADVANCED.md',
  'README.md',
  'assets',
  'bin/codexsync.js',
  'lib',
  'package.json',
  'scripts/check-plugin-runtime.sh',
  'skills',
]);

async function readJson(targetPath) {
  return JSON.parse(await readFile(targetPath, 'utf8'));
}

export async function resolveCodexsyncContext(options = {}) {
  const repoRoot = await realpath(resolve(options.repoRoot || DEFAULT_REPO_ROOT));
  const packageJson = await readJson(join(repoRoot, 'package.json'));
  const pluginJson = await readJson(join(repoRoot, '.codex-plugin', 'plugin.json'));
  const defaultPluginCacheRoot = join(
    options.homeDir || homedir(),
    '.codex',
    'plugins',
    'cache',
    CODEXSYNC_MARKETPLACE,
    pluginJson.name,
  );
  const cachePath = resolve(
    options.cachePathOverride || join(defaultPluginCacheRoot, packageJson.version),
  );

  return {
    cachePath,
    managedPaths: options.managedPaths || MANAGED_PLUGIN_PATHS,
    packageJson,
    pluginCacheRoot: options.cachePathOverride
      ? dirname(cachePath)
      : resolve(defaultPluginCacheRoot),
    pluginJson,
    repoRoot,
    stderr: options.stderr || process.stderr,
    stdout: options.stdout || process.stdout,
  };
}

export async function inspectCodexCacheInstallation(context) {
  let cacheStat;
  try {
    cacheStat = await lstat(context.cachePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  if (cacheStat && !cacheStat.isDirectory()) {
    throw new Error(`Codex plugin cache path is not a directory: ${context.cachePath}`);
  }

  let installationIssue = cacheStat ? null : 'cache path is missing';
  if (cacheStat) {
    const manifestPath = join(context.cachePath, '.codex-plugin', 'plugin.json');
    let cacheManifest;
    try {
      cacheManifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    } catch (error) {
      if (error.code === 'ENOENT') {
        installationIssue = 'cached plugin manifest is missing';
      } else if (error instanceof SyntaxError) {
        installationIssue = 'cached plugin manifest is invalid JSON';
      } else {
        throw error;
      }
    }

    if (cacheManifest && cacheManifest.name !== context.pluginJson.name) {
      installationIssue = `cached plugin name is ${cacheManifest.name || 'missing'}`;
    } else if (cacheManifest && cacheManifest.version !== context.packageJson.version) {
      installationIssue = `cached plugin version is ${cacheManifest.version || 'missing'}`;
    }
  }

  let installedVersions = [];
  try {
    const entries = await readdir(context.pluginCacheRoot, { withFileTypes: true });
    installedVersions = entries
      .filter((entry) => entry.isDirectory() || entry.isSymbolicLink())
      .map((entry) => entry.name)
      .sort((left, right) => left.localeCompare(right));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  return {
    cachePresent: Boolean(cacheStat),
    installationIssue,
    installed: Boolean(cacheStat) && !installationIssue,
    installedVersions,
    version: context.packageJson.version,
  };
}
