# KNOWLEDGE_PIPELINE_CONTRACT

## Purpose

This harness adapts the existing crab-control-plane knowledge contracts into a first working Hermes Knowledge Pipeline run without creating a Hermes self-improvement contour.

## Scope

Supported source input for the first implementation:

```text
repo-local .md/.markdown/.txt file only
```

First source:

```text
control-plane/policy/ADMISSION_POLICY.md
```

Canonical run surface:

```text
operations/harness-knowledge-pipeline/runs/<RUN_ID>/
```

## Layer model

```text
source material
→ source capture / evidence
→ normalized note
→ result packet
→ placement / admission candidate
→ canonical knowledge candidate
→ wiki-derived draft
```

## Ownership rules

- Scripts own source capture, hashes, schema validation, ref validation, layer boundaries, report rendering, and exit codes.
- LLM/Hermes may create semantic outputs only inside the run directory.
- LLM/Hermes does not write admitted canonical assets.
- Admission candidates are not automatic canonical admission.
- Wiki-derived drafts must derive from canonical candidate material, not directly from raw source.

## Forbidden surfaces

- OpenClaw
- Docker
- Hermes config/skills/memory/SOUL
- secrets
- outside-Git paths
- network
- live/apply/rollout targets
- writes to `knowledge/kb/` or `knowledge/canonical/`

## Evidence-owner pattern

This harness follows the Phase 3 evidence-owner pattern:

- freeze input into the run directory;
- record hashes;
- record checks;
- emit report.json/report.md;
- emit exit_code;
- fail closed on boundary violations.

## Thin-wrapper pattern

`run_local_source_smoke.sh` is a thin wrapper. It coordinates capture, validation, and reporting, but it does not generate semantic meaning and does not own an alternate canonical evidence surface.
