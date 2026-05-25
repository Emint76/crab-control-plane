# Knowledge Pipeline Accepted State

This document records the accepted state of `operations/harness-knowledge-pipeline/` after PR67, PR68, PR70, PR71, and PR72. It is a state marker, not a new feature proposal.

## A. Accepted after

- PR67: repo-native knowledge-pipeline harness v0.
- PR68: hardened smoke runner.
- PR70: semantic operator handoff contract.
- PR71: semantic artifact schema contracts.
- PR72: `semantic-required` schema-backed validation hardening.
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
- external URL ingestion in the current harness.

## E. Not accepted yet

The following are not accepted capabilities of the current harness:

- automatic normalized note generation;
- automatic placement/admission/wiki draft generation;
- full semantic pipeline automation;
- external URL capture;
- canonical KB write;
- Hermes skill auto-sync.

## F. Exit semantics

```text
0 = capture-only smoke pass, or semantic-required full pass
3 = awaiting semantic outputs in semantic-required mode
1 = validation/runtime failure, including invalid semantic artifacts
2 = usage, invalid mode, or unavailable Python launcher
```

## G. Next gap

The next gap is a manual semantic handoff evidence run against the hardened `semantic-required` validation path:

See `SEMANTIC_OPERATOR_HANDOFF.md` for the accepted docs/contract handoff shape.

Machine-readable schema contracts for the semantic handoff artifacts live under `contracts/`; `contracts/semantic_artifact_set.schema.json` maps the expected `output/` artifact paths to JSON schemas and lists markdown artifacts without deep markdown validation yet.

1. runner creates capture artifacts;
2. Hermes/LLM fills semantic artifacts inside the run directory when explicitly instructed;
3. runner validates those artifacts in `semantic-required` mode and updates reports;
4. canonical KB remains gated and is not written automatically.
