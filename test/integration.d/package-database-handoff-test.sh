#!/bin/bash
# Prove a fresh installed image can resolve and install an online package
# before any supported full update has refreshed its seeded databases.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_image_ready || { echo "No base image; run this through ./test/integration" >&2; exit 1; }

start_vm_from_base
wait_for_ssh "$BOOT_TIMEOUT"

for repository in core extra multilib omarchy; do
  check "$repository is enabled in the installed online pacman configuration" ssh_guest \
    "pacman-conf --repo-list | grep -Fx '$repository'"
  check "$repository starts with a nonempty readable package database" ssh_guest \
    "test -s '/var/lib/pacman/sync/$repository.db' && bsdtar -tf '/var/lib/pacman/sync/$repository.db' | grep -q ."
done

check "the temporary offline installer repository is no longer configured" ssh_guest \
  "! pacman-conf --repo-list | grep -Fx offline"

probe_package=figlet
check "$probe_package is not preinstalled" ssh_guest "! pacman -Q '$probe_package'"
check "$probe_package resolves from the seeded online databases without a refresh" ssh_guest \
  "pacman -Si '$probe_package'"
check "$probe_package installs through the supported package helper before omarchy update" ssh_sudo \
  "env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-pkg-add '$probe_package'"
check "$probe_package is registered and runnable after the first package transaction" ssh_guest \
  "pacman -Q '$probe_package' && command -v '$probe_package' >/dev/null"

finish
