import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=root / "Host/ImageFixtureManifest.json")
    parser.add_argument("--destination", type=Path, default=root / "Host/BenchmarkImages")
    arguments = parser.parse_args()
    manifest = json.loads(arguments.manifest.read_text())
    arguments.destination.mkdir(parents=True, exist_ok=True)
    for photo in manifest["images"]:
        target = arguments.destination / photo["name"]
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == photo["sha256"]:
            continue
        data = urlopen(photo["url"], timeout=30).read()
        if hashlib.sha256(data).hexdigest() != photo["sha256"]:
            raise ValueError(f"Image payload changed: {photo['name']}")
        target.write_bytes(data)
    print(f"Prepared {len(manifest['images'])} image assets")
