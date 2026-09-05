#!/bin/bash
# Exercise the installed graphical session on a throwaway overlay.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_image_ready || { echo "No base image; run this through ./test/integration" >&2; exit 1; }

start_vm_from_base
wait_for_ssh "$BOOT_TIMEOUT"

guest_evidence=/tmp/maslow-desktop-qa
ssh_guest "rm -rf '$guest_evidence' && mkdir -p '$guest_evidence' && systemctl status sddm --no-pager >'$guest_evidence/sddm-status.txt' 2>&1 || true; journalctl -b -u sddm --no-pager >'$guest_evidence/sddm-journal.txt' 2>&1 || true; loginctl list-sessions --no-legend >'$guest_evidence/login-sessions-before.txt' 2>&1 || true; cat /etc/sddm.conf /etc/sddm.conf.d/*.conf >'$guest_evidence/sddm-config.txt' 2>&1 || true; find /var/log -maxdepth 1 -type f -name 'Xorg*.log' -exec cp {} '$guest_evidence/' \; 2>/dev/null || true"
ssh_guest "tar -C /tmp -cf - '${guest_evidence#/tmp/}'" | tar -C "$RUN_DIR" -xf -
capture_console "sddm-before-wake"

# The unencrypted unattended fixture correctly stops at SDDM. Wake the display
# and authenticate only the disposable QA account; no real user input is used.
press shift
sleep 3
capture_console "sddm-awake"
press ctrl-a
type_text "$GUEST_PASSWORD"
press ret

if ssh_guest "timeout 600 bash -c 'until pgrep -u \"\$(id -u)\" -x Hyprland >/dev/null; do sleep 5; done'"; then
  printf 'ok - disposable QA account reached a logged-in Hyprland desktop\n'
else
  printf 'not ok - disposable QA account reached a logged-in Hyprland desktop\n'
  ((FAILURES += 1))
fi

capture_console "logged-in-onboarding"
ssh_guest "pacman -Q bitwarden openai-codex-bin claude-code hermes-agent >'$guest_evidence/packages-before.txt' && env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-setup-ai-state show >'$guest_evidence/onboarding-state-before.json'"

if ssh_guest "timeout --kill-after=30 480 env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-debug-performance --json --settle=300 --sample=30 >'$guest_evidence/performance.json'"; then
  printf 'ok - settled logged-in desktop performance baseline collected\n'
else
  printf 'not ok - settled logged-in desktop performance baseline collected\n'
  ((FAILURES += 1))
fi
capture_console "logged-in-settled"

ssh_guest "pacman -Q bitwarden openai-codex-bin claude-code hermes-agent >'$guest_evidence/packages-after.txt' && cmp '$guest_evidence/packages-before.txt' '$guest_evidence/packages-after.txt'"
check "onboarding observation leaves preinstalled package inventory unchanged" ssh_guest "cmp '$guest_evidence/packages-before.txt' '$guest_evidence/packages-after.txt'"
ssh_guest "loginctl list-sessions --no-legend >'$guest_evidence/login-sessions-after.txt' 2>&1 || true; tar -C /tmp -cf - '${guest_evidence#/tmp/}'" | tar -C "$RUN_DIR" -xf -

finish
