# ARCHITECTURE

## Purpose

This document defines the high-level architecture of the control plane for the harness "Краб".

The repository is a versioned control surface for policies, contracts, schemas, runtime templates, and scaffold execution assets. In Phase 2, the repository also contains a machine-runnable validation and render surface under `operations/harness-phase2/`.

## Core roles

| Component | Role |
|---|---|
| OpenClaw / "Краб" | Runtime orchestrator that consumes control-plane outputs |
| Codex | Formal subtask executor working against bounded contracts |
| Notion | Operational workflow plane |
| Obsidian | Semantic note plane |
| KB | Sanctioned knowledge store |
| Observability | Execution evidence, logs, evals, and reports |
| `operations/harness-phase2/` | Scaffold-only mechanical validate/apply surface |

## Architectural separation

### Control-plane repository
The repository is the source of truth for:
- architecture
- policy
- contracts and schemas
- runtime templates
- scaffold validation and render logic

### Operational plane
`operations/notion/` models mutable workflow state:
- intake
- queue movement
- review tracking
- project coordination

### Semantic plane
`knowledge/obsidian/` models semantic understanding:
- source notes
- concept notes
- comparison notes
- permanent notes

### Sanctioned asset plane
`knowledge/kb/` models sanctioned reusable assets and their layout.

### Observability plane
`observability/` models execution evidence and future reports, not runtime mutation.

## Mechanical control surface

Phase 2 introduces a scaffold-only mechanical control surface under `operations/harness-phase2/`.

This surface is machine-runnable, but intentionally narrow:
- wrong-root preflight
- contract schema validation
- policy validation
- controlled apply plan rendering
- run-scoped output rendering only

Phase 2 validates and renders only. It does not write to a live runtime instance.

## Execution flow

`task_packet -> validation -> policy checks -> scaffold decisions -> apply_plan render -> runtime-ready package render`

Execution in Phase 2 means:
1. preflight checks verify the repo shape and detect obvious wrong-root hazards
2. contract schemas and examples are validated
3. policy consistency is checked against runtime templates
4. machine-readable decisions are rendered
5. a runtime-ready output package is rendered into the run scope

A later execution owner may consume the rendered output package, but that owner is outside PR-1 and outside Phase 2 live mutation scope.

## Source of truth

| Concern | Source of truth |
|---|---|
| Architecture | `docs/` |
| Runtime templates | `control-plane/runtime/` |
| Contracts and schemas | `control-plane/contracts/` |
| Operational workflow model | `operations/notion/` |
| Phase 2 scaffold surface | `operations/harness-phase2/` |
| Semantic note conventions | `knowledge/obsidian/` |
| KB layout | `knowledge/kb/` |
| Observability model | `observability/` |

## Non-goals

- this repo is not a live runtime instance
- this repo does not store secrets, tokens, or live environment values
- Phase 2 does not perform deploy logic or runtime migration
- Phase 2 does not perform live runtime writes
- Phase 2 is not a full decision engine
- Phase 2 does not redesign Phase 3 or Phase 4 concepts

## Controlled apply model

Controlled apply in PR-1 is render-only.

Phase 2 produces:
- `validation_report.json`
- `admission_decision.json`
- `placement_decision.json`
- `apply_plan.json`
- `operations/harness-phase2/runs/<RUN_ID>/output/runtime-ready/`

The `runtime-ready/` directory under `runs/<RUN_ID>/` is a special Phase 2 render output. It is not an observability placement artifact and it is not a live runtime target.

## Future extension

This repository is intended to support later extensions such as:
- stronger validators
- richer policy checks
- more detailed render plans
- execution-owner handoff for rendered packages
- bounded evolution proposals based on observability feedback
