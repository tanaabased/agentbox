import {
  chmod,
  cp,
  lstat,
  mkdir,
  readFile,
  readdir,
  readlink,
  rm,
  symlink,
} from 'node:fs/promises';
import { dirname, join, sep } from 'node:path';

import { diffCodexsyncEntries } from './codexsync-diff.js';

const IGNORED_NAMES = new Set(['.DS_Store', '.git', 'node_modules']);

async function collectEntry(rootDir, relativePath, entryMap) {
  const absolutePath = join(rootDir, relativePath);
  let entryStat;
  try {
    entryStat = await lstat(absolutePath);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw error;
  }

  if (entryStat.isSymbolicLink()) {
    entryMap.set(relativePath, { target: await readlink(absolutePath), type: 'symlink' });
    return;
  }
  if (entryStat.isDirectory()) {
    entryMap.set(relativePath, { type: 'dir' });
    const entries = await readdir(absolutePath, { withFileTypes: true });
    for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
      if (IGNORED_NAMES.has(entry.name)) continue;
      await collectEntry(rootDir, join(relativePath, entry.name), entryMap);
    }
    return;
  }
  if (entryStat.isFile()) {
    entryMap.set(relativePath, {
      content: await readFile(absolutePath),
      mode: entryStat.mode & 0o777,
      type: 'file',
    });
  }
}

export async function collectCodexsyncEntries(rootDir, managedPaths, entryMap = new Map()) {
  for (const managedPath of managedPaths) {
    await collectEntry(rootDir, managedPath, entryMap);
  }
  return entryMap;
}

function descendingPathDepth(left, right) {
  const leftDepth = left.split(sep).length;
  const rightDepth = right.split(sep).length;
  return rightDepth - leftDepth || right.length - left.length;
}

function ascendingEntryDepth([leftPath, leftEntry], [rightPath, rightEntry]) {
  const leftDepth = leftPath.split(sep).length;
  const rightDepth = rightPath.split(sep).length;
  if (leftDepth !== rightDepth) return leftDepth - rightDepth;
  if (leftEntry.type === 'dir' && rightEntry.type !== 'dir') return -1;
  if (leftEntry.type !== 'dir' && rightEntry.type === 'dir') return 1;
  return leftPath.localeCompare(rightPath);
}

export async function syncCodexsyncEntries(options) {
  const { managedPaths, sourceEntries, sourceRoot, targetEntries, targetRoot } = options;
  const diff = diffCodexsyncEntries(sourceEntries, targetEntries);

  for (const relativePath of [...diff.extra].sort(descendingPathDepth)) {
    await rm(join(targetRoot, relativePath), { force: true, recursive: true });
  }

  for (const [relativePath, sourceEntry] of [...sourceEntries.entries()].sort(
    ascendingEntryDepth,
  )) {
    const sourcePath = join(sourceRoot, relativePath);
    const targetPath = join(targetRoot, relativePath);
    const targetEntry = targetEntries.get(relativePath);

    if (targetEntry && targetEntry.type !== sourceEntry.type) {
      await rm(targetPath, { force: true, recursive: true });
    }
    if (sourceEntry.type === 'dir') {
      await mkdir(targetPath, { recursive: true });
      continue;
    }

    await mkdir(dirname(targetPath), { recursive: true });
    await rm(targetPath, { force: true, recursive: true });
    if (sourceEntry.type === 'symlink') {
      await symlink(sourceEntry.target, targetPath);
      continue;
    }
    await cp(sourcePath, targetPath, { force: true });
    await chmod(targetPath, sourceEntry.mode);
  }

  const refreshedTargetEntries = await collectCodexsyncEntries(targetRoot, managedPaths);
  return diffCodexsyncEntries(sourceEntries, refreshedTargetEntries);
}
