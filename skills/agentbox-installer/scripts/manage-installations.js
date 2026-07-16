#!/usr/bin/env bun

import {
  installStableAgentbox,
  registerSourceAgentbox,
  resolveAgentboxExecutable,
  statusAgentboxInstallations,
  useAgentboxInstallation,
} from './manage-installations-lib.js';

function usage() {
  return `Usage: manage-installations.js <command> [options]

Commands:
  status
  install stable [--install-root PATH] [--bin-dir PATH]
  update stable [--install-root PATH] [--bin-dir PATH]
  register source PATH [--bin-dir PATH]
  use <stable|source> [--bin-dir PATH]
  resolve [stable|source]

Options:
  --install-root PATH  Store release payloads under this directory.
  --bin-dir PATH       Place the agentbox command symlink in this directory.
  --help               Show this help.
`;
}

function parseOptions(args, allowed) {
  const positionals = [];
  const options = {};

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (!argument.startsWith('--')) {
      positionals.push(argument);
      continue;
    }
    if (!allowed.includes(argument)) throw new Error(`unsupported option: ${argument}`);
    const value = args[index + 1];
    if (!value) throw new Error(`${argument} requires a path`);
    options[argument === '--bin-dir' ? 'binDir' : 'installRoot'] = value;
    index += 1;
  }

  return { options, positionals };
}

function printJson(value, stream = process.stdout) {
  stream.write(`${JSON.stringify(value, null, 2)}\n`);
}

async function main(argv) {
  if (argv.length === 0 || argv[0] === '--help') {
    process.stdout.write(usage());
    return 0;
  }

  const [command, ...rest] = argv;
  if (command === 'status') {
    if (rest.length > 0) throw new Error('status does not accept arguments');
    printJson(await statusAgentboxInstallations());
    return 0;
  }
  if (command === 'install' || command === 'update') {
    const { options, positionals } = parseOptions(rest, ['--install-root', '--bin-dir']);
    if (positionals.length !== 1 || positionals[0] !== 'stable') {
      throw new Error(`${command} requires stable`);
    }
    printJson(await installStableAgentbox(options));
    return 0;
  }
  if (command === 'register') {
    const { options, positionals } = parseOptions(rest, ['--bin-dir']);
    if (positionals.length !== 2 || positionals[0] !== 'source') {
      throw new Error('register requires source PATH');
    }
    printJson(await registerSourceAgentbox(positionals[1], options));
    return 0;
  }
  if (command === 'use') {
    const { options, positionals } = parseOptions(rest, ['--bin-dir']);
    if (positionals.length !== 1 || !['stable', 'source'].includes(positionals[0])) {
      throw new Error('use requires stable or source');
    }
    printJson(await useAgentboxInstallation(positionals[0], options));
    return 0;
  }
  if (command === 'resolve') {
    if (rest.length > 1 || (rest[0] && !['stable', 'source'].includes(rest[0]))) {
      throw new Error('resolve accepts only stable or source');
    }
    printJson(await resolveAgentboxExecutable(rest[0]));
    return 0;
  }

  throw new Error(`unknown command: ${command}`);
}

try {
  process.exitCode = await main(process.argv.slice(2));
} catch (error) {
  printJson(
    {
      status: 'error',
      error: {
        code: error.code || 'usage_error',
        detail: error.message,
      },
    },
    process.stderr,
  );
  process.exitCode = 2;
}
