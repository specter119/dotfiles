#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCAL_TOML = ROOT / ".dotter" / "local.toml"
GENERATED_DIR = ROOT / "git" / "generated"


def load_enterprises() -> dict[str, dict[str, str]]:
    if not LOCAL_TOML.exists():
        return {}

    with LOCAL_TOML.open("rb") as fh:
        data = tomllib.load(fh)

    enterprises = data.get("variables", {}).get("git_enterprise", {})
    if not isinstance(enterprises, dict):
        return {}

    result: dict[str, dict[str, str]] = {}
    for key, value in enterprises.items():
        if not isinstance(value, dict):
            continue

        repo_dir = str(value.get("repo_dir", "")).strip()
        name = str(value.get("name", "")).strip()
        email = str(value.get("email", "")).strip()
        if not (repo_dir and name and email):
            continue

        result[str(key)] = {
            "repo_dir": repo_dir,
            "name": name,
            "email": email,
        }

    return result


def validate_key(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
        raise SystemExit(f"invalid git_enterprise key: {value}")
    return value


def generate_files() -> int:
    enterprises = load_enterprises()
    shutil.rmtree(GENERATED_DIR, ignore_errors=True)
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)

    for key, entry in enterprises.items():
        filename = f"{validate_key(key)}.conf"
        content = "\n".join(
            [
                "[user]",
                f'\tname = {entry["name"]}',
                f'\temail = {entry["email"]}',
                "",
            ]
        )
        (GENERATED_DIR / filename).write_text(content, encoding="utf-8")

    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] != "generate":
        print("usage: render_git_enterprise.py generate", file=sys.stderr)
        return 1

    return generate_files()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
