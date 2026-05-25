# Knowledge Pipeline Accepted State

This document records the accepted state of `operations/harness-knowledge-pipeline/` after PR67, PR68, PR70, PR71, PR72, PR75, and PR76. It is a state marker, not a new feature proposal.

## A. Accepted after

- PR67: repo-native knowledge-pipeline harness v0.
- PR68: hardened smoke runner.
- PR70: semantic operator handoff contract.
- PR71: semantic artifact schema contracts.
- PR72: `semantic-required` schema-backed validation hardening.
- PR75: docs-only external source boundary/adaptation over the repo-wide `SOURCE_CAPTURE_PACKAGE` contract.
- PR76: no-network, fixture-backed external URL capture smoke that preserves a raw HTML snapshot, emits extracted text compatibility evidence, validates `SOURCE_CAPTURE_PACKAGE` shape, and reports `network_used=false`.
- Manual semantic handoff evidence run `admission-policy-semantic-handoff-001`: capture-only `exit_code=0`, operator-filled `output/` semantic artifacts, and semantic-required `exit_code=0`.
- Post-merge smoke result on `main`: `exit_code=0` for capture-only smoke.

## B. Current accepted capability

The current harness accepts repo-local source files with these extensions:

- `.md`
- `.markdown`
- `.txt`

Accepted capture/evidence capability:

- source capture;
- source hash/evidence;
- source capture package;
- task packet;
- validation checks;
- `report.md`;
- `report.json`;
- `exit_code`;
- green capture-only smoke.

Accepted fixture-backed external URL capture smoke capability:

- accepts an `http`/`https` URL plus a repo-local HTML fixture;
- performs no real network fetch and sets `network_used=false`;
- preserves the raw fixture snapshot as `input/raw_snapshot.html` with `input/raw_snapshot.sha256`;
- emits extracted text as `input/source.md` with `input/source.sha256` for compatibility with the current contour;
- emits `input/retrieval_metadata.json` describing the simulated fixture retrieval;
- emits `input/source_capture_package.json` compatible with `control-plane/contracts/schemas/source_capture_package.schema.json`;
- keeps `stable_representation` pointed at the preserved raw snapshot, not the extracted text;
- rejects unsafe URL forms before valid evidence is accepted.

Accepted semantic validation capability:

- `semantic-required` requires the seven expected semantic artifacts under `runs/<RUN_ID>/output/`;
- missing semantic artifacts return `exit_code=3` with `awaiting_semantic_outputs`;
- invalid semantic JSON or boundary failures return `exit_code=1` with `fail`;
- complete valid semantic artifacts return `exit_code=0` with `pass`;
- JSON artifacts are validated against `contracts/` schemas;
- markdown artifacts are presence/non-empty checked only, not deeply schema-validated yet.

## C. Agent-facing meaning

Hermes/agent may treat `operations/harness-knowledge-pipeline/` as the repo-authoritative scaffold for this knowledge-pipeline contour.

Hermes/agent may use run-dir artifacts as the evidence surface.

Hermes/agent may read capture and report artifacts generated under:

```text
operations/harness-knowledge-pipeline/runs/<RUN_ID>/
```

Hermes/agent may add semantic outputs only inside the run directory when explicitly instructed by the operator.

## D. Boundaries

The accepted harness state does not permit:

- OpenClaw use;
- Docker use;
- live/apply/rollout actions;
- Hermes config/skills/memory/SOUL changes;
- canonical KB automatic writes;
- real external HTTP/HTTPS fetching, scraping, or URL ingestion beyond the no-network fixture-backed smoke.

See `EXTERNAL_SOURCE_BOUNDARY.md` for the adaptation rules that tie both PR76 fixture-backed evidence and future external HTTP/HTTPS source candidates back to the repo-wide `SOURCE_CAPTURE_PACKAGE` contract. PR76 does not accept real external network capture.

## E. Not accepted yet

The following are not accepted capabilities of the current harness:

- automatic normalized note generation;
- automatic placement/admission/wiki draft generation;
- full semantic pipeline automation;
- real external HTTP/HTTPS fetching, scraping, redirect following, DNS/private-network resolution, or `network_used=true` external URL capture;
- canonical KB write;
- Hermes skill auto-sync.

## F. Exit semantics

```text
0 = capture-only smoke pass, or semantic-required full pass
3 = awaiting semantic outputs in semantic-required mode
1 = validation/runtime failure, including invalid semantic artifacts
2 = usage, invalid mode, invalid external fixture URL/input, or unavailable Python launcher
```

## G. Next gaps

The repo-local semantic handoff contour remains operator-mediated and docs-backed while generated run artifacts remain local/ignored.

The external-source gap after PR76 is a later real HTTP/HTTPS capture layer (likely PR77) that remains bounded, evidence-only by default, and uses the existing `SOURCE_CAPTURE_PACKAGE` contract. That layer would need real fetch controls, redirect evidence, DNS/private-network safeguards, HTTP status/content-type handling, and any `network_used=true` report/schema evolution if accepted.

See `SEMANTIC_OPERATOR_HANDOFF.md` for the accepted docs/contract handoff shape.

See `MANUAL_SEMANTIC_HANDOFF_EVIDENCE.md` for the successful evidence run `admission-policy-semantic-handoff-001`, which proved capture-only `exit_code=0` → operator-filled `output/` semantic artifacts → semantic-required `exit_code=0`.

Machine-readable schema contracts for the semantic handoff artifacts live under `contracts/`; `contracts/semantic_artifact_set.schema.json` maps the expected `output/` artifact paths to JSON schemas and lists markdown artifacts without deep markdown validation yet.

1. runner creates capture artifacts;
2. Hermes/LLM fills semantic artifacts inside the run directory when explicitly instructed;
3. runner validates those artifacts in `semantic-required` mode and updates reports;
4. canonical KB remains gated and is not written automatically.
