#!/usr/bin/env bun

import { validatePlugin } from '../lib/plugin-validation.js';

const parseYaml = globalThis.Bun?.YAML?.parse;

if (typeof parseYaml !== 'function') {
  process.stderr.write('error agentbox plugin validation requires Bun with YAML support.\n');
  process.exit(1);
}

try {
  const result = await validatePlugin({ parseYaml, repoRoot: process.cwd() });
  for (const check of result.checks) process.stdout.write(`check ${check}\n`);

  if (!result.ok) {
    process.stderr.write('\nagentbox plugin validation failed:\n');
    for (const failure of result.failures) process.stderr.write(`- ${failure}\n`);
    process.exitCode = 1;
  } else {
    process.stdout.write('done agentbox plugin validation passed\n');
  }
} catch (error) {
  process.stderr.write(`error agentbox plugin validation failed unexpectedly: ${error.message}\n`);
  process.exitCode = 1;
}
