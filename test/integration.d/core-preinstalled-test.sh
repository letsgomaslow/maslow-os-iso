#!/bin/bash
# Verify the fresh installed image owns and can execute the starter AI tools.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_image_ready || { echo "No base image; run this through ./test/integration" >&2; exit 1; }

runtime_tests="${OMARCHY_INTEGRATION_RUNTIME_TESTS:-}"
runtime_acceptance="test/acceptance.d/preinstalled-ai-test.sh"
runtime_base="test/acceptance.d/base-test.sh"
if [[ -z $runtime_tests || ! -f $runtime_tests/$runtime_acceptance || ! -f $runtime_tests/$runtime_base ]]; then
  echo "core-preinstalled requires --runtime-tests pointing to a Maslow OS runtime checkout" >&2
  exit 1
fi

start_vm_from_base
wait_for_ssh "$BOOT_TIMEOUT"
capture_console "postinstall-initial-screen"

check "Bitwarden desktop package is installed" ssh_guest "pacman -Q bitwarden"
check "Bitwarden desktop launcher exists" ssh_guest "test -x /usr/bin/bitwarden-desktop && test -f /usr/share/applications/bitwarden.desktop"

check "Maslow Connect package is installed" ssh_guest "pacman -Q maslow-connect"
check "Maslow Connect CLI is package-owned" ssh_guest "test \"\$(type -P maslow-connect)\" -ef /usr/bin/maslow-connect"
check "Maslow Connect MCP bridge is package-owned" ssh_guest "test \"\$(type -P maslow-connect-mcp)\" -ef /usr/bin/maslow-connect-mcp"
check "Maslow Connect launcher and icon are installed" ssh_guest \
  "test -f /usr/share/applications/maslow-connect.desktop && test -f /usr/share/icons/hicolor/scalable/apps/maslow-connect.svg"
check "Maslow Connect Codex plugin is installed" ssh_guest \
  "test -f /usr/share/maslow-connect/codex-plugin/.codex-plugin/plugin.json && test -f /usr/share/maslow-connect/codex-plugin/.mcp.json"

for entry in "codex:openai-codex-bin" "claude:claude-code" "hermes:hermes-agent"; do
  tool=${entry%%:*}
  package=${entry#*:}
  check "$tool package is installed" ssh_guest "pacman -Q '$package'"
  check "$tool resolves to the packaged command" ssh_guest "test \"\$(type -P '$tool')\" -ef '/usr/bin/$tool'"
  check "$tool executable starts" ssh_guest "timeout 120 '$tool' --version"
  check "$tool onboarding status is installed but authentication stays unknown" ssh_guest \
    "env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-setup-ai-tool status '$tool' | jq -e '.installed == true and .authentication == \"unknown\"'"
done

# Copy only the acceptance test and its test helper into the disposable guest.
# Installed commands and product files continue to come exclusively from the ISO.
guest_qa_dir=/tmp/maslow-preinstalled-ai-qa
guest_artifacts=/tmp/maslow-preinstalled-ai-artifacts
runtime_log="$RUN_DIR/preinstalled-ai-acceptance.log"
if tar -C "$runtime_tests" -cf - "$runtime_base" "$runtime_acceptance" |
  ssh_guest "rm -rf '$guest_qa_dir' '$guest_artifacts' && mkdir -p '$guest_qa_dir/test/acceptance.d' '$guest_artifacts' && tar -C '$guest_qa_dir' -xf -"; then
  printf 'ok - runtime acceptance sources copied into disposable guest QA directory\n'
else
  printf 'not ok - runtime acceptance sources copied into disposable guest QA directory\n'
  ((FAILURES += 1))
fi

if ssh_guest "timeout --kill-after=30 900 env OMARCHY_ACCEPTANCE_DIR='$guest_artifacts' bash '$guest_qa_dir/$runtime_acceptance'" >"$runtime_log" 2>&1; then
  printf 'ok - installed AI runtime passes the offline fresh-home acceptance gate\n'
else
  printf 'not ok - installed AI runtime passes the offline fresh-home acceptance gate\n'
  ((FAILURES += 1))
fi

desktop_ready=false
if ssh_guest "timeout 300 bash -c 'until pgrep -u \"\$(id -u)\" -x Hyprland >/dev/null; do sleep 5; done'"; then
  desktop_ready=true
  printf 'ok - logged-in Hyprland desktop is running\n'
else
  printf 'unavailable - no logged-in Hyprland desktop; performance baseline not labeled desktop idle\n' | tee "$RUN_DIR/performance-unavailable.txt"
fi

if $desktop_ready; then
  if ssh_guest "timeout --kill-after=30 480 env OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-debug-performance --json --settle=300 --sample=30 >'$guest_artifacts/performance.json'"; then
    printf 'ok - settled logged-in desktop performance baseline collected\n'
  else
    printf 'not ok - settled logged-in desktop performance baseline collected\n'
    ((FAILURES += 1))
  fi
  capture_console "postinstall-settled-desktop"
else
  capture_console "postinstall-no-desktop"
fi

if ssh_guest "tar -C /tmp -cf - '${guest_artifacts#/tmp/}'" |
  tar -C "$RUN_DIR" -xf -; then
  printf 'ok - runtime acceptance artifacts collected\n'
else
  printf 'not ok - runtime acceptance artifacts collected\n'
  ((FAILURES += 1))
fi

finish
