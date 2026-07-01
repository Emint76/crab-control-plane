#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


WORKSPACE = Path("/home/node/.openclaw/workspace")
CORPUS = WORKSPACE / "kb/cosmetics-household-chemistry"
FORMULATIONS = CORPUS / "humblebee-and-me/knowledge/formulations"
REGISTRY = CORPUS / "reference/ingredients/registry.jsonl"
GRAPH = WORKSPACE / "graphify-pilots/humblebee-formulations-v1/output/graph.json"


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def node_type(node: dict[str, Any]) -> str:
    return str(node.get("type") or node.get("node_type") or (node.get("properties") or {}).get("node_type") or "")


def relation(edge: dict[str, Any]) -> str:
    return str(edge.get("relation") or edge.get("type") or (edge.get("properties") or {}).get("edge_type") or "")


def load_registry(path: Path) -> dict[str, dict[str, Any]]:
    if not path.is_file():
        raise ValueError(f"registry missing: {path}")
    rows: dict[str, dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"malformed registry JSONL at line {line_no}: {exc}") from exc
            if not isinstance(row, dict):
                raise ValueError(f"registry row is not an object at line {line_no}")
            ingredient_id = row.get("ingredient_id")
            if not isinstance(ingredient_id, str) or not ingredient_id.strip():
                raise ValueError(f"registry row without ingredient_id at line {line_no}")
            ingredient_id = ingredient_id.strip()
            if ingredient_id in rows:
                raise ValueError(f"duplicate registry ingredient_id {ingredient_id!r} at line {line_no}")
            rows[ingredient_id] = row
    return rows


def split_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}
    metadata: dict[str, str] = {}
    for line in text[4:end].splitlines():
        match = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if match:
            value = match.group(2).strip()
            if len(value) >= 2 and value[0] == value[-1] == '"':
                value = value[1:-1]
            metadata[match.group(1)] = value
    return metadata


