"""Unit tests for installer accessibility preference staging."""

import sys
import types
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest import TestCase, mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "configs/airootfs/usr/share/omarchy-iso"))
sys.modules.setdefault(
    "orchestrator.archinstall_adapter", types.ModuleType("orchestrator.archinstall_adapter")
)

from orchestrator import phases_impl  # noqa: E402


class AccessibilityPreferenceTests(TestCase):
    def test_valid_preferences_are_staged_for_runtime_and_sddm(self):
        with TemporaryDirectory() as temporary:
            target = Path(temporary) / "target"
            target.mkdir()
            source = Path(temporary) / "maslow-accessibility.conf"
            source.write_text(
                "speech=true\nlarge_text=false\nhigh_contrast=true\nreduced_motion=true\n",
                encoding="utf-8",
            )
            real_path = phases_impl.Path

            def mapped_path(value):
                if str(value) == "/root/maslow-accessibility.conf":
                    return source
                return real_path(value)

            with mock.patch.object(phases_impl, "Path", side_effect=mapped_path), mock.patch.object(
                phases_impl.subprocess, "run"
            ) as run:
                phases_impl.stage_accessibility_preferences(SimpleNamespace(target=target))

            staged = target / "etc/maslow-os/accessibility.conf"
            self.assertEqual(staged.read_text(encoding="utf-8"), source.read_text(encoding="utf-8"))
            self.assertEqual(staged.stat().st_mode & 0o777, 0o644)
            run.assert_called_once_with(
                ["arch-chroot", str(target), "/usr/bin/omarchy-accessibility-sync"], check=True
            )

    def test_unknown_value_blocks_staging(self):
        with TemporaryDirectory() as temporary:
            target = Path(temporary) / "target"
            target.mkdir()
            source = Path(temporary) / "maslow-accessibility.conf"
            source.write_text(
                "speech=maybe\nlarge_text=false\nhigh_contrast=false\nreduced_motion=false\n",
                encoding="utf-8",
            )
            real_path = phases_impl.Path

            def mapped_path(value):
                if str(value) == "/root/maslow-accessibility.conf":
                    return source
                return real_path(value)

            with mock.patch.object(phases_impl, "Path", side_effect=mapped_path):
                with self.assertRaisesRegex(RuntimeError, "malformed"):
                    phases_impl.stage_accessibility_preferences(SimpleNamespace(target=target))
