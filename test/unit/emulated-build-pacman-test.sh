#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
launcher="$ROOT/bin/omarchy-iso-make"
builder="$ROOT/builder/build-iso.sh"

grep -Fq '[[ $(uname -m) != "x86_64" ]]' "$launcher"
grep -Fq 'DOCKER_ARGS+=(-e "OMARCHY_BUILD_CPU_EMULATED=1")' "$launcher"
grep -Fq '[[ ${OMARCHY_BUILD_CPU_EMULATED:-} == "1" ]]' "$builder"
grep -Fq "sed -i 's/^DownloadUser[[:space:]]*=/# DownloadUser =/' /etc/pacman.conf" "$builder"

if grep -Eq -- '--skipchecksums|--skippgpcheck|SigLevel[[:space:]]*=[[:space:]]*Never' "$launcher" "$builder"; then
  echo 'Emulated-build compatibility must not bypass package verification.' >&2
  exit 1
fi

printf 'Emulated x86 build pacman compatibility checks passed.\n'
