#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
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
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def node_type(node: dict[str, Any]) -> str:
    return str(node.get("type") or node.get("node_type") or (node.get("properties") or {}).get("node_type") or "")


def relation(edge: dict[str, Any]) -> str:
    return str(edge.get("relation") or edge.get("type") or (edge.get("properties") or {}).get("edge_type") or "")


def load_registry(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    out: dict[str, dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            ingredient_id = str(row.get("ingredient_id", ""))
            if not ingredient_id:
                raise ValueError(f"registry row without ingredient_id at line {line_no}")
            out[ingredient_id] = row
    return out


def load_sha_manifest(path: Path | None) -> dict[str, str]:
    if not path:
        return {}
    data = read_json(path)
    if isinstance(data, dict) and "formulation_sha256" in data:
        data = data["formulation_sha256"]
    return {str(k): str(v) for k, v in data.items()}


def formulation_sha_manifest(root: Path) -> dict[str, str]:
    return {str(path): sha256_path(path) for path in sorted(root.glob("*/index.md"))}


def verify(args: argparse.Namespace) -> dict[str, Any]:
    graph_path = args.graph.resolve()
    registry_path = args.registry.resolve()
    formulation_root = args.formulation_root.resolve()
    result: dict[str, Any] = {
        "status": "PASS",
        "graph_path": str(graph_path),
        "graph_sha256": None,
        "errors": [],
        "warnings": [],
        "counts": {},
        "node_counts_by_type": {},
        "link_counts_by_relation": {},
        "corpus_sha_check": {"status": "not_requested"},
    }

    def fail(code: str, detail: Any) -> None:
        result["status"] = "FAIL"
        result["errors"].append({"code": code, "detail": detail})

    if not graph_path.exists():
        fail("graph_missing", str(graph_path))
        return result
    try:
        graph = read_json(graph_path)
        result["graph_sha256"] = sha256_path(graph_path)
    except Exception as exc:
        fail("graph_json_parse_failed", str(exc))
        return result

    nodes = graph.get("nodes")
    links = graph.get("links")
    if not isinstance(nodes, list):
        fail("nodes_not_list", type(nodes).__name__)
        nodes = []
    if not isinstance(links, list):
        fail("links_not_list", type(links).__name__)
        links = []

    ids = [str(node.get("id", "")) for node in nodes]
    id_counts = Counter(ids)
    duplicate_ids = sorted(node_id for node_id, count in id_counts.items() if not node_id or count > 1)
    if duplicate_ids:
        fail("duplicate_or_empty_node_ids", duplicate_ids[:50])
    id_set = set(ids)

    dangling = []
    malformed_links = []
    for idx, edge in enumerate(links):
        source = str(edge.get("source", ""))
        target = str(edge.get("target", ""))
        rel = relation(edge)
        if not source or not target or not rel:
            malformed_links.append({"index": idx, "source": source, "target": target, "relation": rel})
            continue
        if source not in id_set or target not in id_set:
            dangling.append({"index": idx, "source": source, "target": target, "relation": rel})
    if malformed_links:
        fail("malformed_links", malformed_links[:50])
    if dangling:
        fail("dangling_links", dangling[:50])

    node_counts = Counter(node_type(node) for node in nodes)
    link_counts = Counter(relation(edge) for edge in links)
    ingredient_nodes = [node for node in nodes if node_type(node) == "Ingredient"]
    result["counts"] = {"nodes": len(nodes), "links": len(links)}
    result["node_counts_by_type"] = dict(sorted(node_counts.items()))
    result["link_counts_by_relation"] = dict(sorted(link_counts.items()))

    registry = load_registry(registry_path)
    if registry:
        graph_ingredient_ids = sorted(str(node.get("id", "")) for node in ingredient_nodes)
        registry_ids = sorted(registry)
        if graph_ingredient_ids != registry_ids:
            fail(
                "ingredient_ids_do_not_match_registry",
                {
                    "missing_from_graph": sorted(set(registry_ids) - set(graph_ingredient_ids))[:50],
                    "missing_from_registry": sorted(set(graph_ingredient_ids) - set(registry_ids))[:50],
                },
            )
        missing_reference_path = []
        mismatched_reference_path = []
        for node in ingredient_nodes:
            ingredient_id = str(node.get("id", ""))
            props = node.get("properties") or {}
            reference_path = str(props.get("reference_path", ""))
            if not reference_path:
                missing_reference_path.append(ingredient_id)
            elif ingredient_id in registry and reference_path != registry[ingredient_id].get("path"):
                mismatched_reference_path.append(
                    {
                        "ingredient_id": ingredient_id,
                        "graph_reference_path": reference_path,
                        "registry_path": registry[ingredient_id].get("path"),
                    }
                )
        if missing_reference_path:
            fail("ingredient_nodes_missing_reference_path", missing_reference_path[:50])
        if mismatched_reference_path:
            fail("ingredient_reference_path_mismatch", mismatched_reference_path[:50])
    else:
        result["warnings"].append({"code": "registry_missing", "detail": str(registry_path)})

    before = load_sha_manifest(args.formulation_sha_before)
    if before:
        current = formulation_sha_manifest(formulation_root)
        changed = sorted(path for path, old_sha in before.items() if current.get(path) != old_sha)
        missing = sorted(path for path in before if path not in current)
        added = sorted(path for path in current if path not in before)
        status = "PASS" if not changed and not missing and not added else "FAIL"
        result["corpus_sha_check"] = {
            "status": status,
            "changed": changed,
            "missing": missing,
            "added": added,
        }
        if status != "PASS":
            fail("formulation_corpus_changed", result["corpus_sha_check"])

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
