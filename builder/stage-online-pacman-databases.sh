#!/bin/bash

set -euo pipefail

source_dbpath="${1:-}"
target_dir="${2:-}"

if [[ -z $source_dbpath || -z $target_dir ]]; then
  echo "Usage: stage-online-pacman-databases.sh <source-dbpath> <target-dir>" >&2
  exit 2
fi

repositories=(core extra multilib omarchy)
sources=()

# Validate the complete set before copying anything. A partially seeded target
# would merely trade the fresh-install failure for repository-specific warnings.
for repository in "${repositories[@]}"; do
  source_db="$source_dbpath/sync/$repository.db"
  if [[ ! -s $source_db ]]; then
    echo "ERROR: online pacman database is missing or empty: $source_db" >&2
    exit 1
  fi
  if ! database_entries=$(bsdtar -tf "$source_db"); then
    echo "ERROR: online pacman database is not a readable archive: $source_db" >&2
    exit 1
  fi
  if [[ -z $database_entries ]]; then
    echo "ERROR: online pacman database archive has no entries: $source_db" >&2
    exit 1
  fi
  sources+=("$source_db")
done

mkdir -p "$target_dir"
for index in "${!repositories[@]}"; do
  install -m 0644 "${sources[$index]}" "$target_dir/${repositories[$index]}.db"
done
