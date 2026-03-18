# ARCHITECTURE

## Purpose

This document defines the high-level architecture of the control plane for the “Краб” harness.

## Core roles

| Component | Role |
|---|---|
| OpenClaw / Краб | Runtime orchestrator |
| Codex | Formal subtask executor |
| Notion | Operational plane |
| Obsidian | Semantic knowledge plane |
| KB | Sanctioned knowledge store |
| Observability | Logs, evals, reports, future evolution baseline |

## Architectural separation

### Operational plane
Tracks work movement:
- intake
- queues
- statuses
- handoffs
- review tracking

### Semantic plane
Tracks meaning:
- permanent notes
- source notes
- concept notes
- comparison notes
- durable links and semantic graph

## Non-goals

- this repo is not the runtime instance
- this repo is not the full knowledge corpus
- this repo is not a replacement for Notion or Obsidian
- this repo does not contain secrets

## Future extension

This repository is intended to become the policy surface that later governs:
- subtask delegation
- placement discipline
- runtime templates
- observability baseline
- external evolution loop
