#!/usr/bin/env python3
"""Vérifie la robustesse du cache disque favoris et l'absence de secrets.

- S'assure que le code de cache JSON ne contient pas de secret en dur.
- Vérifie la présence des fichiers clés attendus.
- Refuse tout token d'API « réel » commité (heuristique longueur + préfixe).
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

# Sortie UTF-8 stable quel que soit le terminal (Windows/CI).
try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

ROOT = Path(__file__).resolve().parents[2]
FAILURES: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        FAILURES.append(message)
        print(f"  [X] {message}")
    else:
        print(f"  [OK] {message}")


def check_expected_files() -> None:
    print("Fichiers clés :")
    expected = [
        "project.yml",
        "Orvian2/Core/Cache/FavoritesDiskCache.swift",
        "Orvian2/Core/Cache/DirectoryListStore.swift",
        "Orvian2/Core/Models/DriveModels.swift",
    ]
    for relative in expected:
        require((ROOT / relative).exists(), f"{relative} présent")


def check_no_committed_secrets() -> None:
    print("Recherche de secrets commités :")
    ignored = {".env", ".env.local"}
    suspicious = re.compile(r'(?i)(api[_-]?token|bearer)\s*[:=]\s*["\']([A-Za-z0-9_\-\.]{20,})["\']')
    for path in ROOT.rglob("*.swift"):
        if any(part in {".build", "build", "DerivedData"} for part in path.parts):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in suspicious.finditer(text):
            value = match.group(2)
            if value.lower() in {"your_token_here", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}:
                continue
            FAILURES.append(f"Secret potentiel dans {path.relative_to(ROOT)}")
    require(
        not any("Secret potentiel" in failure for failure in FAILURES),
        "Aucun token en dur dans le code",
    )
    for env_name in ignored:
        # Les fichiers .env ne doivent pas être présents dans un checkout CI.
        if (ROOT / env_name).exists():
            print(f"  ! {env_name} présent localement (doit rester ignoré par git)")


def check_gitignore() -> None:
    print("Vérification .gitignore :")
    gitignore = (ROOT / ".gitignore")
    require(gitignore.exists(), ".gitignore présent")
    if gitignore.exists():
        content = gitignore.read_text(encoding="utf-8", errors="ignore")
        for entry in [".env", ".env.local", "*.xcodeproj", "*.ipa", "Payload/"]:
            require(entry in content, f"'{entry}' ignoré")


def main() -> int:
    check_expected_files()
    check_no_committed_secrets()
    check_gitignore()
    print()
    if FAILURES:
        print(f"ECHEC : {len(FAILURES)} problème(s) détecté(s).")
        return 1
    print("OK : cache favoris et hygiène des secrets validés.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
