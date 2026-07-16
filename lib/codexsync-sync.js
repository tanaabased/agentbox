import { collectCodexsyncEntries, syncCodexsyncEntries } from './codexsync-cache.js';
import { inspectCodexCacheInstallation } from './codexsync-context.js';
import { codexsyncDiffHasChanges, summarizeCodexsyncDiff } from './codexsync-diff.js';
import {
  printCodexsyncDiff,
  printCodexsyncNotInstalled,
  printCodexsyncPaths,
  writeCodexsyncLine,
} from './codexsync-check.js';

export async function runCodexsyncSync(context) {
  const inspection = await inspectCodexCacheInstallation(context);
  printCodexsyncPaths(context);
  if (!inspection.installed) {
    printCodexsyncNotInstalled(context, inspection, context.stderr);
    writeCodexsyncLine(
      context.stderr,
      'error refusing to create a plugin cache; install agentbox through Codex first',
    );
    return { diff: null, inspection, ok: false, status: 'not_installed' };
  }

  const sourceEntries = await collectCodexsyncEntries(context.repoRoot, context.managedPaths);
  const targetEntries = await collectCodexsyncEntries(context.cachePath, context.managedPaths);
  const diff = await syncCodexsyncEntries({
    managedPaths: context.managedPaths,
    sourceEntries,
    sourceRoot: context.repoRoot,
    targetEntries,
    targetRoot: context.cachePath,
  });

  if (codexsyncDiffHasChanges(diff)) {
    writeCodexsyncLine(
      context.stderr,
      `error agentbox plugin cache sync did not converge (${summarizeCodexsyncDiff(diff)})`,
    );
    printCodexsyncDiff(context, diff);
    return { diff, inspection, ok: false, status: 'drifted' };
  }

  writeCodexsyncLine(context.stdout, 'done agentbox plugin cache synced');
  writeCodexsyncLine(
    context.stdout,
    'note restart Codex if refreshed plugin surfaces do not appear immediately',
  );
  return { diff, inspection, ok: true, status: 'current' };
}
