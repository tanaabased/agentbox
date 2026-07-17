import assert from 'node:assert/strict';
import { cp, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const validatorPath = join(repoRoot, 'bin', 'codexsync.js');
const fixtureEntries = ['.codex-plugin', 'assets', 'skills'];

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

  it('should validate a plugin without repository tooling or Tanaab skill conventions', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    const skillDir = join(fixtureRoot, 'skills', 'agentbox');
    await writeFile(
      join(skillDir, 'SKILL.md'),
      '---\nname: minimal-skill\ndescription: Minimal skill.\n---\n\n# Minimal Skill\n',
    );
    await rm(join(skillDir, 'agents'), { recursive: true });

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 0, result.stderr);
  });

  it('should reject an invalid plugin manifest', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    await writeFile(join(fixtureRoot, '.codex-plugin', 'plugin.json'), '{');

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /plugin manifest is not valid JSON/);
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

  it('should reject skills without required frontmatter fields', async () => {
    const fixtureRoot = await createFixture();
    fixtureRoots.push(fixtureRoot);
    const skillPath = join(fixtureRoot, 'skills', 'agentbox', 'SKILL.md');
    await writeFile(skillPath, '---\nname: incomplete\n---\n\n# Incomplete\n');

    const result = runValidator(fixtureRoot);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /frontmatter\.description must be a non-empty string/);
  });
});
