#!/usr/bin/env python3
"""Reverify the upstream Phase 2 runtime-ready package against the frozen hash manifest."""

from __future__ import annotations

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def path_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_hash_manifest(path: Path) -> dict[str, str]:
    manifest: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        digest, _, rel_path = line.partition("  ")
        if not digest or not rel_path:
            raise ValueError("expected '<sha256>  <relative-path>' lines")
        manifest[rel_path] = digest
    if not manifest:
        raise ValueError("hash manifest must contain at least one entry")
    return manifest


class CheckRecorder:
    def __init__(self, run_id: str) -> None:
        self.run_id = run_id
        self.checks: list[dict[str, Any]] = []
        self.error_seen = False

    def add(
        self,
        name: str,
        status: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
    ) -> None:
        item: dict[str, Any] = {
            "name": name,
            "status": status,
            "detail": detail,
            "source_refs": source_refs,
        }
        if expected is not None:
            item["expected"] = expected
        if actual is not None:
            item["actual"] = actual
        self.checks.append(item)
        if status == "fail":
            self.error_seen = True

    def pass_check(self, name: str, detail: str, *, source_refs: list[str], expected: Any | None = None, actual: Any | None = None) -> None:
        self.add(name, "pass", detail, source_refs=source_refs, expected=expected, actual=actual)

    def fail_check(self, name: str, detail: str, *, source_refs: list[str], expected: Any | None = None, actual: Any | None = None) -> None:
        self.add(name, "fail", detail, source_refs=source_refs, expected=expected, actual=actual)

    def build_report(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "phase3-static-v1",
            "status": "fail" if self.error_seen else "pass",
            "checks": self.checks,
        }


def resolve_from_run_meta(repo_root: Path, value: Any) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError("run_meta.json must contain a non-empty phase2_runtime_ready_ref")
    path = Path(value)
    if path.is_absolute():
        return path.resolve(strict=False)
    return (repo_root / path).resolve(strict=False)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: reverify_runtime_ready.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_id = run_dir.name
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "runtime_ready_reverify.json"

    run_meta = read_json_object(run_dir / "run_meta.json")
    runtime_ready_dir = resolve_from_run_meta(repo_root, run_meta.get("phase2_runtime_ready_ref"))
    frozen_hash_path = run_dir / "input" / "runtime_ready.sha256"

    recorder = CheckRecorder(run_id)
    source_refs = [path_ref(repo_root, frozen_hash_path), path_ref(repo_root, runtime_ready_dir)]

    if runtime_ready_dir.is_dir():
        recorder.pass_check(
            "upstream_package.present",
            "Upstream Phase 2 runtime-ready package is present for reverify.",
            source_refs=[path_ref(repo_root, runtime_ready_dir)],
            expected="existing directory",
            actual=path_ref(repo_root, runtime_ready_dir),
        )
    else:
        recorder.fail_check(
            "upstream_package.present",
            "Upstream Phase 2 runtime-ready package must be present for reverify.",
            source_refs=[path_ref(repo_root, runtime_ready_dir)],
            expected="existing directory",
            actual="missing",
        )

    try:
        expected_hashes = parse_hash_manifest(frozen_hash_path)
    except (OSError, ValueError) as exc:
        recorder.fail_check(
            "upstream_package.hashes_match_frozen",
            f"Frozen runtime_ready.sha256 must be readable and well-formed: {exc}",
            source_refs=source_refs,
            expected="valid frozen runtime_ready.sha256 manifest",
            actual="invalid or unreadable",
        )
        report = recorder.build_report()
        write_json(report_path, report)
        return 1

    current_hashes: dict[str, str] = {}
    if runtime_ready_dir.is_dir():
        for package_file in sorted(path for path in runtime_ready_dir.rglob("*") if path.is_file()):
            rel_path = package_file.relative_to(runtime_ready_dir).as_posix()
            current_hashes[rel_path] = sha256_file(package_file)

    if current_hashes == expected_hashes:
        recorder.pass_check(
            "upstream_package.hashes_match_frozen",
            "Current upstream runtime-ready package still matches the frozen runtime_ready.sha256 manifest.",
            source_refs=source_refs,
            expected=sorted(expected_hashes),
            actual=sorted(current_hashes),
        )
    else:
        expected_only = sorted(set(expected_hashes) - set(current_hashes))
        current_only = sorted(set(current_hashes) - set(expected_hashes))
        mismatched = sorted(
            rel_path
            for rel_path in set(expected_hashes).intersection(current_hashes)
            if expected_hashes[rel_path] != current_hashes[rel_path]
        )
        recorder.fail_check(
            "upstream_package.hashes_match_frozen",
            "Current upstream runtime-ready package drifted from the frozen runtime_ready.sha256 manifest.",
            source_refs=source_refs,
            expected="exact hash match against frozen runtime_ready.sha256",
            actual={
                "expected_only": expected_only,
                "current_only": current_only,
                "mismatched": mismatched,
            },
        )

    report = recorder.build_report()
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
