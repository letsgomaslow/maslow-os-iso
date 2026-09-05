#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT/builder/local-packages.sh"
mapfile -t packages < <(omarchy_local_packages)
[[ ${#packages[@]} == 8 ]]
[[ ${packages[*]} == "omarchy-settings-dev omarchy-dev omarchy-nvim openai-codex-bin claude-code hermes-agent maslow-curated-plugins google-chrome" ]]
OMARCHY_RUNTIME_PACKAGE=omarchy OMARCHY_SETTINGS_PACKAGE=omarchy-settings \
  omarchy_local_packages | grep -qx 'omarchy'
exclusions=()
for package in "${packages[@]}"; do exclusions+=(-e "$package"); done
remaining=$(printf '%s\n' "${packages[@]}" bitwarden bash | grep -Fxv "${exclusions[@]}")
[[ $remaining == $'bitwarden\nbash' ]]
! grep -q -- '--skipchecksums\|--skippgpcheck' "$ROOT/builder/build-omarchy-packages.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/mirror" "$work/metadata"
printf '%s\n' \
  'pkgname = fixture' \
  'depend = nodejs>=22' \
  'depend = glibc' \
  'depend = omarchy-settings-dev' \
  'depend = maslow-curated-plugins' \
  'depend = google-chrome' > "$work/metadata/.PKGINFO"
for package in "${packages[@]}"; do
  bsdtar -cf "$work/mirror/$package-1-1-any.pkg.tar.zst" -C "$work/metadata" .PKGINFO
done
dependencies=$(omarchy_local_dependencies "$work/mirror")
grep -qx 'nodejs>=22' <<< "$dependencies"
grep -qx glibc <<< "$dependencies"
! grep -q omarchy-settings-dev <<< "$dependencies"
! grep -q maslow-curated-plugins <<< "$dependencies"
! grep -q google-chrome <<< "$dependencies"
rm "$work/mirror/hermes-agent-1-1-any.pkg.tar.zst"
if omarchy_local_dependencies "$work/mirror" >/dev/null 2>&1; then
  echo 'Missing local dependency metadata must fail' >&2
  exit 1
fi
printf 'Local package selection and integrity checks passed.\n'
