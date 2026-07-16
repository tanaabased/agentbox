import { readFile, readdir, realpath, stat } from 'node:fs/promises';
import { isAbsolute, relative, resolve, sep } from 'node:path';

const ALLOWED_SKILL_TYPES = new Set(['coding', 'generic', 'integration', 'meta', 'workflow']);
const COMMON_SKILL_SECTIONS = [
  'Overview',
  'When to Use',
  'When Not to Use',
  'Workflow',
  'Bundled Resources',
  'Validation',
];
const WORKFLOW_SKILL_SECTIONS = [
  'Overview',
  'When to Use',
  'When Not to Use',
  'Preconditions',
  'Workflow',
  'Checkpoints',
  'Completion Criteria',
  'Bundled Resources',
  'Validation',
];
const PACKAGE_SCRIPT_PATTERN = /\b(?:bun|npm|pnpm|yarn)\s+run\s+([a-zA-Z0-9:_-]+)/g;
const SKILL_REFERENCE_PATTERN = /\$([a-z][a-z0-9]*(?:-[a-z0-9]+)*)/g;

function addCheck(context, message) {
  context.checks.push(message);
}

function fail(context, message) {
  context.failures.push(message);
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
    return null;
  }
}

async function readYaml(context, targetPath, label) {
  let content;
  try {
    content = await readFile(targetPath, 'utf8');
  } catch (error) {
    fail(context, `${label} could not be read: ${error.message}`);
    return null;
  }

  try {
    return context.parseYaml(content);
  } catch (error) {
    fail(context, `${label} is not valid YAML: ${error.message}`);
    return null;
  }
}

async function collectFiles(targetPath, predicate, files = []) {
  if (!(await pathExists(targetPath))) return files;

  const targetStat = await stat(targetPath);
  if (targetStat.isFile()) {
    if (predicate(targetPath)) files.push(targetPath);
    return files;
  }

  if (!targetStat.isDirectory()) return files;

  const entries = await readdir(targetPath, { withFileTypes: true });
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (entry.name === '.git' || entry.name === 'node_modules') continue;
    await collectFiles(resolve(targetPath, entry.name), predicate, files);
  }

  return files;
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
    return context.parseYaml(lines.slice(1, closingIndex).join('\n'));
  } catch (error) {
    fail(context, `${label} frontmatter is not valid YAML: ${error.message}`);
    return null;
  }
}

