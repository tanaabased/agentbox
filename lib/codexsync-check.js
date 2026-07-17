import { collectCodexsyncEntries } from './codexsync-cache.js';
import { inspectCodexCacheInstallation } from './codexsync-context.js';
import {
  codexsyncDiffHasChanges,
  diffCodexsyncEntries,
  previewCodexsyncPaths,
  summarizeCodexsyncDiff,
} from './codexsync-diff.js';

export function writeCodexsyncLine(stream, message = '') {
  stream.write(`${message}\n`);
}

export function printCodexsyncPaths(context) {
  writeCodexsyncLine(context.stdout, `repo: ${context.repoRoot}`);
  writeCodexsyncLine(context.stdout, `cache: ${context.cachePath}`);
}

export function printCodexsyncDiff(context, diff) {
  for (const [label, paths] of [
    ['changed', diff.changed],
    ['missing', diff.missing],
    ['extra', diff.extra],
  ]) {
    const preview = previewCodexsyncPaths(paths);
    if (preview.length === 0) continue;
    writeCodexsyncLine(context.stderr, `${label}:`);
    for (const entry of preview) writeCodexsyncLine(context.stderr, `  ${entry}`);
  }
}

export function printCodexsyncNotInstalled(context, inspection, stream = context.stdout) {
  writeCodexsyncLine(
    stream,
    `note agentbox plugin cache is not installed for version ${inspection.version}`,
  );
  if (inspection.cachePresent && inspection.installationIssue) {
    writeCodexsyncLine(stream, `note ${inspection.installationIssue}`);
  }
  const otherVersions = inspection.installedVersions.filter(
    (version) => version !== inspection.version,
  );
  if (otherVersions.length > 0) {
    writeCodexsyncLine(stream, `note other cache versions found: ${otherVersions.join(', ')}`);
  }
}

export async function runCodexsyncCheck(context) {
  const inspection = await inspectCodexCacheInstallation(context);
  printCodexsyncPaths(context);
  if (!inspection.installed) {
    printCodexsyncNotInstalled(context, inspection);
    return { diff: null, inspection, ok: true, status: 'not_installed' };
  }

  const sourceEntries = await collectCodexsyncEntries(context.repoRoot, context.managedPaths);
  const targetEntries = await collectCodexsyncEntries(context.cachePath, context.managedPaths);
  const diff = diffCodexsyncEntries(sourceEntries, targetEntries);
  if (codexsyncDiffHasChanges(diff)) {
    writeCodexsyncLine(
      context.stderr,
      `error agentbox plugin cache drift detected (${summarizeCodexsyncDiff(diff)})`,
    );
    printCodexsyncDiff(context, diff);
    return { diff, inspection, ok: false, status: 'drifted' };
  }

  writeCodexsyncLine(context.stdout, 'done agentbox plugin cache matches source');
  return { diff, inspection, ok: true, status: 'current' };
}
