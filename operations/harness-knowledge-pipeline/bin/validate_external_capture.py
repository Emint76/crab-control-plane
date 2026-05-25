#!/usr/bin/env python3
"""Validate external URL fixture-capture evidence for a knowledge-pipeline run."""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

RUNS_REF = Path("operations/harness-knowledge-pipeline/runs")
FORBIDDEN_FLAGS = [
    "openclaw_used",
    "docker_used",
    "network_used",
    "live_surface_used",
    "outside_git_paths_used",
    "auto_canonical_write_performed",
]


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_ref(repo_root: Path, path: Path) -> str:
    return path.resolve(strict=False).relative_to(repo_root.resolve(strict=False)).as_posix()


def check_payload(run_id: str, status: str, detail: str, **extra: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "status": status,
        "detail": detail,
    }
    payload.update(extra)
    return payload


def emit(checks_dir: Path, name: str, run_id: str, status: str, detail: str, **extra: object) -> None:
    write_json(checks_dir / f"{name}.json", check_payload(run_id, status, detail, **extra))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def external_url_safety_errors(url: str) -> list[str]:
    errors: list[str] = []
    split = urlsplit(url)
    if split.scheme.lower() not in {"http", "https"}:
        errors.append("URL scheme is not http/https")
    if split.username or split.password:
        errors.append("URL contains userinfo")
    host = (split.hostname or "").rstrip(".").lower()
    if not host:
        errors.append("URL host is missing")
        return errors
    if host == "localhost" or host.endswith((".local", ".localhost", ".internal")):
        errors.append("URL host is local/internal")
    if "." not in host:
        errors.append("URL host is not a public-looking FQDN")
    try:
        ip = ipaddress.ip_address(host.strip("[]"))
    except ValueError:
        ip = None
    if ip is not None and (
        ip.is_loopback
        or ip.is_private
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_unspecified
        or ip.is_reserved
    ):
        errors.append("URL IP literal is private, loopback, reserved, or otherwise unsafe")
    return errors


def rel_file_under(repo_root: Path, run_dir: Path, ref: str) -> Path | None:
    path = Path(ref)
    if path.is_absolute() or ".." in path.parts or ref.startswith("~"):
        return None
    candidate = (repo_root / path).resolve(strict=False)
    try:
        candidate.relative_to(run_dir.resolve(strict=False))
    except ValueError:
        return None
    if not candidate.is_file():
        return None
    return candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve(strict=True)
    run_id = args.run_id
    run_dir = repo_root / RUNS_REF / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    status = "pass"

    raw_snapshot = run_dir / "input/raw_snapshot.html"
    raw_hash_file = run_dir / "input/raw_snapshot.sha256"
    source_md = run_dir / "input/source.md"
    source_hash_file = run_dir / "input/source.sha256"
    metadata_path = run_dir / "input/retrieval_metadata.json"
    source_capture_path = run_dir / "input/source_capture_package.json"
    run_meta_path = run_dir / "run_meta.json"

    required = [raw_snapshot, raw_hash_file, source_md, source_hash_file, metadata_path, source_capture_path, run_meta_path]
    missing = [repo_ref(repo_root, path) for path in required if not path.is_file()]
    if missing:
        emit(checks_dir, "external_capture_metadata_validation", run_id, "fail", "missing external fixture capture files", missing=missing)
        return 1

    metadata = load_json(metadata_path)
    source_capture = load_json(source_capture_path)
    run_meta = load_json(run_meta_path)

    raw_digest = sha256(raw_snapshot)
    raw_digest_line = raw_hash_file.read_text(encoding="utf-8").strip()
    raw_ok = raw_digest_line == f"sha256:{raw_digest}  raw_snapshot.html"
    emit(checks_dir, "raw_snapshot_hash_validation", run_id, "pass" if raw_ok else "fail", "raw snapshot sha256 matches recorded hash", sha256=f"sha256:{raw_digest}", recorded=raw_digest_line)
    if not raw_ok:
        status = "fail"

    source_digest = sha256(source_md)
    source_digest_line = source_hash_file.read_text(encoding="utf-8").strip()
    source_ok = source_digest_line == f"sha256:{source_digest}  source.md"
    emit(checks_dir, "extracted_text_hash_validation", run_id, "pass" if source_ok else "fail", "extracted text sha256 matches recorded hash", sha256=f"sha256:{source_digest}", recorded=source_digest_line)
    if not source_ok:
        status = "fail"

    url = str(source_capture.get("canonical_pointer", ""))
    url_errors = external_url_safety_errors(url)
    stable_ref = str(source_capture.get("stable_representation", ""))
    stable_path = rel_file_under(repo_root, run_dir, stable_ref)
    metadata_errors: list[str] = []
    if url_errors:
        metadata_errors.extend(url_errors)
    if metadata.get("network_performed") is not False:
        metadata_errors.append("retrieval_metadata.network_performed is not false")
    if metadata.get("normalized_url") != url or metadata.get("final_url") != url:
        metadata_errors.append("metadata normalized/final URL does not match source_capture canonical_pointer")
    if metadata.get("raw_snapshot_sha256") != f"sha256:{raw_digest}":
        metadata_errors.append("metadata raw snapshot hash mismatch")
    if metadata.get("extracted_text_sha256") != f"sha256:{source_digest}":
        metadata_errors.append("metadata extracted text hash mismatch")
    if source_capture.get("stable_representation") == f"{RUNS_REF.as_posix()}/{run_id}/input/source.md":
        metadata_errors.append("stable_representation points to extracted text instead of raw snapshot")
    if stable_ref != f"{RUNS_REF.as_posix()}/{run_id}/input/raw_snapshot.html" or stable_path != raw_snapshot.resolve(strict=False):
        metadata_errors.append("stable_representation does not point to preserved raw snapshot under this run")
    if source_capture.get("hash") != f"sha256:{raw_digest}":
        metadata_errors.append("source_capture hash does not bind the raw snapshot")
    if source_capture.get("capture_method") != "manual-download":
        metadata_errors.append("fixture-backed capture_method must be manual-download")
    if not str(metadata.get("fixture_source_ref", "")).startswith("operations/harness-knowledge-pipeline/tests/fixtures/external-url/"):
        metadata_errors.append("fixture_source_ref is not under the external-url fixture surface")
    if any(run_meta.get(flag) is not False for flag in FORBIDDEN_FLAGS):
        metadata_errors.append("run_meta forbidden-surface flags are not all false")

    emit(checks_dir, "external_capture_metadata_validation", run_id, "fail" if metadata_errors else "pass", "external fixture capture metadata checked", errors=metadata_errors)
    if metadata_errors:
        status = "fail"

    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
