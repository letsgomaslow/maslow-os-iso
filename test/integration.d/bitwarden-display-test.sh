#!/bin/bash
# Verify Bitwarden from the real disposable desktop display environment.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_image_ready || { echo "No base image; run this through ./test/integration" >&2; exit 1; }

guest_evidence=/tmp/maslow-bitwarden-display

collect_display_artifacts() {
  local status=$?
  trap - EXIT
  set +e
  if vm_running; then
    ssh_guest "tar -C /tmp -cf - '${guest_evidence#/tmp/}'" | tar -C "$RUN_DIR" -xf -
  fi
  cleanup
  exit "$status"
}
trap collect_display_artifacts EXIT

start_vm_from_base
wait_for_ssh "$BOOT_TIMEOUT"
ssh_guest "rm -rf '$guest_evidence' && mkdir -p '$guest_evidence'"
ssh_sudo "printf '[Autologin]\\nUser=$GUEST_USER\\nSession=omarchy.desktop\\n' > /etc/sddm.conf.d/99-qa-autologin.conf; systemctl restart sddm"
ssh_guest "timeout 600 bash -c 'until pgrep -u \"\$(id -u)\" -x Hyprland >/dev/null && pgrep -u \"\$(id -u)\" -x quickshell >/dev/null; do sleep 5; done'"
check "desktop screenshot text verifier is available" ssh_guest "command -v tesseract"
ssh_guest "env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-toggle-idle stay-awake >'$guest_evidence/idle-inhibition.txt'"
check "supported stay-awake mode inhibits the test screensaver" ssh_guest "test \"\$(env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-toggle-idle status | jq -r .enabled)\" = true"

# Pull only non-secret display routing from the live user manager. This tests
# the desktop launch path without copying the SSH session's incomplete env.
ssh_guest "display=\$(systemctl --user show-environment | sed -n 's/^DISPLAY=//p' | tail -1); wayland=\$(systemctl --user show-environment | sed -n 's/^WAYLAND_DISPLAY=//p' | tail -1); printf 'DISPLAY=%s\\nWAYLAND_DISPLAY=%s\\n' \"\$display\" \"\$wayland\" >'$guest_evidence/display.txt'; nohup env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=\"\$display\" WAYLAND_DISPLAY=\"\$wayland\" omarchy-setup-ai-tool open bitwarden >'$guest_evidence/dispatch.log' 2>&1 </dev/null &"
ssh_guest "timeout 120 bash -c 'until pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/|/usr/lib/electron[0-9]+/electron /usr/lib/bitwarden/app\.asar)\" >/dev/null; do sleep 2; done'" || true
check "Bitwarden remains running with the real desktop display environment" ssh_guest "pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/|/usr/lib/electron[0-9]+/electron /usr/lib/bitwarden/app\.asar)\""
ssh_guest "export HYPRLAND_INSTANCE_SIGNATURE=\$(find /run/user/1000/hypr -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\\n' | sort -n | tail -1 | cut -d' ' -f2); hyprctl clients -j >'$guest_evidence/clients.json'; env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=\$(sed -n 's/^WAYLAND_DISPLAY=//p' '$guest_evidence/display.txt') grim '$guest_evidence/bitwarden.png'; journalctl --user -b --no-pager | grep -i -C4 bitwarden >'$guest_evidence/journal.txt' || true"
check "Bitwarden creates a desktop window" ssh_guest "jq -e '[.[] | select((.class + .title) | ascii_downcase | contains(\"bitwarden\"))] | length > 0' '$guest_evidence/clients.json'"
ssh_guest "pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/|/usr/lib/electron[0-9]+/electron /usr/lib/bitwarden/app\.asar)\" >'$guest_evidence/app.pids' || true; while read -r pid; do kill \"\$pid\" 2>/dev/null || true; done <'$guest_evidence/app.pids'; timeout 30 bash -c 'while pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/|/usr/lib/electron[0-9]+/electron /usr/lib/bitwarden/app\.asar)\" >/dev/null; do sleep 1; done'"
check "Bitwarden app processes close before idle sampling" ssh_guest "! pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/|/usr/lib/electron[0-9]+/electron /usr/lib/bitwarden/app\.asar)\""

check "onboarding panel hide is acknowledged before idle sampling" ssh_guest "env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=\$(sed -n 's/^WAYLAND_DISPLAY=//p' '$guest_evidence/display.txt') OMARCHY_SHELL_IPC_TIMEOUT=10s omarchy-shell shell hide maslow.ai-setup >/dev/null"
ssh_guest "export HYPRLAND_INSTANCE_SIGNATURE=\$(find /run/user/1000/hypr -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\\n' | sort -n | tail -1 | cut -d' ' -f2); hyprctl clients -j >'$guest_evidence/idle-before-clients.json'; hyprctl layers -j >'$guest_evidence/idle-before-layers.json'; env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=\$(sed -n 's/^WAYLAND_DISPLAY=//p' '$guest_evidence/display.txt') grim '$guest_evidence/idle-before.png'; tesseract '$guest_evidence/idle-before.png' '$guest_evidence/idle-before' 2>/dev/null; head -1 /proc/stat >'$guest_evidence/proc-stat-before.txt'; LC_ALL=C top -b -d 30 -n 2 -w 512 >'$guest_evidence/top-30s.txt'; head -1 /proc/stat >'$guest_evidence/proc-stat-after.txt'"
check "onboarding is absent from the pre-sample desktop" ssh_guest "! grep -Eqi 'Welcome to Maslow OS|Set up your AI workspace' '$guest_evidence/idle-before.txt'"
check "screensaver remains absent during the interval sample" ssh_guest "! pgrep -f '[o]rg.omarchy.screensaver'"
ssh_guest "env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-debug-performance --json --settle=300 --sample=30 >'$guest_evidence/performance.json'; export HYPRLAND_INSTANCE_SIGNATURE=\$(find /run/user/1000/hypr -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\\n' | sort -n | tail -1 | cut -d' ' -f2); hyprctl clients -j >'$guest_evidence/idle-after-clients.json'; hyprctl layers -j >'$guest_evidence/idle-after-layers.json'; env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=\$(sed -n 's/^WAYLAND_DISPLAY=//p' '$guest_evidence/display.txt') grim '$guest_evidence/idle-after.png'; tesseract '$guest_evidence/idle-after.png' '$guest_evidence/idle-after' 2>/dev/null"
check "screensaver stays absent through the settled sample" ssh_guest "! pgrep -f '[o]rg.omarchy.screensaver'"
check "stay-awake inhibition stays active through the settled sample" ssh_guest "test \"\$(env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-toggle-idle status | jq -r .enabled)\" = true"
ssh_guest "tar -C /tmp -cf - '${guest_evidence#/tmp/}'" | tar -C "$RUN_DIR" -xf -
check "onboarding stays absent through the settled sample" bash -c "! grep -Eqi 'Welcome to Maslow OS|Set up your AI workspace' '$RUN_DIR/${guest_evidence#/tmp/}/idle-after.txt'"

finish
