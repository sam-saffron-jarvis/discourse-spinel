import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from private_pg_fixture import PrivatePG, claim


class PrivatePGFixtureTests(unittest.TestCase):
    def test_usage_claim_is_exclusive_and_cannot_be_reset_by_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            usage = root / "usage.json"
            first = claim(root, path=usage, auth_sha="test-authorization")
            self.assertEqual(first["rails_invocations"], 0)
            self.assertEqual(usage.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                claim(root, path=usage, auth_sha="test-authorization")
            self.assertEqual(json.loads(usage.read_text()), first)

    def test_failed_shared_postcheck_still_removes_owned_sensitive_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pg = PrivatePG(root / "sensitive", root, "test-authorization")
            pg.base.mkdir(mode=0o700)
            pg.data.mkdir()
            pg.dump.write_text("test-only secret row")
            pg.socket = root / "socket"
            pg.socket.mkdir()
            pg.source_env = {}
            with patch.object(pg, "shared_proof", side_effect=RuntimeError("postcheck failed")):
                with self.assertRaises(RuntimeError):
                    pg.cleanup()
            self.assertFalse(pg.base.exists())
            self.assertFalse(pg.socket.exists())
            self.assertTrue(pg.record["raw_snapshot_removed"])
            self.assertTrue(pg.record["data_removed"])
            self.assertFalse(pg.record["cleanup_verified"])

    def test_setup_failure_before_postmaster_has_idempotent_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pg = PrivatePG(root / "sensitive", root, "test-authorization")
            pg.base.mkdir(mode=0o700)
            pg.dump.write_text("test-only snapshot")
            pg.cleanup()
            pg.cleanup()
            self.assertTrue(pg.record["cleanup_verified"])
            self.assertTrue(pg.record["sensitive_work_removed"])


if __name__ == "__main__":
    unittest.main()
