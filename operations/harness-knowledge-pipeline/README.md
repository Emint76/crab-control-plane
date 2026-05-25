# Hermes Knowledge Pipeline Harness

Repo-local, live-safe harness for bounded information-processing runs.

See `ACCEPTED_STATE.md` for the current accepted capability, boundaries, and gaps after PR67/PR68.

See `SEMANTIC_OPERATOR_HANDOFF.md` for the operator contract for filling semantic artifacts inside a captured run directory.

See `MANUAL_SEMANTIC_HANDOFF_EVIDENCE.md` for the first successful evidence run proving the manual contour: capture-only, operator-filled `output/` artifacts, and `semantic-required` validation with `exit_code=0`.

See `contracts/semantic_artifact_set.schema.json` and the linked JSON schemas in `contracts/` for the machine-readable semantic artifact contracts. These schemas are contracts only; they do not implement automatic semantic generation.

First supported source contour:

```text
repo-local .md/.markdown/.txt source
→ source capture / evidence
→ optional normalized note
→ optional result packet
→ optional placement/admission candidate
→ optional canonical knowledge candidate
→ optional wiki-derived draft
→ validation/report/exit_code
```

Safety boundary:

- no OpenClaw
- no Docker
- no Hermes config/skills/memory/SOUL changes
- no secrets
- no outside-Git paths
- no live/apply/rollout
- no network
- no automatic canonical writes

All first-run writes are confined to:

```text
operations/harness-knowledge-pipeline/runs/<RUN_ID>/
```

## Smoke runner

```bash
operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
  [--mode capture-only|semantic-required] \
  <run-id> \
  <repo-local-source>
```

Default mode is `capture-only`.

Example:

```bash
operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
  knowledge-admission-policy-001 \
  control-plane/policy/ADMISSION_POLICY.md
```

### Python launcher

The wrapper resolves Python in this order:

1. use `KNOWLEDGE_PIPELINE_PYTHON_BIN` when set, and fail clearly if it is unavailable;
2. else use `python` when available;
3. else use `python3` when available;
4. else fail with a clear diagnostic.

### Modes

`capture-only` succeeds when source capture, hashes, task packet, schema checks, report, and `exit_code` are generated and valid. Semantic outputs may be absent.

`semantic-required` validates operator-authored semantic artifacts under `operations/harness-knowledge-pipeline/runs/<RUN_ID>/output/`.

Expected semantic artifacts:

```text
output/normalized_note.md
output/normalized_note.json
output/result_packet.json
output/placement_decision.candidate.json
output/admission_decision.candidate.json
output/canonical_knowledge_candidate.md
output/wiki_derived_draft.md
```

JSON artifacts are validated against the schemas in `contracts/`; the artifact-set/path mapping is validated against `contracts/semantic_artifact_set.schema.json`. Markdown artifacts are presence/non-empty checked only; they are not deeply markdown-schema validated yet.

If semantic output files are absent, the run reports `awaiting_semantic_outputs` and exits `3`. If semantic artifacts are present but invalid, the run reports `fail` and exits `1`. If they are present and valid, the run reports `pass` and exits `0`.

### Exit codes

```text
0 = capture-only smoke pass, or semantic-required full pass
1 = validation/runtime failure
2 = usage, invalid mode, or unavailable Python launcher
3 = awaiting semantic outputs in semantic-required mode
```

Core rule:

```text
LLM transforms meaning.
Scripts own evidence, validation, placement boundaries, admission gates, and reports.
```
