import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class FetchImagesTests(unittest.TestCase):
    def test_materializes_manifest_payload_without_live_network(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.jpg"
            source.write_bytes(b"fixed encoded image payload")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"images": [{"name": "photo-001.jpg", "url": source.as_uri(), "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}]}))
            destination = root / "assets"

            result = subprocess.run([sys.executable, str(Path(__file__).with_name("fetch_images.py")), "--manifest", str(manifest), "--destination", str(destination)], capture_output=True, text=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((destination / "photo-001.jpg").read_bytes(), source.read_bytes())

    def test_rejects_changed_payload_without_overwriting_existing_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.jpg"
            source.write_bytes(b"changed remote payload")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"images": [{"name": "photo-001.jpg", "url": source.as_uri(), "sha256": hashlib.sha256(b"pinned payload").hexdigest()}]}))
            destination = root / "assets"
            destination.mkdir()
            existing = destination / "photo-001.jpg"
            existing.write_bytes(b"previous asset")

            result = subprocess.run([sys.executable, str(Path(__file__).with_name("fetch_images.py")), "--manifest", str(manifest), "--destination", str(destination)], capture_output=True, text=True)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(existing.read_bytes(), b"previous asset")

    def test_reuses_verified_asset_when_origin_is_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "assets"
            destination.mkdir()
            payload = b"pinned encoded image"
            existing = destination / "photo-001.jpg"
            existing.write_bytes(payload)
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"images": [{"name": existing.name, "url": (root / "missing-origin.jpg").as_uri(), "sha256": hashlib.sha256(payload).hexdigest()}]}))

            result = subprocess.run([sys.executable, str(Path(__file__).with_name("fetch_images.py")), "--manifest", str(manifest), "--destination", str(destination)], capture_output=True, text=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(existing.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
