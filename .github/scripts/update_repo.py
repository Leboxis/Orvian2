#!/usr/bin/env python3
"""Régénère repo.json (source LiveContainer / AltStore) pour une version donnée."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT / "repo.json"

REPO_TEMPLATE = {
    "name": "Orvian2",
    "identifier": "com.orvian2.repo",
    "tintColor": "#3B82F6",
    "iconURL": "https://raw.githubusercontent.com/REPLACE/Orvian2/main/icon.png",
    "apps": [],
}

APP_NAME = "Orvian2"
BUNDLE_ID = "com.orvian2.app"


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: update_repo.py <version> <size_bytes>")
        return 2
    version = sys.argv[1]
    try:
        size = int(sys.argv[2])
    except ValueError:
        size = 0

    download = (
        f"https://github.com/REPLACE/Orvian2/releases/download/v{version}/"
        f"Orvian2-{version}-unsigned.ipa"
    )

    repo = dict(REPO_TEMPLATE)
    repo["apps"] = [
        {
            "name": APP_NAME,
            "bundleIdentifier": BUNDLE_ID,
            "version": version,
            "downloadURL": download,
            "iconURL": repo["iconURL"],
            "tintColor": repo["tintColor"],
            "category": "utilities",
            "size": size,
        }
    ]

    REPO.write_text(json.dumps(repo, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"repo.json mis à jour pour v{version} ({size} octets).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
