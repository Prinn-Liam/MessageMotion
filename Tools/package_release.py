#!/usr/bin/env python3
"""Export only portable source, docs and example assets; never the parent project."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = {"Package.swift", "README.md", "README.zh-Hans.md", "LICENSE", "NOTICE.md", "CONTRIBUTING.md", ".gitignore", "llms.txt"}
DIRS = {"Sources", "Tests", "Example", "Tools", ".github"}
DOCS = {"IMPLEMENTATION.md", "IMPLEMENTATION.zh-Hans.md", "MEASUREMENT.md", "VALIDATION.md", "SHOWCASE.md"}
PUBLIC_MEDIA = {"docs/media/scroll.gif", "docs/media/keyboard.gif", "docs/media/provenance.json"}
EXCLUDED_PARTS = {".build", ".swiftpm", ".git", "xcuserdata", "__pycache__", "DerivedData", ".DS_Store"}
EXCLUDED_SUFFIXES = {".xcuserstate", ".mobileprovision", ".p12", ".ipa", ".mov", ".mp4", ".raw", ".pyc"}


def sources():
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED_PARTS for part in relative.parts) or path.is_symlink() or not path.is_file():
            continue
        if path.suffix in EXCLUDED_SUFFIXES:
            continue
        if relative.parts[0] in DIRS or relative.as_posix() in ROOT_FILES or relative.as_posix() in PUBLIC_MEDIA or (relative.parts[0] == "docs" and relative.name in DOCS):
            yield path, relative


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    files = list(sources())
    manifest = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, relative in files:
            data = path.read_bytes()
            if path.suffix in {".swift", ".pbxproj", ".yml", ".xcscheme"}:
                text = data.decode("utf-8")
                if "/Users/" in text or "DEVELOPMENT_TEAM =" in text or "PROVISIONING_PROFILE_SPECIFIER =" in text:
                    raise SystemExit(f"Local path/signing setting found in {relative}; sanitize it before release")
            archive.writestr("MessageMotion/" + relative.as_posix(), data)
            manifest.append({"path": relative.as_posix(), "sha256": hashlib.sha256(data).hexdigest()})
        archive.writestr("MessageMotion/ReleaseManifest.json", json.dumps({"files": manifest}, indent=2) + "\n")
    print(f"Exported {len(files)} files to {args.output}")
    print("SHA256 " + hashlib.sha256(args.output.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