def composition_rows(text: str) -> list[dict[str, str]]:
    match = re.search(r"^## Composition\s*$", text, re.MULTILINE)
    if not match:
        return []
    remainder = text[match.end():]
    next_heading = re.search(r"^## .+$", remainder, re.MULTILINE)
    section = remainder[:next_heading.start()] if next_heading else remainder
    lines = [line.strip() for line in section.splitlines() if line.strip().startswith("|") and line.strip().endswith("|")]
    if len(lines) < 2:
        return []
    header = [cell.strip() for cell in lines[0].strip("|").split("|")]
    rows: list[dict[str, str]] = []
    for line in lines[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != len(header):
            continue
        rows.append(dict(zip(header, cells)))
    return rows


def derive_expected_counts(formulation_root: Path, registry: dict[str, dict[str, Any]]) -> dict[str, Any]:
    admitted: list[tuple[Path, dict[str, str], list[dict[str, str]]]] = []
    for path in sorted(formulation_root.glob("*/index.md")):
        text = path.read_text(encoding="utf-8")
        metadata = split_frontmatter(text)
        if (
            metadata.get("knowledge_type") == "formulations"
            and metadata.get("review_status") == "approved"
            and metadata.get("knowledge_profile_id") == "source_to_formulation.v1"
        ):
            admitted.append((path, metadata, composition_rows(text)))

    source_ids = {metadata.get("source_id", "").strip() for _, metadata, _ in admitted}
    if "" in source_ids:
        raise ValueError("admitted Formulation asset missing source_id")
    uses = 0
    invalid_refs: list[dict[str, str]] = []
    for path, _, rows in admitted:
        for row in rows:
            ingredient_ref = row.get("ingredient_ref", "").strip()
            if ingredient_ref and ingredient_ref in registry:
                uses += 1
            else:
                invalid_refs.append({"path": str(path), "ingredient_ref": ingredient_ref})
    if invalid_refs:
        raise ValueError(f"Composition rows with invalid ingredient_ref: {invalid_refs[:20]}")

    node_counts = {
        "Formulation": len(admitted),
        "Ingredient": len(registry),
        "Source": len(source_ids),
    }
    link_counts = {"DERIVED_FROM": len(admitted), "USES": uses}
    return {
        "nodes": sum(node_counts.values()),
        "links": sum(link_counts.values()),
        "node_counts_by_type": node_counts,
        "link_counts_by_relation": link_counts,
    }


def load_sha_manifest(path: Path | None) -> dict[str, str]:
    if not path:
        return {}
    data = read_json(path)
    if isinstance(data, dict) and "formulation_sha256" in data:
        data = data["formulation_sha256"]
    if not isinstance(data, dict):
        raise ValueError("formulation SHA manifest must be an object")
    return {str(key): str(value) for key, value in data.items()}


def formulation_sha_manifest(root: Path) -> dict[str, str]:
    return {str(path): sha256_path(path) for path in sorted(root.glob("*/index.md"))}


def verify(args: argparse.Namespace) -> dict[str, Any]:
    graph_path = args.graph.resolve()
    registry_path = args.registry.resolve()
    formulation_root = args.formulation_root.resolve()
    result: dict[str, Any] = {
        "status": "PASS", "graph_path": str(graph_path), "graph_sha256": None,
        "errors": [], "warnings": [], "counts": {}, "expected_counts": {},
        "node_counts_by_type": {}, "link_counts_by_relation": {},
        "corpus_sha_check": {"status": "not_requested"},
    }

    def fail(code: str, detail: Any) -> None:
        result["status"] = "FAIL"
        result["errors"].append({"code": code, "detail": detail})

    if not graph_path.is_file():
        fail("graph_missing", str(graph_path))
        return result
    try:
        graph = read_json(graph_path)
        result["graph_sha256"] = sha256_path(graph_path)
    except Exception as exc:
        fail("graph_json_parse_failed", str(exc))
        return result
    if not isinstance(graph, dict):
        fail("graph_not_object", type(graph).__name__)
        return result

    nodes = graph.get("nodes")
    links = graph.get("links")
    if not isinstance(nodes, list):
        fail("nodes_not_list", type(nodes).__name__)
        nodes = []
    if not isinstance(links, list):
        fail("links_not_list", type(links).__name__)
        links = []

    ids = [str(node.get("id", "")) for node in nodes if isinstance(node, dict)]
    duplicate_ids = sorted(node_id for node_id, count in Counter(ids).items() if not node_id or count > 1)
    if len(ids) != len(nodes) or duplicate_ids:
        fail("duplicate_or_empty_node_ids", duplicate_ids)
    id_set = set(ids)
    malformed_links, dangling = [], []
    for index, edge in enumerate(links):
        if not isinstance(edge, dict):
            malformed_links.append({"index": index, "type": type(edge).__name__})
            continue
        source, target, rel = str(edge.get("source", "")), str(edge.get("target", "")), relation(edge)
        if not source or not target or not rel:
            malformed_links.append({"index": index, "source": source, "target": target, "relation": rel})
        elif source not in id_set or target not in id_set:
            dangling.append({"index": index, "source": source, "target": target, "relation": rel})
    if malformed_links:
        fail("malformed_links", malformed_links[:50])
    if dangling:
        fail("dangling_links", dangling[:50])

    node_counts = Counter(node_type(node) for node in nodes if isinstance(node, dict))
    link_counts = Counter(relation(edge) for edge in links if isinstance(edge, dict))
    result["counts"] = {"nodes": len(nodes), "links": len(links)}
    result["node_counts_by_type"] = dict(sorted(node_counts.items()))
    result["link_counts_by_relation"] = dict(sorted(link_counts.items()))

    try:
        registry = load_registry(registry_path)
    except Exception as exc:
        fail("registry_invalid", str(exc))
        registry = {}
    try:
        expected = derive_expected_counts(formulation_root, registry)
        result["expected_counts"] = expected
        actual = {
            "nodes": len(nodes), "links": len(links),
            "node_counts_by_type": dict(sorted(node_counts.items())),
            "link_counts_by_relation": dict(sorted(link_counts.items())),
        }
        if actual != expected:
            fail("graph_count_mismatch", {"expected": expected, "actual": actual})
    except Exception as exc:
        fail("expected_counts_invalid", str(exc))

    if registry:
        ingredient_nodes = [node for node in nodes if isinstance(node, dict) and node_type(node) == "Ingredient"]
        graph_ids = sorted(str(node.get("id", "")) for node in ingredient_nodes)
        if graph_ids != sorted(registry):
            fail("ingredient_ids_do_not_match_registry", {
                "missing_from_graph": sorted(set(registry) - set(graph_ids))[:50],
                "missing_from_registry": sorted(set(graph_ids) - set(registry))[:50],
            })
        missing_paths, mismatched_paths = [], []
        for node in ingredient_nodes:
            ingredient_id = str(node.get("id", ""))
            reference_path = str((node.get("properties") or {}).get("reference_path", ""))
            if not reference_path:
                missing_paths.append(ingredient_id)
            elif ingredient_id in registry and reference_path != registry[ingredient_id].get("path"):
                mismatched_paths.append({"ingredient_id": ingredient_id, "graph": reference_path, "registry": registry[ingredient_id].get("path")})
        if missing_paths:
            fail("ingredient_nodes_missing_reference_path", missing_paths[:50])
        if mismatched_paths:
            fail("ingredient_reference_path_mismatch", mismatched_paths[:50])

    try:
        before = load_sha_manifest(args.formulation_sha_before)
        if before:
            current = formulation_sha_manifest(formulation_root)
            changed = sorted(path for path, old_sha in before.items() if current.get(path) != old_sha)
            missing = sorted(path for path in before if path not in current)
            added = sorted(path for path in current if path not in before)
            status = "PASS" if not changed and not missing and not added else "FAIL"
            result["corpus_sha_check"] = {"status": status, "changed": changed, "missing": missing, "added": added}
            if status != "PASS":
                fail("formulation_corpus_changed", result["corpus_sha_check"])
    except Exception as exc:
        fail("formulation_sha_manifest_invalid", str(exc))
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--graph", type=Path, default=GRAPH)
    parser.add_argument("--registry", type=Path, default=REGISTRY)
    parser.add_argument("--formulation-root", type=Path, default=FORMULATIONS)
    parser.add_argument("--formulation-sha-before", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    result = verify(args)
    text = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if result["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
