#!/bin/bash

set -euo pipefail

if (( $# < 2 )); then
  echo "Usage: check-package-file-overlap.sh <package> <package> [...]" >&2
  exit 2
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
inventory="$work_dir/package-file-owners.tsv"
: >"$inventory"

for package_file in "$@"; do
  if [[ ! -f $package_file ]]; then
    echo "ERROR: package file not found: $package_file" >&2
    exit 2
  fi

  package_name=$(bsdtar -xOf "$package_file" .PKGINFO 2>/dev/null |
    sed -n 's/^pkgname = //p' | head -n 1)
  if [[ -z $package_name ]]; then
    echo "ERROR: package has no readable pkgname: $package_file" >&2
    exit 2
  fi

  while IFS= read -r path; do
    path=${path#./}
    [[ -n $path && $path != .* && $path != */ ]] || continue
    printf '%s\t%s\n' "$path" "$package_name" >>"$inventory"
  done < <(bsdtar -tf "$package_file")
done

duplicate_paths=$(cut -f1 "$inventory" | LC_ALL=C sort | uniq -d)
if [[ -n $duplicate_paths ]]; then
  echo "ERROR: selected Omarchy packages contain conflicting file ownership:" >&2
  while IFS= read -r path; do
    owners=$(awk -F '\t' -v path="$path" '$1 == path { print $2 }' "$inventory" |
      LC_ALL=C sort -u | paste -sd, - | sed 's/,/, /g')
    printf '  %s: %s\n' "$path" "$owners" >&2
  done <<<"$duplicate_paths"
  exit 1
fi

echo "Selected Omarchy packages have no conflicting file ownership."
