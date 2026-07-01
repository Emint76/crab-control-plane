#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


WORKSPACE = Path("/home/node/.openclaw/workspace")
CORPUS = WORKSPACE / "kb/cosmetics-household-chemistry"
FORMULATIONS = CORPUS / "humblebee-and-me/knowledge/formulations"
REGISTRY = CORPUS / "reference/ingredients/registry.jsonl"
PILOT = WORKSPACE / "graphify-pilots/humblebee-formulations-v1"
BUILDER = PILOT / "scripts/build_humblebee_formulation_graph.py"
ACTIVE_OUTPUT = PILOT / "output"
ACTIVE_GRAPH = ACTIVE_OUTPUT / "graph.json"
GRAPHIFY_PY = WORKSPACE / ".local-tools/uv-tools/graphifyy/bin/python"
VERIFY_SCRIPT = Path(__file__).resolve().parent / "verify_graph.py"

OUTPUT_FILES = [
    "GRAPH_REPORT.md",
    "_deterministic_model.json",
    "determinism.json",
    "graph.json",
    "graph.product_type.vis.html",
    "graph.stats.json",
    "input_manifest.json",
    "parse-validation.json",
]


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def node_type(node: dict[str, Any]) -> str:
    return str(node.get("type") or node.get("node_type") or (node.get("properties") or {}).get("node_type") or "")


def relation(edge: dict[str, Any]) -> str:
    return str(edge.get("relation") or edge.get("type") or (edge.get("properties") or {}).get("edge_type") or "")


def graph_stats(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"exists": False}
    graph = read_json(path)
    nodes = graph.get("nodes", [])
    links = graph.get("links", [])
    return {
        "exists": True,
        "sha256": sha256_path(path),
        "nodes": len(nodes),
        "links": len(links),
        "node_counts_by_type": dict(sorted(Counter(node_type(node) for node in nodes).items())),
        "link_counts_by_relation": dict(sorted(Counter(relation(edge) for edge in links).items())),
        "ingredient_ids": sorted(str(node.get("id", "")) for node in nodes if node_type(node) == "Ingredient"),
    }


def formulation_sha_manifest() -> dict[str, str]:
    return {str(path): sha256_path(path) for path in sorted(FORMULATIONS.glob("*/index.md"))}


def snapshot_active(snapshot_dir: Path) -> None:
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    for name in OUTPUT_FILES:
        src = ACTIVE_OUTPUT / name
        if src.exists():
            shutil.copy2(src, snapshot_dir / name)


def active_output_sha() -> dict[str, str]:
    return {name: sha256_path(ACTIVE_OUTPUT / name) for name in OUTPUT_FILES if (ACTIVE_OUTPUT / name).exists()}


def run_builder(candidate_output: Path, run_dir: Path) -> dict[str, Any]:
    py = GRAPHIFY_PY if GRAPHIFY_PY.exists() else Path(sys.executable)
    command = [
        str(py),
        str(BUILDER),
        "--formulation-root",
        str(FORMULATIONS),
        "--pilot-root",
        str(PILOT),
        "--output-dir",
        str(candidate_output),
    ]
    proc = subprocess.run(command, text=True, capture_output=True)
    (run_dir / "builder.stdout").write_text(proc.stdout, encoding="utf-8")
    (run_dir / "builder.stderr").write_text(proc.stderr, encoding="utf-8")
    return {"command": command, "returncode": proc.returncode}


def run_verify(graph: Path, sha_before_path: Path | None, out_path: Path) -> dict[str, Any]:
    command = [
        sys.executable,
        str(VERIFY_SCRIPT),
        "--graph",
        str(graph),
        "--registry",
        str(REGISTRY),
        "--formulation-root",
        str(FORMULATIONS),
        "--out",
        str(out_path),
    ]
    if sha_before_path:
        command.extend(["--formulation-sha-before", str(sha_before_path)])
    proc = subprocess.run(command, text=True, capture_output=True)
    if proc.stdout:
        (out_path.parent / "verify.stdout").write_text(proc.stdout, encoding="utf-8")
    if proc.stderr:
        (out_path.parent / "verify.stderr").write_text(proc.stderr, encoding="utf-8")
    if out_path.exists():
        data = read_json(out_path)
    else:
        data = {"status": "FAIL", "errors": [{"code": "verify_output_missing"}]}
    data["command"] = command
    data["returncode"] = proc.returncode
    return data


