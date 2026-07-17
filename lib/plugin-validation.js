import { readFile, readdir, realpath, stat } from 'node:fs/promises';
import { isAbsolute, relative, resolve, sep } from 'node:path';

function addCheck(context, message) {
  context.checks.push(message);
}

function fail(context, message) {
  context.failures.push(message);
}

function isObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function isInside(rootPath, targetPath) {
  const relativePath = relative(rootPath, targetPath);
  return (
    relativePath === '' ||
    (!isAbsolute(relativePath) && relativePath !== '..' && !relativePath.startsWith(`..${sep}`))
  );
}

async function pathExists(targetPath) {
  try {
    await stat(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function readJson(context, targetPath, label) {
  try {
    return JSON.parse(await readFile(targetPath, 'utf8'));
  } catch (error) {
    fail(context, `${label} is not valid JSON: ${error.message}`);
    return undefined;
  }
}

async function readYaml(context, targetPath, label) {
  let content;
  try {
    content = await readFile(targetPath, 'utf8');
  } catch (error) {
    fail(context, `${label} could not be read: ${error.message}`);
    return undefined;
  }

  try {
    return context.parseYaml(content);
  } catch (error) {
    fail(context, `${label} is not valid YAML: ${error.message}`);
    return undefined;
  }
}

async function checkLocalPath(
  context,
  { basePath, label, rawPath, required = true, expectedType = null },
) {
  if (typeof rawPath !== 'string' || rawPath.trim() === '') {
    if (required) fail(context, `${label} is missing.`);
    return null;
  }

  const normalizedPath = rawPath.trim();
  if (!normalizedPath.startsWith('./')) {
    fail(context, `${label} must start with './': ${normalizedPath}`);
    return null;
  }

  const targetPath = resolve(basePath, normalizedPath);
  if (!isInside(context.repoRoot, targetPath)) {
    fail(context, `${label} escapes the plugin root: ${normalizedPath}`);
    return null;
  }

  let targetStat;
  try {
    targetStat = await stat(targetPath);
  } catch {
    fail(context, `${label} points to a missing path: ${normalizedPath}`);
    return null;
  }

  const resolvedTarget = await realpath(targetPath);
  if (!isInside(context.repoRoot, resolvedTarget)) {
    fail(context, `${label} resolves outside the plugin root: ${normalizedPath}`);
    return null;
  }

  if (expectedType === 'file' && !targetStat.isFile()) {
    fail(context, `${label} must point to a file: ${normalizedPath}`);
    return null;
  }
  if (expectedType === 'directory' && !targetStat.isDirectory()) {
    fail(context, `${label} must point to a directory: ${normalizedPath}`);
    return null;
  }

  return targetPath;
}

function requireString(context, value, label) {
  if (typeof value !== 'string' || value.trim() === '') {
    fail(context, `${label} must be a non-empty string.`);
    return false;
  }
  return true;
}

function parseFrontmatter(context, content, label) {
  const lines = content.split(/\r?\n/);
  if (lines[0] !== '---') {
    fail(context, `${label} must start with YAML frontmatter.`);
    return null;
  }

  const closingIndex = lines.indexOf('---', 1);
  if (closingIndex === -1) {
    fail(context, `${label} has unterminated YAML frontmatter.`);
    return null;
  }

  try {
    const frontmatter = context.parseYaml(lines.slice(1, closingIndex).join('\n'));
    if (!isObject(frontmatter)) {
      fail(context, `${label} frontmatter must be a YAML object.`);
      return null;
    }
    return frontmatter;
  } catch (error) {
    fail(context, `${label} frontmatter is not valid YAML: ${error.message}`);
    return null;
  }
}

async function validateOpenAiMetadata(context, skillDir, skillLabel) {
  const metadataPath = resolve(skillDir, 'agents', 'openai.yaml');
  if (!(await pathExists(metadataPath))) return;

  const metadata = await readYaml(context, metadataPath, `${skillLabel} agents/openai.yaml`);
  if (metadata === undefined) return;
  if (!isObject(metadata)) {
    fail(context, `${skillLabel} agents/openai.yaml must contain a YAML object.`);
    return;
  }

  const pluginInterface = metadata.interface;
  if (pluginInterface === undefined) return;
  if (!isObject(pluginInterface)) {
    fail(context, `${skillLabel} agents/openai.yaml interface must be an object.`);
    return;
  }

  for (const iconField of ['icon_small', 'icon_large']) {
    await checkLocalPath(context, {
      basePath: skillDir,
      label: `${skillLabel} interface.${iconField}`,
      rawPath: pluginInterface[iconField],
      required: false,
      expectedType: 'file',
    });
  }
}

async function validateSkills(context, skillsDir) {
  addCheck(context, 'bundled skills');
  const skillIds = new Set();
  const entries = await readdir(skillsDir, { withFileTypes: true });
  const skillDirs = entries
    .filter((entry) => entry.isDirectory())
    .sort((left, right) => left.name.localeCompare(right.name));

  if (skillDirs.length === 0) {
    fail(context, 'plugin skills directory must contain at least one skill.');
  }

  for (const entry of skillDirs) {
    const skillDir = resolve(skillsDir, entry.name);
    const skillLabel = `skills/${entry.name}`;
    const skillPath = resolve(skillDir, 'SKILL.md');
    let content;
    try {
      content = await readFile(skillPath, 'utf8');
    } catch {
      fail(context, `${skillLabel} is missing SKILL.md.`);
      continue;
    }

    const frontmatter = parseFrontmatter(context, content, `${skillLabel}/SKILL.md`);
    if (!frontmatter) continue;

    if (requireString(context, frontmatter.name, `${skillLabel} frontmatter.name`)) {
      if (skillIds.has(frontmatter.name)) {
        fail(context, `duplicate skill name: ${frontmatter.name}`);
      } else {
        skillIds.add(frontmatter.name);
      }
    }
    requireString(context, frontmatter.description, `${skillLabel} frontmatter.description`);
    await validateOpenAiMetadata(context, skillDir, skillLabel);
  }
}

function validateDefaultPrompts(context, pluginInterface) {
  const rawPrompts = pluginInterface.defaultPrompt;
  if (rawPrompts === undefined) return;

  if (typeof rawPrompts === 'string') {
    requireString(context, rawPrompts, 'plugin interface.defaultPrompt');
    return;
  }
  if (!Array.isArray(rawPrompts)) {
    fail(context, 'plugin interface.defaultPrompt must be a string or an array of strings.');
    return;
  }
  for (const [index, prompt] of rawPrompts.entries()) {
    requireString(context, prompt, `plugin interface.defaultPrompt[${index}]`);
  }
}

async function validateOptionalJsonConfig(context, { label, rawPath, rootKey }) {
  if (rawPath === undefined || rawPath === null) return;

  const configPath = await checkLocalPath(context, {
    basePath: context.repoRoot,
    label,
    rawPath,
    expectedType: 'file',
  });
  if (!configPath) return;

  const config = await readJson(context, configPath, label);
  if (config === undefined) return;
  if (!isObject(config)) {
    fail(context, `${label} must contain a JSON object.`);
    return;
  }
  if (!isObject(config[rootKey])) {
    fail(context, `${label} must contain an ${rootKey} object.`);
  }
}

async function validateManifest(context, pluginJson) {
  addCheck(context, 'plugin manifest');
  if (!isObject(pluginJson)) {
    fail(context, 'plugin manifest must contain a JSON object.');
    return null;
  }

  for (const field of ['name', 'version', 'description']) {
    requireString(context, pluginJson[field], `plugin manifest ${field}`);
  }

  const pluginInterface = pluginJson.interface;
  if (!isObject(pluginInterface)) {
    fail(context, 'plugin manifest interface must be an object.');
    return null;
  }
  validateDefaultPrompts(context, pluginInterface);

  addCheck(context, 'declared plugin resources');
  const skillsDir =
    pluginJson.skills === undefined || pluginJson.skills === null
      ? null
      : await checkLocalPath(context, {
          basePath: context.repoRoot,
          label: 'plugin manifest skills',
          rawPath: pluginJson.skills,
          expectedType: 'directory',
        });

  for (const iconField of ['composerIcon', 'logo', 'logoDark']) {
    await checkLocalPath(context, {
      basePath: context.repoRoot,
      label: `plugin interface.${iconField}`,
      rawPath: pluginInterface[iconField],
      required: false,
      expectedType: 'file',
    });
  }

  if (pluginInterface.screenshots !== undefined) {
    if (!Array.isArray(pluginInterface.screenshots)) {
      fail(context, 'plugin interface.screenshots must be an array.');
    } else {
      for (const [index, screenshotPath] of pluginInterface.screenshots.entries()) {
        await checkLocalPath(context, {
          basePath: context.repoRoot,
          label: `plugin interface.screenshots[${index}]`,
          rawPath: screenshotPath,
          expectedType: 'file',
        });
      }
    }
  }

  await validateOptionalJsonConfig(context, {
    label: 'plugin apps config',
    rawPath: pluginJson.apps,
    rootKey: 'apps',
  });
  await validateOptionalJsonConfig(context, {
    label: 'plugin MCP config',
    rawPath: pluginJson.mcpServers,
    rootKey: 'mcpServers',
  });

  return skillsDir;
}

/**
 * Validates the loader-facing Codex plugin contract without mutating source or cache state.
 *
 * @param {object} options Validation options.
 * @param {(source: string) => unknown} options.parseYaml YAML parser supplied by the Bun entrypoint.
 * @param {string} options.repoRoot Plugin root containing .codex-plugin/plugin.json.
 * @returns {Promise<{checks: string[], failures: string[], ok: boolean}>} Validation report.
 */
export async function validatePlugin({ parseYaml, repoRoot }) {
  if (typeof parseYaml !== 'function') throw new TypeError('parseYaml must be a function.');

  const resolvedRepoRoot = await realpath(resolve(repoRoot));
  const context = {
    checks: [],
    failures: [],
    parseYaml,
    repoRoot: resolvedRepoRoot,
  };
  const pluginJson = await readJson(
    context,
    resolve(context.repoRoot, '.codex-plugin', 'plugin.json'),
    'plugin manifest',
  );
  if (pluginJson === undefined) {
    return { checks: context.checks, failures: context.failures, ok: false };
  }

  const skillsDir = await validateManifest(context, pluginJson);
  if (skillsDir) await validateSkills(context, skillsDir);

  return {
    checks: context.checks,
    failures: context.failures,
    ok: context.failures.length === 0,
  };
}
