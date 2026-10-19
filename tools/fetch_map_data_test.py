import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from fetch_map_data import check, refresh


class MapFallbackTest(unittest.TestCase):
    def test_downloads_published_fallback_and_rejects_mismatched_update(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            public = root / 'public'
            bundled = root / 'bundled'
            public.mkdir()
            bundled.mkdir()
            layout = [['A-01', '']]
            snapshot = {
                'version': 2, 'layout': layout,
                'proximity': {
                    'schema_version': 1,
                    'map_sha256': hashlib.sha256(
                        json.dumps(layout, separators=(',', ':')).encode()).hexdigest(),
                    'booths': ['A-1'], 'neighbors': [[]],
                },
            }
            (public / 'manifest.json').write_text(json.dumps({'map': {'version': 2, 'path': 'snapshot.json'}}))
            snapshot_path = public / 'snapshot.json'
            snapshot_path.write_text(json.dumps(snapshot))
            refresh(str(public), bundled)
            check(bundled)
            self.assertEqual(json.loads((bundled / 'map-version.json').read_bytes()), {'version': 2})
            before = {file.name: file.read_bytes() for file in bundled.iterdir()}
            snapshot['layout'] = [['B-02', '']]
            snapshot_path.write_text(json.dumps(snapshot))
            with self.assertRaisesRegex(ValueError, 'do not match'):
                refresh(str(public), bundled)
            self.assertEqual({file.name: file.read_bytes() for file in bundled.iterdir()}, before)
