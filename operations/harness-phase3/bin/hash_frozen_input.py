#!/usr/bin/env python3
"""Hash the frozen Phase 3 intake surface."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: hash_frozen_input.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    run_dir = Path(sys.argv[2]).resolve(strict=False)
    input_dir = run_dir / "input"
    if not input_dir.is_dir():
        print(f"missing input directory: {input_dir}", file=sys.stderr)
        return 1

    files = sorted(
        path for path in input_dir.rglob("*") if path.is_file() and path.name != "input.sha256"
    )
    if not files:
        print(f"no frozen input files to hash under: {input_dir}", file=sys.stderr)
        return 1

    hash_lines = [f"{sha256_file(path)}  {path.relative_to(input_dir).as_posix()}" for path in files]
    (input_dir / "input.sha256").write_text("\n".join(hash_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
