import assert from 'node:assert/strict';
import { cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const validatorPath = join(repoRoot, 'bin', 'codexsync.js');
const fixtureEntries = [
  '.codex-plugin',
  '.github',
  'ADVANCED.md',
  'README.md',
  'assets',
  'lib',
  'package.json',
  'scripts',
  'skills',
];

function runValidator(cwd) {
  return spawnSync('bun', [validatorPath, 'validate', '--repo-root', cwd], {
    cwd,
    encoding: 'utf8',
  });
}

async function createFixture() {
  const fixtureRoot = await mkdtemp(join(tmpdir(), 'agentbox-plugin-validation-'));
  for (const entry of fixtureEntries) {
    await cp(join(repoRoot, entry), join(fixtureRoot, entry), { recursive: true });
  }
  return fixtureRoot;
}

describe('lib/plugin-validation', function () {
  this.timeout(10_000);
  const fixtureRoots = [];

  afterEach(async () => {
    await Promise.all(
      fixtureRoots.splice(0).map((fixtureRoot) => rm(fixtureRoot, { recursive: true })),
    );
  });

  it('should validate the current plugin contract', () => {
    const result = runValidator(repoRoot);

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /done agentbox plugin validation passed/);
  });

  it('should reject package and plugin version drift', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    const manifestPath = join(fixtureRoot, '.codex-plugin', 'plugin.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    manifest.version = '9.9.9';
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /package and plugin versions must match/);
  });

  it('should reject starter prompts that reference unknown skills', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    const manifestPath = join(fixtureRoot, '.codex-plugin', 'plugin.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    manifest.interface.defaultPrompt.push('Use $tanaab-agentbox-missing to do something.');
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /starter prompt references unknown skill: tanaab-agentbox-missing/);
  });

  it('should reject missing skill metadata assets', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    await rm(join(fixtureRoot, 'skills', 'agentbox-doctor', 'assets', 'icon-large.png'));

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(
      result.stderr,
      /skills\/agentbox-doctor interface\.icon_large points to a missing path/,
    );
  });

  it('should reject broken skill Markdown links', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    const skillPath = join(fixtureRoot, 'skills', 'agentbox', 'SKILL.md');
    const skill = await readFile(skillPath, 'utf8');
    await writeFile(skillPath, skill.replace('../../ADVANCED.md', '../../MISSING.md'));

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /broken Markdown link in skills\/agentbox\/SKILL\.md/);
  });

  it('should reject workflows that call missing package scripts', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    const packagePath = join(fixtureRoot, 'package.json');
    const packageJson = JSON.parse(await readFile(packagePath, 'utf8'));
    delete packageJson.scripts.build;
    await writeFile(packagePath, `${JSON.stringify(packageJson, null, 2)}\n`);

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /calls missing package script: build/);
  });
});
