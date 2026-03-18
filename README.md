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

## What belongs elsewhere

- Live runtime state does **not** belong here
- Secrets and tokens do **not** belong here
- Notion board contents do **not** belong here
- Full knowledge corpus does **not** belong here unless explicitly curated as examples

## Recommended next steps

1. Commit this starter structure
2. Connect Codex to this repo
3. Give Codex the control-plane assembly prompt
4. Review Codex output before applying any ideas to the live Гоша instance
