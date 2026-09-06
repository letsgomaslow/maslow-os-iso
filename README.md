# Maslow OS ISO

This repository builds the bootable installer for [Maslow OS](https://github.com/letsgomaslow/maslow-os), using the Omarchy installer engine.

The ISO targets **64-bit Intel and AMD PCs with UEFI**, plus x86_64 virtual machines. It is **not Apple-only**. A fresh installation has been tested on a Lenovo ThinkPad; other hardware still needs testing.

Intel Macs can use the ISO in a virtual machine. Direct installation on Mac hardware is not currently supported. ARM64 devices, including Apple Silicon Macs, need a different installer.

> **Internal preview:** there is no public Maslow ISO release yet. Do not redistribute preview images.

## How the repositories fit together

- [maslow-os](https://github.com/letsgomaslow/maslow-os) provides the desktop, commands, and defaults; branch `main`.
- [maslow-os-pkgs](https://github.com/letsgomaslow/maslow-os-pkgs) provides package recipes; branch `maslow`.
- **This repository** assembles the live system, offline packages, and installer; branch `maslow`.

## Build a test ISO

Read [AGENTS.md](AGENTS.md) and [DOWNSTREAM.md](DOWNSTREAM.md) first. Use clean checkouts and record the exact commit from all three repositories.

Assembly runs in an x86_64 Linux Docker container. A native x86_64 Linux host is preferred. The internal candidate was built through Docker Desktop emulation on Apple Silicon, using Bash 5 on the host. That does not make the resulting ISO an ARM64 installer.

With the three repositories checked out side by side, run from this repository:

```bash
./bin/omarchy-iso-make --local-source \
  "../Maslow OS - Linux" \
  "../Maslow OS - Packages"
```

Output goes into `release/`. The build includes the runtime, settings, AI tools, curated plugins, and Chrome from the supplied recipes.

**Known cleanup defect:** the September 5 image was created, but the wrapper failed while changing ownership of older output files. Scope that cleanup to the current build's files before the next build. Do not rebuild the verified ISO just for this defect. See the [candidate record](https://github.com/letsgomaslow/maslow-os/blob/main/docs/handoffs/2026-09-05-verified-usb-native-acceptance.md) for details.

## Verify and test

1. Verify the exact ISO's SHA-256 checksum.
2. Use a spare PC or disposable VM. Back up important data first.
3. Before writing a USB, identify its current model, size, and disk identifier and confirm the erase target. Verify the written data and safely eject it.
4. Boot the live installer and check that it responds. Confirm the installation disk before proceeding; installation can erase it.
5. After installation, remove the USB or detach the ISO and boot from the installed disk.
6. Test app installation **before any update**, then check defaults, AI setup, reboot behavior, and supported OS/plugin updates.

The Lenovo tester confirmed fresh app installs before updating, Chrome default, the Maslow dock icon, and Super+A opening App Launcher. The user later reported running the system update. Detailed post-update, AI, recovery, and performance checks remain open in the [acceptance checklist](https://github.com/letsgomaslow/maslow-os/blob/main/docs/handoffs/2026-09-05-verified-usb-native-acceptance.md).

Some systemd setup commands crashed during emulated assembly. A checksum or successful desktop login does not replace native service-health checks.

For source checks, run on Linux:

```bash
./test/maslow-branding
./test/all
```

These do not replace installing and testing the actual ISO.

## Advanced testing and automation

See the [installer reference](docs/installer-reference.md) for unattended installation, Proxmox examples, graphical acceptance tests, and integration tests. Keep credentials out of Git and shared logs.

## Release limits and credits

Do not use inherited Omarchy signing or upload commands to publish Maslow images. Public releases require approved Maslow-owned signing, package distribution, and tested update/recovery paths. Chrome redistribution is not approved.

See [NOTICE](NOTICE) for upstream attribution and licensing information.
