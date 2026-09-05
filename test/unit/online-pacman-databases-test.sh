#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
STAGER="$ROOT/builder/stage-online-pacman-databases.sh"
BUILD_ISO="$ROOT/builder/build-iso.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The staged databases must come from the exact dbpath used both to download
# and resolve the frozen offline package set. A separate synchronization would
# allow the database snapshot and cached package closure to drift apart.
grep -Fq -- '--dbpath /tmp/offlinedb --needed' "$BUILD_ISO"
grep -A2 -F 'bash /builder/stage-online-pacman-databases.sh \' "$BUILD_ISO" |
  grep -Fq '  /tmp/offlinedb \'
grep -Fq -- '--dbpath /tmp/offlinedb -S --print' "$BUILD_ISO"

mkdir -p "$work/source/sync"
for repository in core extra multilib omarchy; do
  mkdir -p "$work/archive/$repository-package"
  printf '%%NAME%%\n%s-package\n' "$repository" >"$work/archive/$repository-package/desc"
  bsdtar -cf "$work/source/sync/$repository.db" -C "$work/archive" "$repository-package"
done

bash "$STAGER" "$work/source" "$work/target"
for repository in core extra multilib omarchy; do
  cmp "$work/source/sync/$repository.db" "$work/target/$repository.db"
done

rm -rf "$work/target"
: >"$work/source/sync/multilib.db"
if bash "$STAGER" "$work/source" "$work/target" >"$work/out" 2>"$work/err"; then
  echo "Empty repository database must fail staging" >&2
  exit 1
fi
grep -Fq "$work/source/sync/multilib.db" "$work/err"
[[ ! -e $work/target ]] || {
  echo "Failed validation must not leave a partially staged database set" >&2
  exit 1
}

bsdtar -cf "$work/source/sync/multilib.db" --files-from /dev/null
if bash "$STAGER" "$work/source" "$work/target" >"$work/out" 2>"$work/err"; then
  echo "Repository database archive without entries must fail staging" >&2
  exit 1
fi
grep -Fq "archive has no entries: $work/source/sync/multilib.db" "$work/err"
[[ ! -e $work/target ]] || {
  echo "Empty archive validation must not leave a partially staged database set" >&2
  exit 1
}

printf 'not a tar archive\n' >"$work/source/sync/multilib.db"
if bash "$STAGER" "$work/source" "$work/target" >"$work/out" 2>"$work/err"; then
  echo "Malformed repository database must fail staging" >&2
  exit 1
fi
grep -Fq "not a readable archive: $work/source/sync/multilib.db" "$work/err"
[[ ! -e $work/target ]] || {
  echo "Malformed archive validation must not leave a partially staged database set" >&2
  exit 1
}

printf 'Online pacman database staging checks passed.\n'
