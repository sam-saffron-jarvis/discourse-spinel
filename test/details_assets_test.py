#!/usr/bin/env python3
"""Fail-closed details stage reuse regression; only owned build scratch mutates."""
import hashlib
import json
from pathlib import Path
import runpy
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]
module = runpy.run_path(str(ROOT / 'frontend/stage-details.py'))
verify = module['verify_stage']


class DetailsStageTest(unittest.TestCase):
    def setUp(self):
        self.scratch = ROOT / 'build/details/stage-reuse-test'
        self.assertFalse(self.scratch.exists(), 'refuse an unknown scratch directory')
        self.scratch.mkdir(parents=True)
        self.original_out = verify.__globals__['OUT']
        verify.__globals__['OUT'] = self.scratch
        self.manifest = json.loads((self.original_out / 'manifest.json').read_text())
        self.css = self.scratch / self.manifest['stylesheet']['path']
        self.css.write_bytes((self.original_out / self.manifest['stylesheet']['path']).read_bytes())
        # Substitute test-only source/cache transports; do not change pinned source
        # or its cache to simulate corruption.
        self.input = self.scratch / 'source.scss'
        self.input.write_text('test-only source transport')
        self.cache = self.scratch / 'processor.js'
        self.cache.write_text('test-only compiler transport')
        self.manifest['source_files'].append({'path': str(self.input), 'sha256': self.sha(self.input)})
        self.manifest['stylesheet']['asset_processor_path'] = str(self.cache)
        self.manifest['stylesheet']['asset_processor_sha256'] = self.sha(self.cache)
        self.save()
        self.assertTrue(verify())

    def tearDown(self):
        verify.__globals__['OUT'] = self.original_out
        shutil.rmtree(self.scratch)

    def sha(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def save(self):
        (self.scratch / 'manifest.json').write_text(json.dumps(self.manifest))

    def test_corrupt_css_rejected(self):
        self.css.write_bytes(self.css.read_bytes() + b' changed')
        with self.assertRaisesRegex(SystemExit, 'CSS failed'):
            verify()

    def test_changed_source_rejected(self):
        self.input.write_text('changed source transport')
        with self.assertRaisesRegex(SystemExit, 'source changed'):
            verify()

    def test_changed_compiler_rejected(self):
        self.cache.write_text('changed compiler transport')
        with self.assertRaisesRegex(SystemExit, 'AssetProcessor source changed'):
            verify()

    def test_changed_stage_script_rejected(self):
        self.manifest['stage_script_sha256'] = '0' * 64
        self.save()
        with self.assertRaisesRegex(SystemExit, 'format/script changed'):
            verify()


if __name__ == '__main__':
    unittest.main()
