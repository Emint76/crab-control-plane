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
| `operations/harness-phase2/` | Phase 2 strict check-layer and repo-native scaffold surfaces |
| `operations/harness-phase3/` | Phase 3 repo-native canonical execution owner surface |
| `operations/harness-phase4/` | Phase 4 thin wrapper over Phase 3 |

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

## Phase 2 profiles

Phase 2 contains two explicit profiles:
- check-layer-strict: strict external check layer, closest repo-native equivalent of the earlier VPS Phase 2 harness.
- repo-native-scaffold: broader repo-native scaffold that validates, renders decision artifacts, renders runtime-ready package, runs conformance, emits reports, and produces handoff readiness.

The strict check-layer profile performs external checks only. It does not render decision artifacts, `runtime-ready/`, reports, or handoff readiness.

The repo-native scaffold profile validates and renders only. It does not write to a live runtime instance.

## Execution flow

`task_packet -> validation -> policy checks -> scaffold decisions -> apply_plan render -> runtime-ready package render`

Execution in the Phase 2 repo-native scaffold profile means:
1. preflight checks verify the repo shape and detect obvious wrong-root hazards
2. contract schemas and examples are validated
3. policy consistency is checked against runtime templates
4. machine-readable decisions are rendered
5. a runtime-ready output package is rendered into the run scope

Phase 3 consumes the rendered output package inside the repo-native harness boundary, but that remains outside Phase 2 live mutation scope.

## Phase 3 role

Phase 3 is the repo-native canonical execution owner.

Canonical execution ownership means:
- Phase 3 owns the canonical execution run directory.
- Phase 3 owns execution evidence, logs, checks, reports, timestamps, and final exit status.
- Phase 3 consumes Phase 2 handoff/runtime-ready package as upstream input.
- Phase 3 must not be bypassed by Phase 4.
- Phase 3 must not write live runtime state unless explicitly allowed by a later contract.

## Phase 4 role

Phase 4 is the thin wrapper over Phase 3.

It packages operator invocation, runs wrapper preflight checks, and calls Phase 3, but it must not own canonical execution outputs.

## Source of truth

| Concern | Source of truth |
|---|---|
| Architecture | `docs/` |
| Runtime templates | `control-plane/runtime/` |
| Contracts and schemas | `control-plane/contracts/` |
| Operational workflow model | `operations/notion/` |
| Phase 2 strict/scaffold surfaces | `operations/harness-phase2/` |
| Phase 3 execution surface | `operations/harness-phase3/` |
| Phase 4 wrapper surface | `operations/harness-phase4/` |
| Semantic note conventions | `knowledge/obsidian/` |
| KB layout | `knowledge/kb/` |
| Observability model | `observability/` |

## Non-goals

- this repo is not a live runtime instance
- this repo does not store secrets, tokens, or live environment values
- Phase 2 does not perform deploy logic or runtime migration
- Phase 2 does not perform live runtime writes
- Phase 2 is not a full decision engine
- Phase 3 is not a live runtime deployment or migration engine
- Phase 4 is not a canonical execution owner

## Controlled apply model

Controlled apply in the Phase 2 repo-native scaffold profile is render-only.

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
- bounded wrapper and operator-invocation refinements
- bounded evolution proposals based on observability feedback
