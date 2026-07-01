---
name: graphify-kb
description: "Operate the Humblebee KB Graphify graph: rebuild, verify graph.json, validate builder output, MCP smoke-check, and preserve evidence."
---

# Graphify KB Operations

Use this skill before any Graphify build, rebuild, validation, builder modification,
active graph replacement, MCP graph check, or corpus/reference change that affects
the Humblebee Formulation graph.

This skill is operational only. It must not normalize ingredients, merge or split
entities, change canonical labels, create reference entities, decide aliases, extract
new entities, edit Formulation/reference data, use LLMs for graph data changes, or
manually edit `graph.json`.

## Canonical Paths

- Corpus: `/home/node/.openclaw/workspace/kb/cosmetics-household-chemistry`
- Formulations: `/home/node/.openclaw/workspace/kb/cosmetics-household-chemistry/humblebee-and-me/knowledge/formulations`
- Ingredient registry: `/home/node/.openclaw/workspace/kb/cosmetics-household-chemistry/reference/ingredients/registry.jsonl`
- Graph project: `/home/node/.openclaw/workspace/graphify-pilots/humblebee-formulations-v1`
- Builder: `/home/node/.openclaw/workspace/graphify-pilots/humblebee-formulations-v1/scripts/build_humblebee_formulation_graph.py`
- Active graph: `/home/node/.openclaw/workspace/graphify-pilots/humblebee-formulations-v1/output/graph.json`

## Workflow

1. Run preflight.
2. Snapshot current active graph/output before any active replacement.
3. Rebuild a candidate with the existing builder. Do not duplicate builder logic.
4. Verify candidate structure and invariants.
5. Compare old/new stats and Ingredient IDs.
6. Replace active graph/output only after verification passes.
7. Smoke-check MCP with `humblebee-knowledge-graph.graph_stats`.
8. Report evidence paths, old/new stats, SHA, MCP status, and whether corpus changed during rebuild.

Fail closed: if any gate fails, do not replace the active graph.

## Invariants

Verify at minimum:

- `graph.json` parses as JSON.
- Node IDs are unique.
- Links have `source`, `target`, and relation/type.
- Every link endpoint exists.
- Counts are recorded by node type and relation.
- Ingredient IDs match `reference/ingredients/registry.jsonl` when the registry exists.
- Every Ingredient node has `properties.reference_path` when registry-backed reference layer is active.
- Formulation asset SHA values are unchanged during rebuild.
- Old/new stats and graph SHA are saved.
- Repeat rebuild is deterministic, or any difference is explained as a technical build parameter issue.

Current Humblebee graph baseline after Ingredient reference materialization:

- Formulation nodes: 137
- Ingredient nodes: 316
- Source nodes: 127
- USES links: 1263
- DERIVED_FROM links: 137
- Total nodes: 580
- Total links: 1400

## Scripts

Run from anywhere:

```bash
python3 /home/node/.openclaw/workspace/skills/graphify-kb/scripts/verify_graph.py
```

`verify_graph.py` checks structure, IDs, dangling links, counts, registry alignment,
Ingredient `reference_path`, and optional corpus SHA stability. It never fixes data.

```bash
python3 /home/node/.openclaw/workspace/skills/graphify-kb/scripts/rebuild_graph.py --check
python3 /home/node/.openclaw/workspace/skills/graphify-kb/scripts/rebuild_graph.py --dry-run
python3 /home/node/.openclaw/workspace/skills/graphify-kb/scripts/rebuild_graph.py --apply
```

`rebuild_graph.py` orchestrates the existing builder only. It writes evidence under:

- `/home/node/.openclaw/workspace/graphify-pilots/humblebee-formulations-v1/runs/graphify-kb-<timestamp>/`
- `/home/node/.openclaw/workspace/graphify-pilots/humblebee-formulations-v1/snapshots/graphify-kb-<timestamp>/`

Evidence files:

- `preflight.json`
- `old-stats.json`
- `new-stats.json`
- `comparison.json`
- `verification.json`
- `changed-files.txt`
- `manifest.json`
- `REPORT.md`

## MCP Check

After `--apply`, call MCP `humblebee-knowledge-graph.graph_stats` and verify it
sees the new active graph. Record the observed MCP stats in the final chat summary
or in follow-up run evidence if the task requires a persistent MCP proof.

Read-only graph queries that only inspect existing MCP graph data do not need this
skill unless the task also asks for rebuild, validation, builder changes, active
graph replacement, or graph-affecting corpus/reference mutation.