def compare(old: dict[str, Any], new: dict[str, Any]) -> dict[str, Any]:
    old_ids = old.get("ingredient_ids", [])
    new_ids = new.get("ingredient_ids", [])
    return {
        "old": {k: v for k, v in old.items() if k != "ingredient_ids"},
        "new": {k: v for k, v in new.items() if k != "ingredient_ids"},
        "ingredient_ids_unchanged": old_ids == new_ids,
        "ingredient_ids_removed": sorted(set(old_ids) - set(new_ids)),
        "ingredient_ids_added": sorted(set(new_ids) - set(old_ids)),
    }


def commit_candidate(candidate_output: Path) -> list[str]:
    changed = []
    for name in OUTPUT_FILES:
        src = candidate_output / name
        if not src.exists():
            continue
        dst = ACTIVE_OUTPUT / name
        old_sha = sha256_path(dst) if dst.exists() else None
        new_sha = sha256_path(src)
        if old_sha != new_sha:
            shutil.copy2(src, dst)
            changed.append(str(dst))
    return changed


def write_report(path: Path, mode: str, status: str, run_dir: Path, comparison: dict[str, Any], verification: dict[str, Any]) -> None:
    lines = [
        "# Graphify KB Rebuild",
        "",
        f"- mode: {mode}",
        f"- status: {status}",
        f"- run: {run_dir}",
        f"- old graph SHA: {comparison.get('old', {}).get('sha256')}",
        f"- new graph SHA: {comparison.get('new', {}).get('sha256')}",
        f"- ingredient IDs unchanged: {comparison.get('ingredient_ids_unchanged')}",
        f"- verification: {verification.get('status')}",
        "",
        "## Old Stats",
        "",
        "```json",
        json.dumps(comparison.get("old", {}), ensure_ascii=False, indent=2, sort_keys=True),
        "```",
        "",
        "## New Stats",
        "",
        "```json",
        json.dumps(comparison.get("new", {}), ensure_ascii=False, indent=2, sort_keys=True),
        "```",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    mode = "check" if args.check else "dry-run" if args.dry_run else "apply"
    timestamp = datetime.now(timezone.utc).strftime("graphify-kb-%Y%m%dT%H%M%SZ")
    run_dir = PILOT / "runs" / timestamp
    snapshot_dir = PILOT / "snapshots" / timestamp
    candidate_output = run_dir / "candidate-output"
    run_dir.mkdir(parents=True, exist_ok=False)

    old_stats = graph_stats(ACTIVE_GRAPH)
    before_shas = formulation_sha_manifest()
    before_sha_path = run_dir / "formulation-sha-before.json"
    write_json(before_sha_path, before_shas)
    preflight = {
        "mode": mode,
        "builder": str(BUILDER),
        "builder_exists": BUILDER.exists(),
        "graphify_python": str(GRAPHIFY_PY) if GRAPHIFY_PY.exists() else sys.executable,
        "active_graph": str(ACTIVE_GRAPH),
        "active_graph_exists": ACTIVE_GRAPH.exists(),
        "registry": str(REGISTRY),
        "registry_exists": REGISTRY.exists(),
        "formulation_files": len(before_shas),
    }
    write_json(run_dir / "preflight.json", preflight)
    write_json(run_dir / "old-stats.json", old_stats)

    if not BUILDER.exists() or not ACTIVE_GRAPH.exists() or not REGISTRY.exists():
        verification = {"status": "FAIL", "errors": [{"code": "preflight_failed", "detail": preflight}]}
        comparison = compare(old_stats, old_stats)
        write_json(run_dir / "new-stats.json", old_stats)
        write_json(run_dir / "comparison.json", comparison)
        write_json(run_dir / "verification.json", verification)
        write_report(run_dir / "REPORT.md", mode, "FAIL", run_dir, comparison, verification)
        write_json(run_dir / "manifest.json", {"status": "FAIL", "run_dir": str(run_dir), "snapshot_dir": None})
        print(json.dumps({"status": "FAIL", "run_dir": str(run_dir), "preflight": preflight}, ensure_ascii=False, indent=2))
        return 2

    if args.check:
        verification = run_verify(ACTIVE_GRAPH, None, run_dir / "verification.json")
        comparison = compare(old_stats, old_stats)
        write_json(run_dir / "new-stats.json", old_stats)
        write_json(run_dir / "comparison.json", comparison)
        status = "PASS" if verification.get("status") == "PASS" else "FAIL"
        write_report(run_dir / "REPORT.md", mode, status, run_dir, comparison, verification)
        write_json(run_dir / "manifest.json", {"status": status, "run_dir": str(run_dir), "snapshot_dir": None, "active_output_sha": active_output_sha()})
        print(json.dumps({"status": status, "mode": mode, "run_dir": str(run_dir), "verification": verification}, ensure_ascii=False, indent=2))
        return 0 if status == "PASS" else 2

    snapshot_active(snapshot_dir)
    builder = run_builder(candidate_output, run_dir)
    if builder["returncode"] != 0 or not (candidate_output / "graph.json").exists():
        verification = {"status": "FAIL", "errors": [{"code": "builder_failed", "detail": builder}]}
        new_stats = graph_stats(candidate_output / "graph.json")
        comparison = compare(old_stats, new_stats)
        write_json(run_dir / "new-stats.json", new_stats)
        write_json(run_dir / "comparison.json", comparison)
        write_json(run_dir / "verification.json", verification)
        write_report(run_dir / "REPORT.md", mode, "FAIL", run_dir, comparison, verification)
        write_json(run_dir / "manifest.json", {"status": "FAIL", "run_dir": str(run_dir), "snapshot_dir": str(snapshot_dir), "builder": builder})
        print(json.dumps({"status": "FAIL", "mode": mode, "run_dir": str(run_dir), "builder": builder}, ensure_ascii=False, indent=2))
        return 2

    new_stats = graph_stats(candidate_output / "graph.json")
    verification = run_verify(candidate_output / "graph.json", before_sha_path, run_dir / "verification.json")
    comparison = compare(old_stats, new_stats)
    if not comparison["ingredient_ids_unchanged"]:
        verification["status"] = "FAIL"
        verification.setdefault("errors", []).append({"code": "ingredient_ids_changed", "detail": comparison})
    status = "PASS" if verification.get("status") == "PASS" else "FAIL"

    changed_files: list[str] = []
    if args.apply and status == "PASS":
        changed_files = commit_candidate(candidate_output)
    elif args.apply and status != "PASS":
        changed_files = []

    (run_dir / "changed-files.txt").write_text("\n".join(changed_files) + ("\n" if changed_files else ""), encoding="utf-8")
    write_json(run_dir / "new-stats.json", new_stats)
    write_json(run_dir / "comparison.json", comparison)
    write_json(run_dir / "verification.json", verification)
    write_report(run_dir / "REPORT.md", mode, status, run_dir, comparison, verification)
    manifest = {
        "status": status,
        "mode": mode,
        "run_dir": str(run_dir),
        "snapshot_dir": str(snapshot_dir),
        "candidate_output": str(candidate_output),
        "builder": builder,
        "changed_files": changed_files,
        "active_replaced": bool(args.apply and status == "PASS"),
        "active_output_sha_after": active_output_sha() if args.apply and status == "PASS" else None,
    }
    write_json(run_dir / "manifest.json", manifest)
    print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
