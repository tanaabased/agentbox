const MAX_DIFF_PREVIEW = 5;

function contentEquals(leftContent, rightContent) {
  if (leftContent?.equals && rightContent instanceof Uint8Array) {
    return leftContent.equals(rightContent);
  }
  if (rightContent?.equals && leftContent instanceof Uint8Array) {
    return rightContent.equals(leftContent);
  }
  return Object.is(leftContent, rightContent);
}

export function diffCodexsyncEntries(sourceEntries, targetEntries) {
  const changed = [];
  const extra = [];
  const missing = [];

  for (const [relativePath, sourceEntry] of sourceEntries) {
    const targetEntry = targetEntries.get(relativePath);
    if (!targetEntry) {
      missing.push(relativePath);
      continue;
    }
    if (sourceEntry.type !== targetEntry.type) {
      changed.push(relativePath);
      continue;
    }
    if (
      sourceEntry.type === 'file' &&
      (sourceEntry.mode !== targetEntry.mode ||
        !contentEquals(sourceEntry.content, targetEntry.content))
    ) {
      changed.push(relativePath);
      continue;
    }
    if (sourceEntry.type === 'symlink' && sourceEntry.target !== targetEntry.target) {
      changed.push(relativePath);
    }
  }

  for (const relativePath of targetEntries.keys()) {
    if (!sourceEntries.has(relativePath)) extra.push(relativePath);
  }

  for (const paths of [changed, extra, missing]) {
    paths.sort((left, right) => left.localeCompare(right));
  }
  return { changed, extra, missing };
}

export function codexsyncDiffHasChanges(diff) {
  return diff.changed.length > 0 || diff.missing.length > 0 || diff.extra.length > 0;
}

export function previewCodexsyncPaths(paths, maxPreview = MAX_DIFF_PREVIEW) {
  if (paths.length <= maxPreview) return paths;
  return [...paths.slice(0, maxPreview), `... ${paths.length - maxPreview} more`];
}

export function summarizeCodexsyncDiff(diff) {
  const parts = [];
  if (diff.changed.length > 0) parts.push(`changed ${diff.changed.length}`);
  if (diff.missing.length > 0) parts.push(`missing ${diff.missing.length}`);
  if (diff.extra.length > 0) parts.push(`extra ${diff.extra.length}`);
  return parts.length > 0 ? parts.join(', ') : 'in sync';
}
