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

case "${bun_version}" in
  1.3.[0-9]*)
    bun_patch="${bun_version#1.3.}"
    case "${bun_patch}" in
      '' | *[!0-9]*) bun_supported="0" ;;
      *) bun_supported="1" ;;
    esac
    ;;
  *) bun_supported="0" ;;
esac

if [ "${bun_supported}" != "1" ]; then
  printf '%s\n' \
    "agentbox plugin runtime unavailable: Bun ${bun_version} at ${bun_path} is unsupported." \
    'This plugin requires Bun >=1.3.0 <1.4.0.' \
    'Install a supported Bun version before retrying.' >&2
  exit 2
fi

exit 0
