# Semantic Operator Handoff Contract

This document defines how a Hermes/LLM operator may fill semantic artifacts after the knowledge-pipeline runner has created a capture-only run. It is a docs/contract marker, not an automation contract.

## A. Purpose

The runner owns:

- source capture;
- evidence artifacts;
- validation checks;
- reports;
- exit codes.

A Hermes/LLM operator may fill semantic artifacts only after explicit operator instruction.

Canonical KB writes remain gated. This handoff does not admit content to canonical KB and does not authorize automatic canonical writes.

## B. Preconditions

Before semantic operator handoff begins, the run must already exist as a capture-only run with:

- `exit_code=0`;
- `input/source_capture_package.json` present;
- `input/task_packet.json` present;
- `report.md` present;
- `report.json` present.

The operator must treat the run directory as the evidence boundary for the handoff.

## C. Allowed write surface

The only allowed semantic write surface is:

```text
operations/harness-knowledge-pipeline/runs/<RUN_ID>/output/
```

No other path is in scope for semantic handoff writes.

## D. Expected semantic artifacts

The expected semantic artifacts are:

```text
normalized_note.md
normalized_note.json
result_packet.json
placement_decision.candidate.json
admission_decision.candidate.json
canonical_knowledge_candidate.md
wiki_derived_draft.md
```

These files are semantic handoff artifacts. They are not canonical KB admission.

## E. Operator rules

The Hermes/LLM operator must follow these rules:

- no external source retrieval;
- no claims beyond the captured source;
- every substantive claim must reference the source capture or source artifact;
- no canonical admission;
- no writes outside the run directory;
- no Hermes config/skills/memory/SOUL changes;
- no OpenClaw use;
- no Docker use;
- no live/apply/rollout actions.

## F. Handoff sequence

1. Runner creates a capture-only run.
2. Operator reviews input artifacts inside the run directory.
3. Operator writes semantic artifacts inside `output/`.
4. Runner is re-run, or the validation/report step is run, in `semantic-required` mode.
5. Report records `pass`, `fail`, or `awaiting_semantic_outputs`.
6. Canonical KB write remains a separate future gate.

## G. Not accepted yet

This handoff contract does not accept or implement:

- automatic semantic generation;
- external URL capture;
- canonical KB write;
- Hermes skill auto-sync.

## H. Future PRs

Likely future PRs may cover:

- semantic artifact schemas;
- semantic-required validation hardening;
- external source capture;
- synthesis layer.
