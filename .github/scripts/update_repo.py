#!/usr/bin/env python3
"""Régénère repo.json (source LiveContainer / AltStore) pour une version donnée."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT / "repo.json"

APP_NAME = "Orvian2"
BUNDLE_ID = "com.orvian2.app"
TINT = "#3B82F6"

# « owner/repo » fourni par GitHub Actions, ex. Leboxis/Orvian2.
SLUG = os.environ.get("GITHUB_REPOSITORY", "Leboxis/Orvian2")
OWNER, _, NAME = SLUG.partition("/")
NAME = NAME or "Orvian2"

RAW_BASE = f"https://raw.githubusercontent.com/{SLUG}/main"
ICON_URL = f"{RAW_BASE}/icon.png"
IDENTIFIER = f"com.{OWNER.lower()}.{NAME.lower()}.repo"


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
        f"https://github.com/{SLUG}/releases/download/v{version}/"
        f"Orvian2-{version}-unsigned.ipa"
    )

    repo = {
        "name": APP_NAME,
        "identifier": IDENTIFIER,
        "tintColor": TINT,
        "iconURL": ICON_URL,
        "apps": [
            {
                "name": APP_NAME,
                "bundleIdentifier": BUNDLE_ID,
                "version": version,
                "downloadURL": download,
                "iconURL": ICON_URL,
                "tintColor": TINT,
                "category": "utilities",
                "size": size,
            }
        ],
    }

    REPO.write_text(json.dumps(repo, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"repo.json mis à jour pour v{version} ({size} octets) — {SLUG}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

