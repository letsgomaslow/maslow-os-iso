#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
CHECKER="$ROOT/builder/check-package-file-overlap.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

make_package() {
  local package_name=$1 package_root=$2 archive=$3 owned_path=$4
  mkdir -p "$package_root/$(dirname "$owned_path")"
  printf 'pkgname = %s\npkgver = 1-1\n' "$package_name" >"$package_root/.PKGINFO"
  printf '%s\n' "$package_name" >"$package_root/$owned_path"
  bsdtar -cf "$archive" -C "$package_root" .PKGINFO usr
}

make_package runtime "$TEST_ROOT/runtime" "$TEST_ROOT/runtime.pkg.tar" \
  usr/share/omarchy/maslow-version
make_package settings "$TEST_ROOT/settings" "$TEST_ROOT/settings.pkg.tar" \
  usr/share/maslow-os/product.json

bash "$CHECKER" "$TEST_ROOT/runtime.pkg.tar" "$TEST_ROOT/settings.pkg.tar" >/dev/null ||
  fail "distinct package files were reported as an overlap"

make_package conflicting-settings "$TEST_ROOT/conflicting-settings" \
  "$TEST_ROOT/conflicting-settings.pkg.tar" usr/share/omarchy/maslow-version

set +e
output=$(bash "$CHECKER" "$TEST_ROOT/runtime.pkg.tar" \
  "$TEST_ROOT/conflicting-settings.pkg.tar" 2>&1)
status=$?
set -e

(( status == 1 )) || fail "overlapping package files returned status $status"
[[ $output == *"usr/share/omarchy/maslow-version"* ]] ||
  fail "overlap output omitted the conflicting path"
[[ $output == *"runtime"* && $output == *"conflicting-settings"* ]] ||
  fail "overlap output omitted package owners"

printf 'Package file overlap checks passed.\n'