function validateSkillSections(context, content, skillLabel, skillType) {
  const sections = [...content.matchAll(/^## ([^\n]+)$/gm)].map((match) => match[1].trim());
  const requiredSections =
    skillType === 'workflow' ? WORKFLOW_SKILL_SECTIONS : COMMON_SKILL_SECTIONS;

  let previousIndex = -1;
  for (const section of requiredSections) {
    const sectionIndex = sections.indexOf(section);
    if (sectionIndex === -1) {
      fail(context, `${skillLabel} is missing required section: ${section}`);
      continue;
    }
    if (sectionIndex < previousIndex) {
      fail(context, `${skillLabel} section is out of canonical order: ${section}`);
    }
    previousIndex = sectionIndex;
  }
}

function isExternalMarkdownTarget(target) {
  return (
    target.startsWith('#') ||
    /^[a-z][a-z0-9+.-]*:/i.test(target) ||
    target.startsWith('{{') ||
    target.includes('{{') ||
    target.includes('}}')
  );
}

function normalizeMarkdownTarget(rawTarget) {
  const withoutTitle = String(rawTarget ?? '')
    .trim()
    .split(/\s+["'][^"']*["']$/)[0];
  const withoutAngles =
    withoutTitle.startsWith('<') && withoutTitle.endsWith('>')
      ? withoutTitle.slice(1, -1)
      : withoutTitle;
  return withoutAngles.split('#', 1)[0];
}

async function validateMarkdownLinks(context, markdownFiles) {
  const linkPattern = /(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)/g;

  for (const filePath of markdownFiles) {
    const content = await readFile(filePath, 'utf8');
    for (const match of content.matchAll(linkPattern)) {
      const target = normalizeMarkdownTarget(match[1]);
      if (!target || isExternalMarkdownTarget(target)) continue;

      const targetPath = resolve(filePath, '..', target);
      const fileLabel = relative(context.repoRoot, filePath);
      if (!isInside(context.repoRoot, targetPath) || !(await pathExists(targetPath))) {
        fail(context, `broken Markdown link in ${fileLabel}: ${match[1]}`);
      }
    }
  }
}

async function validateOpenAiMetadata(context, skillDir, skillId, skillLabel) {
  const metadataPath = resolve(skillDir, 'agents', 'openai.yaml');
  const metadata = await readYaml(context, metadataPath, `${skillLabel} agents/openai.yaml`);
  if (!metadata) return;

  const pluginInterface = metadata.interface;
  if (!pluginInterface || typeof pluginInterface !== 'object' || Array.isArray(pluginInterface)) {
    fail(context, `${skillLabel} agents/openai.yaml must contain an interface object.`);
    return;
  }

  for (const field of ['display_name', 'short_description', 'default_prompt', 'brand_color']) {
    requireString(context, pluginInterface[field], `${skillLabel} interface.${field}`);
  }

  if (
    typeof pluginInterface.short_description === 'string' &&
    !pluginInterface.short_description.startsWith('Tanaab-based')
  ) {
    fail(context, `${skillLabel} interface.short_description must start with 'Tanaab-based'.`);
  }
  if (pluginInterface.brand_color !== '#00c88a') {
    fail(context, `${skillLabel} interface.brand_color must equal #00c88a.`);
  }
  if (
    typeof pluginInterface.default_prompt === 'string' &&
    !pluginInterface.default_prompt.includes(`$${skillId}`)
  ) {
    fail(context, `${skillLabel} interface.default_prompt must reference $${skillId}.`);
  }

  await checkLocalPath(context, {
    basePath: skillDir,
    label: `${skillLabel} interface.icon_small`,
    rawPath: pluginInterface.icon_small,
    expectedType: 'file',
  });
  await checkLocalPath(context, {
    basePath: skillDir,
    label: `${skillLabel} interface.icon_large`,
    rawPath: pluginInterface.icon_large,
    expectedType: 'file',
  });
}

async function validateSkills(context, skillsDir) {
  addCheck(context, 'skill contracts');
  const skillIds = new Set();
  const markdownFiles = [];
  const entries = await readdir(skillsDir, { withFileTypes: true });
  const skillDirs = entries
    .filter((entry) => entry.isDirectory())
    .sort((left, right) => left.name.localeCompare(right.name));

  if (skillDirs.length === 0)
    fail(context, 'plugin skills directory must contain at least one skill.');

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

    const expectedSkillId = `tanaab-${entry.name}`;
    if (frontmatter.name !== expectedSkillId) {
      fail(context, `${skillLabel} frontmatter.name must equal ${expectedSkillId}.`);
    }
    if (skillIds.has(frontmatter.name)) {
      fail(context, `duplicate skill id: ${frontmatter.name}`);
    } else if (typeof frontmatter.name === 'string') {
      skillIds.add(frontmatter.name);
    }

    requireString(context, frontmatter.description, `${skillLabel} frontmatter.description`);
    if (
      typeof frontmatter.description === 'string' &&
      !frontmatter.description.startsWith('Tanaab-based')
    ) {
      fail(context, `${skillLabel} frontmatter.description must start with 'Tanaab-based'.`);
    }
    if (frontmatter.license !== 'MIT') {
      fail(context, `${skillLabel} frontmatter.license must equal MIT.`);
    }

    const skillMetadata = frontmatter.metadata;
    if (!skillMetadata || typeof skillMetadata !== 'object' || Array.isArray(skillMetadata)) {
      fail(context, `${skillLabel} frontmatter.metadata must be an object.`);
      continue;
    }
    if (skillMetadata.owner !== 'tanaab') {
      fail(context, `${skillLabel} frontmatter.metadata.owner must equal tanaab.`);
    }
    if (!ALLOWED_SKILL_TYPES.has(skillMetadata.type)) {
      fail(
        context,
        `${skillLabel} frontmatter.metadata.type is unsupported: ${skillMetadata.type}`,
      );
    }
    if (!Array.isArray(skillMetadata.tags)) {
      fail(context, `${skillLabel} frontmatter.metadata.tags must be an array.`);
    } else {
      for (const requiredTag of ['tanaab', skillMetadata.type]) {
        if (!skillMetadata.tags.includes(requiredTag)) {
          fail(context, `${skillLabel} frontmatter.metadata.tags must include ${requiredTag}.`);
        }
      }
      if (skillMetadata.tags.length < 3) {
        fail(context, `${skillLabel} frontmatter.metadata.tags must include a category tag.`);
      }
    }

    validateSkillSections(context, content, skillLabel, skillMetadata.type);
    await validateOpenAiMetadata(context, skillDir, frontmatter.name, skillLabel);
    await collectFiles(skillDir, (filePath) => filePath.endsWith('.md'), markdownFiles);
  }

  addCheck(context, 'skill Markdown links');
  await validateMarkdownLinks(context, markdownFiles);
  return skillIds;
}

function collectDefaultPrompts(context, pluginInterface) {
  const rawPrompts = pluginInterface.defaultPrompt;
  const prompts = Array.isArray(rawPrompts) ? rawPrompts : [rawPrompts];
  const normalizedPrompts = prompts
    .filter((prompt) => typeof prompt === 'string')
    .map((prompt) => prompt.trim())
    .filter(Boolean);

  if (normalizedPrompts.length === 0) {
    fail(context, 'plugin interface.defaultPrompt must contain at least one prompt.');
  }
  if (!Array.isArray(rawPrompts) && typeof rawPrompts !== 'string') {
    fail(context, 'plugin interface.defaultPrompt must be a string or an array of strings.');
  }
  if (Array.isArray(rawPrompts) && rawPrompts.some((prompt) => typeof prompt !== 'string')) {
    fail(context, 'plugin interface.defaultPrompt entries must be strings.');
  }

  return normalizedPrompts;
}

function validateStarterPrompts(context, pluginInterface, skillIds) {
  addCheck(context, 'plugin starter prompts');
  const prompts = collectDefaultPrompts(context, pluginInterface);
  const referencedSkillIds = new Set();

  for (const prompt of prompts) {
    for (const match of prompt.matchAll(SKILL_REFERENCE_PATTERN)) {
      referencedSkillIds.add(match[1]);
    }
  }

  for (const skillId of referencedSkillIds) {
    if (!skillIds.has(skillId))
      fail(context, `plugin starter prompt references unknown skill: ${skillId}`);
  }
  if (![...referencedSkillIds].some((skillId) => skillIds.has(skillId))) {
    fail(context, 'plugin starter prompts must reference at least one installed skill.');
  }
}

async function validateOptionalMcp(context, pluginJson) {
  if (pluginJson.mcpServers === undefined) return;

  const mcpPath = await checkLocalPath(context, {
    basePath: context.repoRoot,
    label: 'plugin manifest mcpServers',
    rawPath: pluginJson.mcpServers,
    expectedType: 'file',
  });
  if (!mcpPath) return;

  const mcpJson = await readJson(context, mcpPath, 'plugin MCP config');
  if (
    mcpJson &&
    (!mcpJson.mcpServers ||
      typeof mcpJson.mcpServers !== 'object' ||
      Array.isArray(mcpJson.mcpServers))
  ) {
    fail(context, 'plugin MCP config must contain an mcpServers object.');
  }
}

async function validateManifest(context, packageJson, pluginJson) {
  addCheck(context, 'package and plugin metadata');
  for (const field of ['name', 'version', 'description', 'license', 'repository']) {
    requireString(context, pluginJson[field], `plugin manifest ${field}`);
  }
  if (packageJson.version !== pluginJson.version) {
    fail(
      context,
      `package and plugin versions must match: ${packageJson.version} != ${pluginJson.version}`,
    );
  }

  const pluginInterface = pluginJson.interface;
  if (!pluginInterface || typeof pluginInterface !== 'object' || Array.isArray(pluginInterface)) {
    fail(context, 'plugin manifest interface must be an object.');
    return { pluginInterface: {}, skillsDir: null };
  }
  for (const field of [
    'displayName',
    'shortDescription',
    'longDescription',
    'developerName',
    'category',
    'brandColor',
  ]) {
    requireString(context, pluginInterface[field], `plugin interface.${field}`);
  }

  addCheck(context, 'plugin manifest paths');
  const skillsDir = await checkLocalPath(context, {
    basePath: context.repoRoot,
    label: 'plugin manifest skills',
    rawPath: pluginJson.skills,
    expectedType: 'directory',
  });
  await checkLocalPath(context, {
    basePath: context.repoRoot,
    label: 'plugin interface.composerIcon',
    rawPath: pluginInterface.composerIcon,
    expectedType: 'file',
  });
  await checkLocalPath(context, {
    basePath: context.repoRoot,
    label: 'plugin interface.logo',
    rawPath: pluginInterface.logo,
    expectedType: 'file',
  });
  await checkLocalPath(context, {
    basePath: context.repoRoot,
    label: 'plugin manifest apps',
    rawPath: pluginJson.apps,
    required: false,
  });
  await validateOptionalMcp(context, pluginJson);

  if (Array.isArray(pluginInterface.screenshots)) {
    for (const [index, screenshotPath] of pluginInterface.screenshots.entries()) {
      await checkLocalPath(context, {
        basePath: context.repoRoot,
        label: `plugin interface.screenshots[${index}]`,
        rawPath: screenshotPath,
        expectedType: 'file',
      });
    }
  }

  return { pluginInterface, skillsDir };
}

async function validateWorkflowScripts(context, packageJson) {
  addCheck(context, 'workflow package script references');
  const workflowDir = resolve(context.repoRoot, '.github', 'workflows');
  const workflowFiles = await collectFiles(workflowDir, (filePath) => /\.ya?ml$/.test(filePath));
  const packageScripts = new Set(Object.keys(packageJson.scripts ?? {}));

  for (const workflowFile of workflowFiles) {
    const content = await readFile(workflowFile, 'utf8');
    for (const match of content.matchAll(PACKAGE_SCRIPT_PATTERN)) {
      if (!packageScripts.has(match[1])) {
        fail(
          context,
          `workflow ${relative(context.repoRoot, workflowFile)} calls missing package script: ${match[1]}`,
        );
      }
    }
  }
}

/**
 * Validates the repository-owned Codex plugin contract without mutating source or cache state.
 *
 * @param {object} options Validation options.
 * @param {(source: string) => unknown} options.parseYaml YAML parser supplied by the Bun entrypoint.
 * @param {string} options.repoRoot Repository root containing package and plugin manifests.
 * @returns {Promise<{checks: string[], failures: string[], ok: boolean}>} Validation report.
 */
export async function validatePlugin({ parseYaml, repoRoot }) {
  if (typeof parseYaml !== 'function') throw new TypeError('parseYaml must be a function.');

  const context = {
    checks: [],
    failures: [],
    parseYaml,
    repoRoot: resolve(repoRoot),
  };

  const packageJson = await readJson(
    context,
    resolve(context.repoRoot, 'package.json'),
    'package.json',
  );
  const pluginJson = await readJson(
    context,
    resolve(context.repoRoot, '.codex-plugin', 'plugin.json'),
    'plugin manifest',
  );
  if (!packageJson || !pluginJson) {
    return { checks: context.checks, failures: context.failures, ok: false };
  }

  const { pluginInterface, skillsDir } = await validateManifest(context, packageJson, pluginJson);
  const skillIds = skillsDir ? await validateSkills(context, skillsDir) : new Set();
  validateStarterPrompts(context, pluginInterface, skillIds);
  await validateWorkflowScripts(context, packageJson);

  return {
    checks: context.checks,
    failures: context.failures,
    ok: context.failures.length === 0,
  };
}
