"""Verify complete framework source against the task's pinned cached gem.

No fetching, extraction, execution or synthetic class/module availability. The
original package was Gem::Package.verify'd at acquisition; its locked SHA and
exact data.tar.gz members are rechecked on each source proof.
"""
import io
from pathlib import Path
import re
import tarfile


def verify_framework_sources(lock, here, root, digest):
    reports = []
    for group in lock.get("framework_sources", []):
        package = root / group["package"]
        package_bytes = package.read_bytes()
        assert digest(package_bytes) == group["package_sha256"], "framework package changed"
        runtime_lock = (root / group["runtime_lock"]).read_bytes()
        assert digest(runtime_lock) == group["runtime_lock_sha256"], "framework runtime lock changed"
        assert re.search(r"^    " + re.escape(group["gem"]) + r" \(" + re.escape(group["version"]) + r"\)$", runtime_lock.decode(), re.M)
        with tarfile.open(fileobj=io.BytesIO(package_bytes), mode="r:*") as archive:
            stream = archive.extractfile("data.tar.gz")
            assert stream is not None
            data = stream.read()
        files = []
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as members:
            for item in group["files"]:
                relative = Path(item["path"])
                assert not relative.is_absolute() and ".." not in relative.parts
                assert relative.parts[:2] == ("source", "framework")
                stream = members.extractfile(item["package_member"])
                assert stream is not None
                original = stream.read()
                copied = (here / relative).read_bytes()
                assert copied == original, "framework source differs from original package member"
                assert digest(copied) == item["sha256"], "framework source changed"
                files.append({**item, "bytes": len(copied)})
        reports.append({"gem": group["gem"], "version": group["version"],
                        "package_sha256": group["package_sha256"], "files": files})
    return reports
