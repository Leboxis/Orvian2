#!/usr/bin/env python3
"""Renvoie le chemin du Xcode le plus récent installé sur le runner.

macOS `sort` ne supporte pas `-V`, donc on compare les versions en Python.
Le Xcode par défaut (`/Applications/Xcode.app`) est préféré s'il est présent,
sinon on prend la version numérique la plus élevée.
"""
from __future__ import annotations

import glob
import os
import re
import sys


def version_key(path: str) -> tuple[int, ...]:
    name = os.path.basename(path)
    match = re.search(r"Xcode_?(\d+(?:\.\d+)*)\.app$", name)
    if match:
        return tuple(int(part) for part in match.group(1).split("."))
    if name == "Xcode.app":
        return (0,)
    return (-1,)


def main() -> int:
    candidates = [p for p in glob.glob("/Applications/Xcode*.app") if "beta" not in p.lower()]
    if not candidates:
        print("/Applications/Xcode.app")
        return 0
    # Le Xcode le plus récent possède les runtimes simulateur alignés avec son SDK.
    print(max(candidates, key=version_key))
    return 0


if __name__ == "__main__":
    sys.exit(main())
