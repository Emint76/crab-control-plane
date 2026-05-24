# KNOWLEDGE_PIPELINE_CONTRACT

## Purpose

This harness adapts the existing crab-control-plane knowledge contracts into a working Hermes Knowledge Pipeline run without creating a Hermes self-improvement contour.

## Scope

Supported source input:

```text
repo-local .md/.markdown/.txt file only
```

Example source:

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

The capture/evidence layer is runnable without semantic outputs. Semantic files are produced separately by Hermes/LLM and validated only when semantic validation is required.

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

## Python launcher contract

The wrapper resolves Python in this order:

1. if `KNOWLEDGE_PIPELINE_PYTHON_BIN` is set, use it and fail clearly when unavailable;
2. else prefer `python` when available;
3. else fallback to `python3` when available;
4. else fail clearly with instructions to set `KNOWLEDGE_PIPELINE_PYTHON_BIN=python3` or install Python.

## Smoke modes

The wrapper supports:

```bash
run_local_source_smoke.sh [--mode capture-only|semantic-required] <run-id> <repo-local-source>
```

Default mode: `capture-only`.

### `capture-only`

A capture-only smoke succeeds when these generated artifacts/checks are valid:

- `run_meta.json`
- `input/source.md`
- `input/source.sha256`
- `input/source_capture_package.json`
- `input/task_packet.json`
- source capture schema check
- task packet schema check
- source hash validation
- no-live-surface validation
- `report.json`
- `report.md`
- `exit_code`

Semantic output files are not required in this mode.

### `semantic-required`

Semantic-required mode preserves full validation. Missing semantic outputs produce `awaiting_semantic_outputs` and exit code `3`.

## Exit codes

```text
0 = capture-only smoke pass, or semantic-required full pass
1 = validation/runtime failure
2 = usage, invalid mode, or unavailable Python launcher
3 = awaiting semantic outputs in semantic-required mode
```

`3` must not be emitted only because semantic outputs are absent in `capture-only` mode.

## Report fields

Reports include:

- `mode`
- `semantic_outputs_required`
- `exit_code`
- `status`
- generated artifacts/checks/blockers
