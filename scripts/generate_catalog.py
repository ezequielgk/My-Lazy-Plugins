#!/usr/bin/env python3
"""Regenera catalog.toml a partir de cada <plugin>/plugin.toml en la raíz del repo.

- added_at se preserva del catalog.toml anterior si el plugin ya existía ahí;
  si es nuevo, se usa la misma fecha que updated_at.
- updated_at se recalcula solo si la versión declarada en plugin.toml cambió
  desde la última corrida (evita "tocar" entries que no cambiaron).
- Cualquier [[plugin.release]] que hayas agregado a mano para un id existente
  se preserva tal cual entre corridas (el script nunca las genera solo).

Requiere Python 3.11+ (usa tomllib de la stdlib, solo lectura).
"""
from __future__ import annotations

import subprocess
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "catalog.toml"
SKIP_DIRS = {".github", "scripts", ".git"}

HEADER = (
    "# This file is auto-generated. Do not edit manually.\n"
    "# Do not include it in your commit.\n"
    "# Noctalia plugins catalog.\n"
)


def git_commit_time(path: Path) -> int:
    """Timestamp unix del último commit que tocó `path`. Si no hay historial
    (archivo nuevo todavía sin commitear), usa la hora actual."""
    out = subprocess.run(
        ["git", "log", "-1", "--format=%at", "--", str(path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    return int(out) if out else int(time.time())


def load_existing_catalog() -> dict[str, dict]:
    if not CATALOG_PATH.exists():
        return {}
    data = tomllib.loads(CATALOG_PATH.read_text())
    return {p["id"]: p for p in data.get("plugin", [])}


def toml_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def format_entry(entry: dict) -> str:
    lines = ["[[plugin]]"]
    lines.append(f'id = {toml_str(entry["id"])}')
    lines.append(f'name = {toml_str(entry["name"])}')
    lines.append(f'version = {toml_str(entry["version"])}')
    lines.append(f'updated_at = {entry["updated_at"]}')
    lines.append(f'added_at = {entry["added_at"]}')
    lines.append(f'author = {toml_str(entry["author"])}')
    lines.append(f'license = {toml_str(entry["license"])}')
    if entry.get("icon"):
        lines.append(f'icon = {toml_str(entry["icon"])}')
    lines.append(f'description = {toml_str(entry["description"])}')
    if entry.get("deprecated"):
        lines.append("deprecated = true")
    lines.append(f'plugin_api = {entry["plugin_api"]}')
    tags = ", ".join(toml_str(t) for t in entry.get("tags", []))
    lines.append(f"tags = [{tags}]")

    for rel in entry.get("release", []):
        lines.append("")
        lines.append("[[plugin.release]]")
        lines.append(f'plugin_api = {rel["plugin_api"]}')
        lines.append(f'version = {toml_str(rel["version"])}')
        lines.append(f'updated_at = {rel["updated_at"]}')
        lines.append(f'rev = {toml_str(rel["rev"])}')

    return "\n".join(lines)


def main() -> None:
    existing = load_existing_catalog()
    entries = []

    for plugin_dir in sorted(ROOT.iterdir()):
        if not plugin_dir.is_dir() or plugin_dir.name in SKIP_DIRS:
            continue
        manifest = plugin_dir / "plugin.toml"
        if not manifest.exists():
            continue

        data = tomllib.loads(manifest.read_text())
        plugin_id = data["id"]
        prev = existing.get(plugin_id, {})

        version_changed = prev.get("version") != data["version"]
        updated_at = (
            git_commit_time(manifest)
            if version_changed or "updated_at" not in prev
            else prev["updated_at"]
        )
        added_at = prev.get("added_at", updated_at)

        entries.append(
            {
                "id": plugin_id,
                "name": data["name"],
                "version": data["version"],
                "updated_at": updated_at,
                "added_at": added_at,
                "author": data["author"],
                "license": data["license"],
                "icon": data.get("icon"),
                "description": data["description"],
                "deprecated": data.get("deprecated", False),
                "plugin_api": data["plugin_api"],
                "tags": data.get("tags", []),
                "release": prev.get("release", []),
            }
        )

    body = "\n\n".join(format_entry(e) for e in entries)
    CATALOG_PATH.write_text(HEADER + "\n" + body + "\n")
    print(f"catalog.toml regenerado con {len(entries)} plugin(s).")


if __name__ == "__main__":
    main()
