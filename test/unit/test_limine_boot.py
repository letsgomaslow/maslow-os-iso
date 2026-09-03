"""Regression coverage for product-aware Limine boot-entry validation."""

import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "configs/airootfs/usr/share/omarchy-iso"))

sys.modules.setdefault(
    "orchestrator.archinstall_adapter", types.ModuleType("orchestrator.archinstall_adapter")
)

from orchestrator import phases_impl  # noqa: E402


class LimineBootEntryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.target = Path(self.tmp.name) / "mnt"
        self.target.mkdir()

        self.ctx = types.SimpleNamespace(
            target=self.target,
            encrypt=False,
            is_protected=False,
            defer_provisioning=False,
            omarchy_install={"boot": {}, "storage": {"kernel": "linux"}},
            user_configuration={"kernels": ["linux"]},
        )

        self.default_limine = self.target / "etc/default/limine"
        self.default_limine.parent.mkdir(parents=True)
        self.default_limine.write_text(
            'TARGET_OS_NAME="Maslow OS"\n'
            'CUSTOM_UKI_NAME="omarchy"\n'
            'ESP_PATH="/boot"\n'
            'KERNEL_CMDLINE[default]+="root=/dev/mapper/root"\n'
        )

        self.limine_conf = self.target / "boot/limine.conf"
        self.limine_conf.parent.mkdir(parents=True)

    def write_entry(self, os_name: str, *, branding_only: bool = False) -> None:
        if branding_only:
            self.limine_conf.write_text(f"interface_branding: {os_name} Bootloader\n")
        else:
            self.limine_conf.write_text(
                f"interface_branding: {os_name} Bootloader\n"
                f"/+{os_name}\n"
                f"comment: {os_name}\n"
            )

    def prepare_finalize_target(self) -> None:
        limine_update = self.target / "usr/bin/limine-update"
        limine_update.parent.mkdir(parents=True)
        limine_update.write_text("#!/bin/bash\n")

        snapper_root = self.target / "etc/snapper/configs/root"
        snapper_root.parent.mkdir(parents=True)
        snapper_root.write_text("SUBVOLUME=/\n")

    def prepare_validate_target(self) -> None:
        kernel_cmdline = self.target / "etc/kernel/cmdline"
        kernel_cmdline.parent.mkdir(parents=True)
        kernel_cmdline.write_text("root=/dev/mapper/root\n")

        limine_binary = self.target / "boot/EFI/limine/limine_x64.efi"
        limine_binary.parent.mkdir(parents=True)
        limine_binary.write_bytes(b"limine")

        uki = self.target / "boot/EFI/Linux/omarchy_linux.efi"
        uki.parent.mkdir(parents=True)
        uki.write_bytes(b"uki")

    def test_configured_maslow_entry_is_accepted(self):
        self.write_entry("Maslow OS")
        text = phases_impl._require_limine_os_entry(
            self.limine_conf, self.default_limine.read_text()
        )
        self.assertIn("/+Maslow OS", text)

    def test_upstream_omarchy_fallback_is_accepted(self):
        self.write_entry("Omarchy")
        text = phases_impl._require_limine_os_entry(self.limine_conf, "")
        self.assertIn("/+Omarchy", text)

    def test_branding_text_without_exact_entry_is_rejected(self):
        self.write_entry("Maslow OS", branding_only=True)
        with self.assertRaisesRegex(RuntimeError, "has no Maslow OS entry"):
            phases_impl._require_limine_os_entry(
                self.limine_conf, self.default_limine.read_text()
            )

    def test_wrong_product_entry_is_rejected(self):
        self.write_entry("Omarchy")
        with self.assertRaisesRegex(RuntimeError, "has no Maslow OS entry"):
            phases_impl._require_limine_os_entry(
                self.limine_conf, self.default_limine.read_text()
            )

    def test_finalize_limine_boot_accepts_maslow_entry(self):
        self.prepare_finalize_target()
        self.write_entry("Maslow OS")

        with mock.patch.object(phases_impl.subprocess, "run") as run:
            phases_impl.finalize_limine_boot(self.ctx)

        run.assert_any_call(
            ["arch-chroot", str(self.target), "limine-update"], check=True
        )

    def test_validate_boot_accepts_maslow_entry(self):
        self.prepare_validate_target()
        self.write_entry("Maslow OS")

        with (
            mock.patch.object(phases_impl, "_assert_boot_hooks_restored"),
            mock.patch.object(phases_impl, "_installed_kernels", return_value=["linux"]),
            mock.patch.object(
                phases_impl,
                "_read_efibootmgr",
                return_value={"entries": {"0001": "Limine"}, "order": ["0001"], "raw": ""},
            ),
            mock.patch.object(phases_impl.arch, "has_uefi", return_value=True, create=True),
        ):
            phases_impl.validate_boot(self.ctx)


if __name__ == "__main__":
    unittest.main()
