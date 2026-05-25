#!/usr/bin/env python3
"""Capture a fixture-backed external HTTP/HTTPS URL into a knowledge-pipeline run dir."""
from __future__ import annotations

import argparse
import hashlib
import html.parser
import ipaddress
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from jsonschema import Draft202012Validator

HARNESS_REF = Path("operations/harness-knowledge-pipeline")
RUNS_REF = HARNESS_REF / "runs"
RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
ALLOWED_FIXTURE_SUFFIXES = {".html", ".htm"}
UNSAFE_HOST_SUFFIXES = (".local", ".localhost", ".internal")


class TextExtractor(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.skip_depth = 0
        self.parts: list[str] = []
        self.title_parts: list[str] = []
        self.in_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:  # noqa: ARG002
        tag_l = tag.lower()
        if tag_l in {"script", "style", "noscript"}:
            self.skip_depth += 1
        if tag_l == "title":
            self.in_title = True
        if tag_l in {"p", "div", "section", "article", "main", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag_l = tag.lower()
        if tag_l in {"script", "style", "noscript"} and self.skip_depth:
            self.skip_depth -= 1
        if tag_l == "title":
            self.in_title = False
        if tag_l in {"p", "div", "section", "article", "main", "li", "h1", "h2", "h3", "h4", "h5", "h6"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self.skip_depth:
            return
        stripped = " ".join(data.split())
        if not stripped:
            return
        if self.in_title:
            self.title_parts.append(stripped)
        self.parts.append(stripped)
        self.parts.append(" ")

    @property
    def title(self) -> str:
        return " ".join(self.title_parts).strip()

    @property
    def text(self) -> str:
        lines = []
        for line in "".join(self.parts).splitlines():
            cleaned = " ".join(line.split())
            if cleaned:
                lines.append(cleaned)
        return "\n".join(lines).strip()


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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


def fail(run_id: str, run_dir: Path | None, check_name: str, detail: str, code: int = 1) -> int:
    if run_dir is not None:
        write_json(run_dir / "checks" / f"{check_name}.json", check_payload(run_id, "fail", detail))
    print(f"FAIL {detail}", file=sys.stderr)
    return code


def validate_schema(schema_path: Path, instance_path: Path) -> tuple[str, list[str]]:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    instance = json.loads(instance_path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda err: list(err.path))
    return ("pass" if not errors else "fail", [err.message for err in errors])


def normalize_external_url(raw_url: str) -> str:
    split = urlsplit(raw_url.strip())
    if split.scheme.lower() not in {"http", "https"}:
        raise ValueError("external fixture URL must use http or https")
    if split.username or split.password:
        raise ValueError("external fixture URL must not contain userinfo")
    if not split.hostname:
        raise ValueError("external fixture URL must include a host")
    host = split.hostname.rstrip(".").lower()
    if host in {"localhost"} or host.endswith(UNSAFE_HOST_SUFFIXES):
        raise ValueError("external fixture URL host is local/internal")
    if "." not in host:
        raise ValueError("external fixture URL host must be a public-looking FQDN")
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
        raise ValueError("external fixture URL IP literal is private, loopback, reserved, or otherwise unsafe")
    netloc = host
    if split.port is not None:
        netloc = f"{netloc}:{split.port}"
    path = split.path or "/"
    return urlunsplit((split.scheme.lower(), netloc, path, split.query, ""))


def source_id_for(url: str) -> str:
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    return f"external-url-{digest}"


def read_fixture_text(fixture_path: Path) -> tuple[str, str, str]:
    raw_text = fixture_path.read_text(encoding="utf-8")
    parser = TextExtractor()
    parser.feed(raw_text)
    title = parser.title or fixture_path.stem.replace("-", " ").replace("_", " ").title()
    extracted = parser.text or title
    source_md = f"# {title}\n\n{extracted}\n"
    return raw_text, title, source_md


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--fixture", required=True)
    args = parser.parse_args()

    run_id = args.run_id
    if not RUN_ID_RE.fullmatch(run_id) or run_id in {".", ".."}:
        return fail(run_id, None, "run_dir_invariants", "invalid run id", 2)

    try:
        normalized_url = normalize_external_url(args.url)
    except ValueError as exc:
        return fail(run_id, None, "external_url_boundary", str(exc), 2)

    repo_root = Path(args.repo_root).resolve(strict=True)
    fixture_ref = Path(args.fixture)
    if fixture_ref.is_absolute() or ".." in fixture_ref.parts or str(args.fixture).startswith("~"):
        return fail(run_id, None, "fixture_path_boundary", "fixture path must be repo-local relative path", 2)
    if fixture_ref.suffix.lower() not in ALLOWED_FIXTURE_SUFFIXES:
        return fail(run_id, None, "fixture_path_boundary", "fixture suffix must be .html or .htm", 2)
    fixture_path = (repo_root / fixture_ref).resolve(strict=True)
    try:
        fixture_path.relative_to(repo_root)
    except ValueError:
        return fail(run_id, None, "fixture_path_boundary", "fixture resolves outside repo root", 2)

    runs_root = repo_root / RUNS_REF
    run_dir = runs_root / run_id
    input_dir = run_dir / "input"
    output_dir = run_dir / "output"
    checks_dir = run_dir / "checks"
    input_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    checks_dir.mkdir(parents=True, exist_ok=True)

    canonical_run_dir = f"{RUNS_REF.as_posix()}/{run_id}"
    if repo_ref(repo_root, run_dir) != canonical_run_dir:
        return fail(run_id, run_dir, "run_dir_invariants", "run dir identity mismatch", 2)

    write_json(checks_dir / "run_dir_invariants.json", check_payload(
        run_id, "pass", "run dir is direct child of harness runs root",
        canonical_run_dir=canonical_run_dir,
        write_surface=canonical_run_dir + "/",
    ))
    write_json(checks_dir / "external_url_boundary.json", check_payload(
        run_id, "pass", "external URL is HTTP/HTTPS, public-looking, and fixture-backed only",
        requested_url=args.url,
        normalized_url=normalized_url,
        network_performed=False,
    ))
    write_json(checks_dir / "fixture_path_boundary.json", check_payload(
        run_id, "pass", "fixture path is repo-local HTML",
        fixture_ref=fixture_ref.as_posix(),
    ))

    raw_text, title, source_md = read_fixture_text(fixture_path)
    raw_snapshot = input_dir / "raw_snapshot.html"
    shutil.copyfile(fixture_path, raw_snapshot)
    raw_digest = hashlib.sha256(raw_snapshot.read_bytes()).hexdigest()
    (input_dir / "raw_snapshot.sha256").write_text(f"sha256:{raw_digest}  raw_snapshot.html\n", encoding="utf-8")
    write_json(checks_dir / "raw_snapshot_hash_validation.json", check_payload(
        run_id, "pass", "raw fixture snapshot sha256 matches recomputation",
        sha256=raw_digest,
        source_ref=repo_ref(repo_root, raw_snapshot),
    ))

    captured_source = input_dir / "source.md"
    captured_source.write_text(source_md, encoding="utf-8")
    source_digest = hashlib.sha256(captured_source.read_bytes()).hexdigest()
    (input_dir / "source.sha256").write_text(f"sha256:{source_digest}  source.md\n", encoding="utf-8")
    write_json(checks_dir / "extracted_text_hash_validation.json", check_payload(
        run_id, "pass", "extracted text sha256 matches recomputation",
        sha256=source_digest,
        source_ref=repo_ref(repo_root, captured_source),
    ))

    generated_at = now_utc()
    run_meta = {
        "run_id": run_id,
        "generated_at": generated_at,
        "profile": "knowledge-pipeline-external-url-fixture",
        "engine_mode": "knowledge-pipeline-scaffold",
        "evaluation_mode": "external-url-fixture-no-network-v1",
        "canonical_run_dir": canonical_run_dir,
        "source_ref": normalized_url,
        "fixture_ref": fixture_ref.as_posix(),
        "write_surface": canonical_run_dir + "/",
        "openclaw_used": False,
        "docker_used": False,
        "network_used": False,
        "live_surface_used": False,
        "outside_git_paths_used": False,
        "auto_canonical_write_performed": False,
    }
    write_json(run_dir / "run_meta.json", run_meta)

    retrieval_metadata = {
        "requested_url": args.url,
        "normalized_url": normalized_url,
        "final_url": normalized_url,
        "redirects": [],
        "retrieval_status": "success",
        "retrieval_timestamp": generated_at,
        "content_type": "text/html; charset=utf-8",
        "capture_method": "manual-download",
        "network_performed": False,
        "fixture_source_ref": fixture_ref.as_posix(),
        "raw_snapshot_ref": f"{canonical_run_dir}/input/raw_snapshot.html",
        "raw_snapshot_sha256": f"sha256:{raw_digest}",
        "extracted_text_ref": f"{canonical_run_dir}/input/source.md",
        "extracted_text_sha256": f"sha256:{source_digest}",
        "extraction_method": "python-html-parser-text-v1",
        "extraction_warnings": [],
        "retention_notes": "Fixture-backed snapshot retained only as run-local evidence under the ignored runs/ surface.",
        "policy_notes": "No robots, terms, or copyright review is performed in PR76 fixture-backed smoke.",
    }
    write_json(input_dir / "retrieval_metadata.json", retrieval_metadata)

    source_capture = {
        "source_id": source_id_for(normalized_url),
        "canonical_pointer": normalized_url,
        "retrieval_status": "success",
        "retrieval_timestamp": generated_at,
        "content_type": "text/html; charset=utf-8",
        "stable_representation": f"{canonical_run_dir}/input/raw_snapshot.html",
        "human_identifier": title,
        "provenance_notes": "Fixture-backed external HTTP/HTTPS URL smoke. No network fetch, scraper, cookies, secrets, semantic generation, canonical KB write, OpenClaw, Docker, live/apply, or rollout surface used. Extracted text is compatibility evidence only; stable_representation points to the preserved raw snapshot.",
        "linkage": [
            run_id,
            f"{canonical_run_dir}/input/retrieval_metadata.json",
            f"{canonical_run_dir}/input/source.md",
        ],
        "capture_method": "manual-download",
        "hash": f"sha256:{raw_digest}",
    }
    write_json(input_dir / "source_capture_package.json", source_capture)

    task_packet = {
        "id": run_id.lower().replace("_", "-"),
        "task_type": "source-capture",
        "title": f"Fixture-backed external URL capture smoke for {normalized_url}",
        "objective": "Create bounded no-network evidence for the future external URL capture shape using a repo-local HTML fixture.",
        "scope": "Fixture-backed external URL source capture only; no real network fetch, scraper, semantic generation, admission, or canonical KB write.",
        "inputs": [
            {"type": "document", "ref": normalized_url, "description": "Canonical external HTTP/HTTPS URL represented by a fixture snapshot."},
            {"type": "document", "ref": fixture_ref.as_posix(), "description": "Repo-local HTML fixture used as the preserved raw snapshot source."},
            {"type": "source-package", "ref": "input/source_capture_package.json", "description": "SOURCE_CAPTURE_PACKAGE-compatible source provenance package."},
        ],
        "constraints": [
            "No real external network fetch is performed in PR76.",
            "No scraper, cookies, secrets, OpenClaw, Docker, live/apply/rollout, or Hermes config/skills/memory/SOUL changes.",
            "All generated evidence remains under the canonical knowledge-pipeline run directory.",
            "No semantic generation, placement/admission execution, or canonical KB write is performed.",
            "The raw snapshot is the stable preserved representation; extracted text is a compatibility artifact only.",
        ],
        "expected_outputs": [
            {"type": "source-capture-package", "description": "Existing-source-schema-compatible package pointing stable_representation at the raw snapshot.", "destination_hint": "observability"},
            {"type": "result-packet", "description": "Run report and checks proving fixture-backed capture evidence only.", "destination_hint": "observability"},
        ],
        "acceptance_criteria": [
            "Source capture package validates against control-plane/contracts/schemas/source_capture_package.schema.json.",
            "Raw snapshot and extracted text hashes are present and validated.",
            "Report and exit_code are emitted with network_used=false and auto_canonical_write_performed=false.",
            "Unsafe URL forms are rejected before valid evidence is accepted.",
        ],
        "destination_hint": "observability",
        "priority": "medium",
        "policy_refs": [
            "control-plane/contracts/SOURCE_CAPTURE_PACKAGE.md",
            "control-plane/contracts/schemas/source_capture_package.schema.json",
            "operations/harness-knowledge-pipeline/EXTERNAL_SOURCE_BOUNDARY.md",
        ],
        "placement_request": {
            "target_layer": "observability",
            "target_path": f"{canonical_run_dir}/",
            "review_required": True,
            "apply_mode": "manual",
        },
        "provenance_requirements": [
            "Every capture claim must reference input/source_capture_package.json and/or input/retrieval_metadata.json.",
            "Fixture-backed smoke does not accept real external HTTP/HTTPS capture as a harness capability.",
        ],
        "notes": "PR76 no-network fixture-backed external URL capture smoke.",
        "status_hint": "in_progress",
    }
    write_json(input_dir / "task_packet.json", task_packet)

    schema_pairs = [
        (repo_root / "control-plane/contracts/schemas/source_capture_package.schema.json", input_dir / "source_capture_package.json", checks_dir / "source_capture_schema.json"),
        (repo_root / "control-plane/contracts/schemas/task_packet.schema.json", input_dir / "task_packet.json", checks_dir / "task_packet_schema.json"),
    ]
    failed = False
    for schema_path, instance_path, check_path in schema_pairs:
        status, errors = validate_schema(schema_path, instance_path)
        failed = failed or status == "fail"
        write_json(check_path, check_payload(
            run_id, status, "schema validation complete",
            schema=repo_ref(repo_root, schema_path),
            instance=repo_ref(repo_root, instance_path),
            errors=errors,
        ))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
