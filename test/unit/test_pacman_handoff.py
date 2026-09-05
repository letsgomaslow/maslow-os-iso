"""Regression coverage for the offline-to-online pacman database handoff."""

import sys
import tempfile
import types
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "configs/airootfs/usr/share/omarchy-iso"))

sys.modules.setdefault(
    "orchestrator.archinstall_adapter", types.ModuleType("orchestrator.archinstall_adapter")
)

from orchestrator import phases_impl  # noqa: E402


class PacmanDatabaseHandoffTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.target = self.root / "target"
        self.source.mkdir()
        self.ctx = types.SimpleNamespace(target=self.target)

    def write_databases(self):
        for repository in phases_impl.ONLINE_PACMAN_REPOSITORIES:
            (self.source / f"{repository}.db").write_bytes(
                f"{repository} database\n".encode()
            )

    def test_seeds_fresh_target_with_complete_online_database_set(self):
        self.write_databases()

        phases_impl._seed_target_online_pacman_databases(self.ctx, self.source)

        sync = self.target / "var/lib/pacman/sync"
        self.assertEqual(
            sorted(path.name for path in sync.iterdir()),
            ["core.db", "extra.db", "multilib.db", "omarchy.db"],
        )
        for repository in phases_impl.ONLINE_PACMAN_REPOSITORIES:
            self.assertEqual(
                (sync / f"{repository}.db").read_bytes(),
                (self.source / f"{repository}.db").read_bytes(),
            )

    def test_missing_database_fails_before_creating_partial_target(self):
        self.write_databases()
        (self.source / "multilib.db").unlink()

        with self.assertRaisesRegex(RuntimeError, "multilib.db"):
            phases_impl._seed_target_online_pacman_databases(self.ctx, self.source)

        self.assertFalse((self.target / "var/lib/pacman/sync").exists())

    def test_empty_database_is_rejected(self):
        self.write_databases()
        (self.source / "omarchy.db").write_bytes(b"")

        with self.assertRaisesRegex(RuntimeError, "omarchy.db"):
            phases_impl._seed_target_online_pacman_databases(self.ctx, self.source)


if __name__ == "__main__":
    unittest.main()
