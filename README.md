# crab-control-plane

Versioned control plane for the “Краб” agent harness.

This repository is **not** the live runtime instance of Гоша and is **not** a dump of the existing OpenClaw installation.
It is the governing layer above the system: architecture docs, policies, contracts, schemas, templates, and storage discipline.

## Purpose

This repo defines how the system should be structured across six layers:

1. **runtime** — machine-readable configuration templates
2. **policy** — normative markdown documents
3. **contracts** — structured packet specs and schemas
4. **operations** — Notion workflow model
5. **knowledge** — Obsidian semantic plane and KB layout
6. **observability** — logs, evals, reports, future evolution baseline

## Source of truth by data class

| Data class | Source of truth |
|---|---|
| Runtime templates | `control-plane/runtime/` |
| Policy docs | `control-plane/policy/` |
| Contracts and schemas | `control-plane/contracts/` |
| Operational workflow model | `operations/notion/` |
| Semantic note conventions | `knowledge/obsidian/` |
| KB layout and admission discipline | `knowledge/kb/` + policy docs |
| Observability model | `observability/` |

## Current executable surfaces

| Surface | Entrypoint | Status |
|---|---|---|
| Phase 2 strict check layer | `operations/harness-phase2/bin/run_phase2_check_layer.sh` | external check layer; no render, no runtime-ready, no handoff |
| Phase 2 repo-native scaffold | `operations/harness-phase2/bin/run_phase2_bundle.sh` | validates, renders scaffold decisions, runtime-ready package, conformance, report, handoff readiness |
| Phase 3 execution surface | `operations/harness-phase3/bin/run_phase3_bundle.sh` | target surface to be hardened into canonical execution owner |
| Phase 4 wrapper | not yet implemented here | future thin wrapper over Phase 3 only |

Phase 2 is upstream check/render/handoff preparation. It does not perform live runtime execution.

Phase 3 is the planned canonical execution owner surface. Its next hardening work must focus on canonical run evidence, execution ownership, fail-closed behavior, and CI.

Phase 4 must not own canonical execution outputs. It should remain a thin wrapper over Phase 3.

## What belongs elsewhere

- Live runtime state does **not** belong here
- Secrets and tokens do **not** belong here
- Notion board contents do **not** belong here
- Full knowledge corpus does **not** belong here unless explicitly curated as examples

## Recommended next steps

1. Keep Phase 2 strict/scaffold profiles green in CI.
2. Harden Phase 3 into the canonical execution owner.
3. Add dedicated Phase 3 CI.
4. Define Phase 4 only as a thin wrapper over Phase 3.
5. Continue to keep live runtime state, secrets, and instance-specific config out of this repo.
