#!/usr/bin/env python3
"""Copy real local current-avatar image bytes into private native build storage.

Only SELECTs against the task PG; no Rails, HTTP, resize/cache writes or response
fixtures. Native requests still authorize username/upload membership dynamically.
"""
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
source = root.parent / "discourse/public"
target = root / "build/media"
target.mkdir(parents=True, exist_ok=True)
expected = "postgres://discourse@127.0.0.1:5499"
assert os.environ["DSPINEL_PG_URL"] == expected
sql = """BEGIN READ ONLY;
SELECT DISTINCT up.url FROM uploads up JOIN users u ON u.uploaded_avatar_id=up.id
WHERE NOT up.secure AND up.extension IN ('png','jpg','jpeg','webp','gif')
UNION SELECT DISTINCT im.url FROM optimized_images im JOIN users u ON u.uploaded_avatar_id=im.upload_id
JOIN uploads up ON up.id=im.upload_id WHERE NOT up.secure;
ROLLBACK;"""
paths = subprocess.check_output(["psql", expected + "/discourse_development", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", sql], text=True,
                                env=dict(os.environ, PGOPTIONS="-c default_transaction_read_only=on")).splitlines()
count = 0
for url in paths:
    if not url.startswith("/uploads/default/") or any(p in (".", "..") for p in Path(url).parts):
        raise SystemExit("unsupported avatar asset storage")
    original = source / url[1:]
    assert original.resolve().is_relative_to(source.resolve())
    if original.is_file():
        copied = target / url[1:]
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, copied)
        count += 1
print(f"Staged {count} real public current-avatar images in private build/media; live native authorization remains required")
