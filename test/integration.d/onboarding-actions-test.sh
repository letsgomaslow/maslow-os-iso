#!/bin/bash
# Exercise configuration-first onboarding without authenticating or installing.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_image_ready || { echo "No base image; run this through ./test/integration" >&2; exit 1; }

guest_evidence=/tmp/maslow-onboarding-actions
session_env="env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 OMARCHY_SHELL_IPC_TIMEOUT=10s"
state_command="env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-setup-ai-state"

collect_actions_artifacts() {
  local status=$?
  trap - EXIT
  set +e
  if vm_running; then
    ssh_guest "tar -C /tmp -cf - '${guest_evidence#/tmp/}'" | tar -C "$RUN_DIR" -xf -
  fi
  cleanup
  exit "$status"
}
trap collect_actions_artifacts EXIT

capture_guest() {
  local name="$1"
  ssh_guest "$session_env timeout 15 grim '$guest_evidence/$name.png'"
}

wait_tool_selection() {
  local tool="$1" selected="$2" waited=0
  until ssh_guest "$state_command show | jq -e '.tools[\"$tool\"].selected == $selected'" >/dev/null; do
    ((waited >= 20)) && return 1
    sleep 1
    ((waited += 1))
  done
}

start_vm_from_base
wait_for_ssh "$BOOT_TIMEOUT"
ssh_guest "rm -rf '$guest_evidence' && mkdir -p '$guest_evidence' && pacman -Q bitwarden openai-codex-bin claude-code hermes-agent >'$guest_evidence/packages-before.txt'"

# This override exists only in the throwaway overlay. The clean installed base
# and shipped SDDM configuration remain unchanged.
ssh_guest "sha256sum /etc/sddm.conf.d/*.conf >'$guest_evidence/sddm-config-before.sha256'"
ssh_sudo "printf '[Autologin]\\nUser=$GUEST_USER\\nSession=omarchy.desktop\\n' > /etc/sddm.conf.d/99-qa-autologin.conf; systemctl restart sddm"
ssh_guest "sha256sum /etc/sddm.conf.d/*.conf >'$guest_evidence/sddm-config-overlay.sha256'"
ssh_guest "timeout 600 bash -c 'until pgrep -u \"\$(id -u)\" -x Hyprland >/dev/null; do sleep 5; done'"
check "test-only autologin reaches the disposable user's Hyprland session" ssh_guest "pgrep -u \"\$(id -u)\" -x Hyprland"
ssh_guest "timeout 180 bash -c 'until pgrep -u \"\$(id -u)\" -x quickshell >/dev/null && $session_env omarchy-shell shell ping >/dev/null 2>&1; do sleep 3; done'"
check "Maslow shell is ready before onboarding actions" ssh_guest "$session_env omarchy-shell shell ping"

ssh_guest "$session_env timeout 30 omarchy-setup-ai"
sleep 5
capture_guest "welcome"
press ret
sleep 4
capture_guest "tools-unselected"

# Step 2 focuses its list. Tab reaches the next checkbox; Space toggles it.
# A resume run may skip these already-preserved checks after an unrelated
# harness failure and continue with the remaining evidence only.
if [[ ${OMARCHY_INTEGRATION_REMAINING_ONLY:-false} != "true" ]]; then
  for tool in bitwarden codex claude hermes; do
    press tab
    press spc
    if wait_tool_selection "$tool" true; then
      printf 'ok - %s can be selected through the onboarding UI\n' "$tool"
    else
      printf 'not ok - %s can be selected through the onboarding UI\n' "$tool"
      ((FAILURES += 1))
    fi
    capture_guest "$tool-selected"
    press spc
    if wait_tool_selection "$tool" false; then
      printf 'ok - %s can be deselected without uninstalling\n' "$tool"
    else
      printf 'not ok - %s can be deselected without uninstalling\n' "$tool"
      ((FAILURES += 1))
    fi
  done
fi

# Reload all selected states to capture the configure/sign-in presentation.
for tool in bitwarden codex claude hermes; do
  check "$tool selected for combined configure view" ssh_guest "$state_command tool-select '$tool' true"
done
check "combined selected state is reopened" ssh_guest "$session_env timeout 30 omarchy-setup-ai"
sleep 5
capture_guest "core-tools-selected"
ssh_guest "$state_command show >'$guest_evidence/state-selected.json'"

# Launch the installed Bitwarden desktop without entering credentials, then
# close it so it cannot contaminate the settled idle measurement.
ssh_guest "nohup $session_env omarchy-setup-ai-tool open bitwarden >'$guest_evidence/bitwarden-dispatch.log' 2>&1 </dev/null & echo \$! >'$guest_evidence/bitwarden-dispatch.pid'"
ssh_guest "timeout 60 bash -c 'until pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/)\" >/dev/null; do sleep 2; done'" || true
check "Bitwarden desktop launches without onboarding handling credentials" ssh_guest "pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/)\""
capture_guest "bitwarden-open"
ssh_guest "pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/)\" >'$guest_evidence/bitwarden-app.pids' || true; while read -r pid; do kill \"\$pid\" 2>/dev/null || true; done <'$guest_evidence/bitwarden-app.pids'; timeout 30 bash -c 'while pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/)\" >/dev/null; do sleep 1; done'"
check "Bitwarden app processes are closed before idle sampling" ssh_guest "! pgrep -u \"\$(id -u)\" -f \"^(/usr/bin/bitwarden-desktop|/usr/lib/bitwarden/)\""
check "onboarding panel closes before idle sampling" ssh_guest "$session_env omarchy-shell shell hide maslow.ai-setup >/dev/null"
sleep 10
capture_guest "idle-precheck"

for tool in bitwarden codex claude hermes; do
  check "$tool deselected after combined view" ssh_guest "$state_command tool-select '$tool' false"
done
ssh_guest "$state_command show >'$guest_evidence/state-final.json'; pacman -Q bitwarden openai-codex-bin claude-code hermes-agent >'$guest_evidence/packages-after.txt'"
check "selecting and deselecting every starter tool leaves packages unchanged" ssh_guest "cmp '$guest_evidence/packages-before.txt' '$guest_evidence/packages-after.txt'"

if ssh_guest "$session_env timeout --kill-after=30 480 omarchy-debug-performance --json --settle=300 --sample=30 >'$guest_evidence/performance.json'"; then
  printf 'ok - settled desktop performance collected after closing test surfaces\n'
else
  printf 'not ok - settled desktop performance collected after closing test surfaces\n'
  ((FAILURES += 1))
fi
capture_guest "settled-desktop"
ssh_guest "tar -C /tmp -cf - '${guest_evidence#/tmp/}'" | tar -C "$RUN_DIR" -xf -

finish
