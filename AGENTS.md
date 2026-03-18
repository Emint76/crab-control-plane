# AGENTS.md

## Purpose

This repository contains the control plane for the “Краб” agent harness.
It is a governance, contracts, and architecture repository.
It is **not** a live runtime instance and must not be treated as one.

## Primary instruction

When working in this repo:

- prefer simple, audit-friendly structure
- keep documents markdown-first
- use JSON Schema where strict validation is needed
- do not invent production integrations
- do not add secrets, tokens, private URLs, or environment values
- do not collapse Notion, Obsidian, KB, and observability into one storage concept
- keep operational plane and semantic plane clearly separated
- treat this repo as versioned source of truth for control-plane artifacts only

## Layer meanings

- `control-plane/runtime/` = machine-readable templates
- `control-plane/policy/` = normative governance docs
- `control-plane/contracts/` = packet specs and schemas
- `operations/notion/` = workflow model, not canonical policy
- `knowledge/obsidian/` = semantic note conventions
- `knowledge/kb/` = sanctioned asset layout
- `observability/` = runs, evals, logging model

## Do not do

- do not write production sync code
- do not create fake autonomous self-evolution claims
- do not move live data into this repo
- do not turn Obsidian into a task tracker
- do not turn Notion into a canonical KB
- do not store secrets in markdown

## Output style

- concise and exact
- no marketing language
- explain design boundaries clearly
- use tables only where useful
- prefer placeholders with explicit TODO markers over invented specifics

## Priority files

Start by keeping these coherent:
- `docs/ARCHITECTURE.md`
- `docs/STORAGE_MODEL.md`
- `docs/DECISION_MODEL.md`
- `control-plane/policy/PLACEMENT_POLICY.md`
- `control-plane/contracts/`
- `knowledge/obsidian/OBSIDIAN_VAULT_CONVENTIONS.md`
