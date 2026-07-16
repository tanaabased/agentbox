import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const runtimeCheck = resolve('scripts/check-plugin-runtime.sh');

describe('scripts/check-plugin-runtime.sh', function () {
  let root;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), 'agentbox-plugin-runtime-'));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it('should explain when Bun is not on PATH', () => {
    const result = spawnSync(runtimeCheck, [], {
      encoding: 'utf8',
      env: { PATH: root },
    });

    assert.equal(result.status, 2);
    assert.match(result.stderr, /Bun was not found on PATH/);
    assert.match(result.stderr, /hosted agentbox Bash bootstrap/);
  });

  it('should pass silently when Bun is available', async () => {
    const bunPath = join(root, 'bin', 'bun');
    await mkdir(join(root, 'bin'), { recursive: true });
    await writeFile(bunPath, '#!/bin/sh\nprintf "1.3.4\\n"\n');
    await chmod(bunPath, 0o755);

    const result = spawnSync(runtimeCheck, [], {
      encoding: 'utf8',
      env: { PATH: join(root, 'bin') },
    });

    assert.equal(result.status, 0);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, '');
  });

  it('should explain when the discovered Bun executable is broken', async () => {
    const bunPath = join(root, 'bin', 'bun');
    await mkdir(join(root, 'bin'), { recursive: true });
    await writeFile(bunPath, '#!/bin/sh\nexit 1\n');
    await chmod(bunPath, 0o755);

    const result = spawnSync(runtimeCheck, [], {
      encoding: 'utf8',
      env: { PATH: join(root, 'bin') },
    });

    assert.equal(result.status, 2);
    assert.match(result.stderr, /was found at .* but could not run/);
  });
});
