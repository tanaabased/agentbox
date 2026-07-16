#!/bin/sh

bun_path="$(command -v bun 2>/dev/null)" || bun_path=""

if [ -z "${bun_path}" ]; then
  printf '%s\n' \
    'agentbox plugin runtime unavailable: Bun was not found on PATH.' \
    'Bun is required to run this skill.' \
    'On a bare Mac, use the hosted agentbox Bash bootstrap.' \
    'On an existing agentbox host, repair the core Brewfile packages before retrying.' >&2
  exit 2
fi

if ! bun_version="$("${bun_path}" --version 2>/dev/null)" || [ -z "${bun_version}" ]; then
  printf '%s\n' \
    "agentbox plugin runtime unavailable: Bun was found at ${bun_path} but could not run." \
    'Repair the Bun installation or PATH entry before retrying.' >&2
  exit 2
fi

exit 0
