# Hermes Knowledge Pipeline Harness

Repo-local, live-safe harness for bounded information-processing runs.

See `ACCEPTED_STATE.md` for the current accepted capability, boundaries, and gaps after PR67/PR68.

See `SEMANTIC_OPERATOR_HANDOFF.md` for the operator contract for filling semantic artifacts inside a captured run directory.

See `MANUAL_SEMANTIC_HANDOFF_EVIDENCE.md` for the first successful evidence run proving the manual contour: capture-only, operator-filled `output/` artifacts, and `semantic-required` validation with `exit_code=0`.

See `EXTERNAL_SOURCE_BOUNDARY.md` for the external-source adaptation boundary. The accepted executable external-source capability is limited to the PR76 no-network, fixture-backed URL capture smoke; real HTTP/HTTPS fetching remains not accepted.

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

Accepted fixture-backed external URL smoke contour:

```text
repo-local HTML fixture standing in for an HTTP/HTTPS URL
→ preserved raw snapshot under the run dir
→ extracted text compatibility artifact
→ SOURCE_CAPTURE_PACKAGE-compatible capture package
→ validation/report/exit_code
```

This external URL smoke is no-network only. It does not accept real HTTP/HTTPS fetching, scraping, semantic generation, admission, or canonical KB writes.

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

## Smoke runners

### Repo-local source smoke

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

### External URL fixture smoke

```bash
operations/harness-knowledge-pipeline/bin/run_external_url_capture_smoke.sh \
  <run-id> \
  <http-or-https-url> \
  <repo-local-html-fixture>
```

The external URL fixture smoke always runs in `capture-only` mode and performs no real network access. The fixture HTML is copied to `input/raw_snapshot.html`; `input/source.md` is extracted text for compatibility with the existing knowledge-pipeline contour. In `input/source_capture_package.json`, `stable_representation` must point to the preserved raw snapshot, not the extracted text.

Example:

```bash
operations/harness-knowledge-pipeline/bin/run_external_url_capture_smoke.sh \
  knowledge-external-url-fixture-001 \
  https://example.com/source \
  operations/harness-knowledge-pipeline/tests/fixtures/external-url/example.html
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
2 = usage, invalid mode, invalid external fixture URL/input, or unavailable Python launcher
3 = awaiting semantic outputs in semantic-required mode
```

Core rule:

```text
LLM transforms meaning.
Scripts own evidence, validation, placement boundaries, admission gates, and reports.
```
