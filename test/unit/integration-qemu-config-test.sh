#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

touch "$work/candidate.iso" "$work/OVMF_CODE.fd" "$work/OVMF_VARS.fd"
cat >"$work/qemu-system" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$QEMU_ARGS_LOG"
SH
chmod +x "$work/qemu-system"

export OMARCHY_INTEGRATION_ISO="$work/candidate.iso"
export OMARCHY_INTEGRATION_SSH_PORT=2399
export OMARCHY_INTEGRATION_NO_PREVIEW=true
export OMARCHY_INTEGRATION_QEMU_BINARY="$work/qemu-system"
export OMARCHY_INTEGRATION_QEMU_IMG=/bin/false
export OMARCHY_INTEGRATION_QEMU_ACCEL=tcg
export OMARCHY_INTEGRATION_QEMU_CPU=max
export OMARCHY_INTEGRATION_QEMU_SMP=4
export OMARCHY_INTEGRATION_OVMF_CODE="$work/OVMF_CODE.fd"
export OMARCHY_INTEGRATION_OVMF_VARS="$work/OVMF_VARS.fd"
export QEMU_ARGS_LOG="$work/qemu.args"

source "$ROOT/test/integration.d/base-test.sh"
# The sourced integration harness installs its VM cleanup trap. This unit test
# launches only a logging stub, so retain only the throwaway-directory cleanup.
cleanup_unit_test() {
  rmdir "$RUN_DIR" "$BASE_DIR/runs" "$BASE_DIR" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup_unit_test EXIT
ACTIVE_OVMF="$work/OVMF_VARS.fd"
start_vm "$work/disk.qcow2" "$work/serial.log"

grep -Fx -- '-cpu' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- 'max' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- 'q35,accel=tcg' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- '4' "$QEMU_ARGS_LOG" >/dev/null
! grep -Fx -- '-enable-kvm' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- "if=pflash,format=raw,readonly=on,file=$work/OVMF_CODE.fd" "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- "if=pflash,format=raw,file=$work/OVMF_VARS.fd" "$QEMU_ARGS_LOG" >/dev/null

QEMU_ACCEL=kvm
QEMU_CPU=host
QEMU_SMP=8
QEMU_ARGS_LOG="$work/qemu-kvm.args"
start_vm "$work/disk.qcow2" "$work/serial.log"
grep -Fx -- 'host' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- 'q35,accel=kvm' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- '8' "$QEMU_ARGS_LOG" >/dev/null
grep -Fx -- '-enable-kvm' "$QEMU_ARGS_LOG" >/dev/null

grep -qF 'OMARCHY_INTEGRATION_QEMU_ACCEL:-kvm' "$ROOT/test/integration"
grep -qF 'OMARCHY_INTEGRATION_QEMU_CPU:-host' "$ROOT/test/integration"
grep -qF 'export OMARCHY_INTEGRATION_OVMF_CODE=' "$ROOT/test/integration"
grep -qF 'export OMARCHY_INTEGRATION_OVMF_VARS=' "$ROOT/test/integration"
grep -qF -- '--runtime-tests' "$ROOT/test/integration"
[[ -x "$ROOT/test/integration.d/core-preinstalled-test.sh" ]]
[[ -x "$ROOT/test/integration.d/desktop-onboarding-test.sh" ]]
[[ -x "$ROOT/test/integration.d/onboarding-actions-test.sh" ]]
[[ -x "$ROOT/test/integration.d/bitwarden-display-test.sh" ]]
display_scenario="$ROOT/test/integration.d/bitwarden-display-test.sh"
grep -qF '/usr/lib/electron[0-9]+/electron /usr/lib/bitwarden/app\.asar' "$display_scenario"
grep -qF 'omarchy-shell shell hide maslow.ai-setup' "$display_scenario"
grep -qF 'omarchy-debug-performance --json --settle=300 --sample=30' "$display_scenario"
grep -qF 'idle-before-clients.json' "$display_scenario"
grep -qF 'idle-after-layers.json' "$display_scenario"
grep -qF 'onboarding stays absent through the settled sample' "$display_scenario"
grep -qF 'stay-awake inhibition stays active through the settled sample' "$display_scenario"

# The runner parses these options before starting scenarios in child shells.
# Keep explicit firmware paths exported across that subprocess boundary.
export OMARCHY_INTEGRATION_OVMF_CODE=""
export OMARCHY_INTEGRATION_OVMF_VARS=""
OMARCHY_INTEGRATION_OVMF_CODE="$work/OVMF_CODE.fd"
OMARCHY_INTEGRATION_OVMF_VARS="$work/OVMF_VARS.fd"
bash -c '[[ $OMARCHY_INTEGRATION_OVMF_CODE == "$1" && $OMARCHY_INTEGRATION_OVMF_VARS == "$2" ]]' -- \
  "$work/OVMF_CODE.fd" "$work/OVMF_VARS.fd"

scenario="$ROOT/test/integration.d/core-preinstalled-test.sh"
for package in bitwarden openai-codex-bin claude-code hermes-agent; do
  grep -qF "$package" "$scenario"
done
grep -qF 'pacman -Q' "$scenario"
grep -qF "timeout 120 '\$tool' --version" "$scenario"
grep -qF '.authentication == \"unknown\"' "$scenario"
grep -qF 'OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/bin:/bin omarchy-setup-ai-tool' "$scenario"
grep -qF 'test/acceptance.d/preinstalled-ai-test.sh' "$scenario"
grep -qF 'test/acceptance.d/base-test.sh' "$scenario"
grep -qF 'timeout --kill-after=30 900' "$scenario"
grep -qF 'OMARCHY_ACCEPTANCE_DIR=' "$scenario"
grep -qF 'omarchy-debug-performance --json --settle=300 --sample=30' "$scenario"
grep -qF 'pgrep -u \"\$(id -u)\" -x Hyprland' "$scenario"
grep -qF 'performance baseline not labeled desktop idle' "$scenario"
grep -qF 'capture_console "postinstall-initial-screen"' "$scenario"
grep -qF 'capture_console "postinstall-settled-desktop"' "$scenario"
grep -qF 'tar -C "$RUN_DIR" -xf -' "$scenario"
if grep -Eq 'pacman[[:space:]]+-S|omarchy-pkg-add|curl|wget|token|password|login' "$scenario"; then
  echo "core preinstall scenario mutates packages, fetches software, or handles credentials" >&2
  exit 1
fi

printf 'ok - integration runner supports explicit TCG without changing KVM defaults\n'
printf 'ok - core preinstall scenario verifies packages and the explicit runtime offline gate without installing or authenticating\n'
