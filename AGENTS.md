# Maslow OS ISO Repository Agent Instructions

Work in this repository as the installation-media stage of the three-repository Maslow OS product pipeline. Optimize for reproducible installation, accurate provenance, and end-to-end user-visible validation.

# Repository Role

This repository owns the bootable x86_64 installer and its test harness. It does not own the installed desktop source or Arch package recipes.

- `letsgomaslow/maslow-os` owns the installed runtime and visible product experience. Its public product branch is `main`.
- `letsgomaslow/maslow-os-pkgs` owns the package recipes consumed during local-source builds. Its downstream product branch is `maslow`.
- `letsgomaslow/maslow-os-iso` (this repository) assembles those inputs into the live environment, offline mirror, installer, and bootable ISO. Its downstream product branch is `maslow`; `quattro` mirrors upstream.

The dependency flow is `maslow-os source` -> `maslow-os-pkgs package recipes` -> `maslow-os-iso installation media`.

# Change Routing

- Change boot menus, live-environment packages, installer presentation, installation orchestration, offline-mirror assembly, media diagnostics, and VM harnesses here.
- Change installed desktop commands, themes, runtime branding, defaults, migrations, and user documentation in `maslow-os`.
- Change `PKGBUILD` files, package metadata, dependencies, file ownership, install hooks, and repository publication in `maslow-os-pkgs`.
- Do not vendor a second editable copy of runtime product strings or desktop configuration into this repository. Consume the canonical runtime source or packaged artifact.

# Source and Branch Rules

- Never assume the three repositories share one default branch. Inspect each downstream remote.
- Release-candidate local-source builds use `maslow-os` branch `main` and `maslow-os-pkgs` branch `maslow` unless an explicit pre-merge validation records different exact commits.
- Always pass both explicit checkouts to `./bin/omarchy-iso-make --local-source <runtime-checkout> <package-checkout>` for Maslow preview builds.
- Record the exact runtime, package, and ISO commits used to produce every candidate. Refuse release claims when any checkout is dirty or provenance is missing.
- Preserve Omarchy-compatible command names, package names, paths, service identifiers, and update behavior inside the installer.
- Do not use inherited upstream signing or upload commands for a Maslow release. Public distribution requires explicitly approved Maslow-owned signing and publication infrastructure.

# Working Style

- Inspect installer and builder code before editing and keep the change scoped to the appropriate phase.
- Use Bash 5 syntax, two-space indentation, and `[[ ]]` or `(( ))` for tests.
- Keep installer success dependent on real exit status; never turn a failed phase into a successful completion screen.
- Do not force-push or rebase the public `maslow` branch.
- Keep commits atomic and use reviewed pull requests for downstream changes.

# Verification

- Read the runtime repository's `docs/handoffs/2026-09-05-verified-usb-native-acceptance.md` before continuing this candidate. Keep exact built commits separate from later documentation commits and current branch heads.
- Distinguish focused source tests, image creation, wrapper exit status, checksum/readback verification, and tester-reported native behavior. A valid image does not make a failed build wrapper successful; emulated systemd crashes still need native service-health checks.
- The recorded recursive `/out/` ownership cleanup defect must be fixed narrowly before the next build: touch only current outputs and test with protected old artifacts. Do not rebuild the verified candidate solely for cleanup or make unrelated output trees writable.
- Test normal app installs before the first update; never hide a database handoff failure with a manual database refresh. Verify reboot persistence and supported OS/plugin updates separately.
- Enumerate removable devices afresh, show exact size/model/disk identifier, obtain explicit erase confirmation, verify written bytes, and safely eject. Never reuse the historical `/dev/disk4` identifier without a new check.
- Keep the Lenovo an acceptance target, not a manually customized fork. Do not add features, dictation, or plugins while closing this candidate's checks. A source push is not authorization to rebuild or publish an ISO.

- Run `git diff --check`, `./test/maslow-branding`, and `./test/all` on Linux.
- When package ownership changes, build the affected packages together and run `builder/check-package-file-overlap.sh` before installing.
- Build from clean, explicit sibling checkouts and verify the produced checksum.
- Complete a fresh disposable x86_64 VM installation, reboot from the installed disk, and validate login, desktop, keybindings, updates, and recovery before claiming release readiness.
- Keep passwords and provider credentials out of screenshots, logs, build metadata, and committed fixtures.
