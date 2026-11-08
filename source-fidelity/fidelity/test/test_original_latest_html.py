import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from probe_original_latest_html import audit_source


def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


class OriginalHtmlSourceAuditTests(unittest.TestCase):
    def test_checks_bytes_and_raw_symlink_target_not_normalized_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = b"class Original\nend\n"
            (root / "original.rb").write_bytes(data)
            (root / "skills").symlink_to("../.skills/")
            tree = (f"100644 blob {git_blob(data)}\toriginal.rb\0"
                    f"120000 blob {git_blob(b'../.skills/')}\tskills\0").encode()
            with patch("probe_original_latest_html.subprocess.check_output", return_value=tree):
                result = audit_source(root)
                self.assertEqual(result["matched_source_files"], 2)
                (root / "original.rb").write_bytes(data + b"# not original\n")
                with self.assertRaisesRegex(AssertionError, "original source changed"):
                    audit_source(root)

    def test_nonblob_and_missing_source_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch("probe_original_latest_html.subprocess.check_output",
                       return_value=b"160000 commit deadbeef\tother-tree\0"):
                with self.assertRaisesRegex(AssertionError, "unsupported source entry"):
                    audit_source(root)
            with patch("probe_original_latest_html.subprocess.check_output",
                       return_value=f"100644 blob {git_blob(b'original')}\tabsent.rb\0".encode()):
                with self.assertRaises(FileNotFoundError):
                    audit_source(root)


if __name__ == "__main__":
    unittest.main()
