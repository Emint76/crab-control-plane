# OPENCLAW_INTEGRATION_BOUNDARY

## Purpose

This document defines the boundary between the repo-native crab-control-plane harness and any future OpenClaw runtime integration.

## Current accepted state

- repo-native Phase 2 check/render/handoff preparation
- repo-native Phase 3 canonical execution owner
- repo-native Phase 4 thin wrapper
- smoke-e2e CI
- Crab-safe orchestration wrapper
- OpenClaw dry-run adapter skeleton

## What this document does not implement

This document does not implement runtime integration, deploy, migration, disposable workspace apply, live adapter behavior, real source ingestion, real KB write-back, or live OpenClaw mutation.

## Boundary model

```text
repo-native harness output
  -> dry-run OpenClaw adapter boundary
  -> disposable local OpenClaw workspace
  -> controlled apply gate
  -> only then possible live-runtime discussion
```

## Allowed future integration modes

| Mode | Meaning | Status |
| --- | --- | --- |
| `dry-run` | inspect repo-native output and produce a proposed OpenClaw placement plan without writing to OpenClaw | allowed future first step |
| `disposable-workspace-apply` | apply only to disposable local OpenClaw workspace/state created for testing | future gated step |
| `live-runtime-apply` | write to a real running OpenClaw instance | explicitly not implemented and forbidden until separate contract |

## Forbidden behavior

- no live OpenClaw runtime mutation
- no production deploy
- no migration
- no secrets in Git
- no tokens in Git
- no instance identity in Git
- no direct writes to real KB
- no direct writes to live workspace/state
- no bypassing Phase 3
- no bypassing Crab-safe orchestration rules
- no arbitrary shell execution by Crab
- no adapter that writes before dry-run evidence is reviewed

## Required local-only surfaces

Future integration work must keep these surfaces local-only and outside Git:

- local overlay
- runtime secrets
- instance identity
- OpenClaw workspace
- OpenClaw state
- KB data
- logs from real runtime
- generated adapter artifacts

Example local paths:

```text
../crab-local-overlay/
../crab-instance-data/
../openclaw/
```

These paths are examples only and are not canonical Git contents.

The local overlay boundary is defined in `docs/LOCAL_OVERLAY_CONTRACT.md`.

## Runtime target assumptions

The repo may later target a local OpenClaw checkout or containerized OpenClaw runtime, but this repository must not vendor, fork, or mutate OpenClaw runtime code as part of the boundary.

## Dry-run adapter boundary

The dry-run adapter contract is defined in `operations/harness-openclaw-dryrun/OPENCLAW_DRY_RUN_ADAPTER_CONTRACT.md`.

The dry-run adapter skeleton may:

- read Phase 3 staging output
- read Phase 3 reports
- read Phase 2 handoff evidence
- read execution target metadata
- produce a proposed OpenClaw placement plan
- write only repo-local dry-run evidence

The dry-run adapter skeleton must not:

- write to OpenClaw state
- write to OpenClaw workspace
- start or stop OpenClaw
- edit OpenClaw runtime files
- use secrets
- contact external services
- perform real KB write-back

## Disposable workspace boundary

The disposable OpenClaw workspace/state boundary is defined in `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`.
The controlled disposable apply contract is defined in `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`.

The first non-dry-run integration target must be a disposable local OpenClaw workspace/state, not a real personal agent instance.

It must be:

- created for test only
- safe to delete
- separated from real agent state
- controlled by local overlay outside Git
- validated by explicit evidence before promotion

## Secrets and identity boundary

All secrets, tokens, endpoint credentials, bot identities, channel IDs, model credentials, and instance-specific config remain outside Git.

## Write-surface rules

Allowed repo write surfaces for dry-run only:

```text
operations/harness-openclaw-dryrun/runs/<RUN_ID>/
```

The dry-run adapter skeleton writes repo-local dry-run evidence under this directory.

Forbidden write surfaces:

- live OpenClaw state
- live OpenClaw workspace
- real KB
- real memory
- real logs
- local overlay
- secrets files

## Evidence requirements

A future adapter must produce evidence such as:

- `adapter_meta.json`
- `input_refs.json`
- `proposed_openclaw_placement_plan.json`
- `dry_run_report.md`
- `dry_run_report.json`
- `exit_code`
- `checks/run_dir_invariants.json`

The dry-run adapter skeleton emits these dry-run evidence artifacts.

## Promotion gates

Promotion from dry-run to disposable apply requires:

- explicit contract
- tests
- CI or local validation
- no secret leakage
- no live runtime writes
- human review

Promotion from disposable apply to live apply requires a separate future decision and is out of scope.

## Relationship to Phase 2

Phase 2 prepares and validates upstream package/handoff evidence.
OpenClaw integration must not redefine Phase 2, Phase 3, or Phase 4.

## Relationship to Phase 3

Phase 3 remains canonical repo-native execution owner.
OpenClaw integration must not redefine Phase 2, Phase 3, or Phase 4.

## Relationship to Phase 4

Phase 4 remains a thin wrapper over Phase 3.
OpenClaw integration must not redefine Phase 2, Phase 3, or Phase 4.

## Relationship to Crab-safe orchestration

Crab may only use approved wrappers. Future OpenClaw integration commands must be added as explicit approved entrypoints with contracts, tests, and CI before Crab can call them.

## Minimum acceptance criteria before live runtime apply

- dry-run adapter exists
- dry-run adapter has CI or local validation
- disposable workspace apply has been tested
- explicit local overlay contract exists
- secret scanner / leakage checks exist
- rollback/cleanup procedure exists
- human approval gate exists
- live runtime target identity is explicit and local-only

## Non-goals

- no live OpenClaw runtime mutation
- no production deploy
- no migration
- no disposable or live runtime adapter implementation
- no real external source ingestion
- no real KB write-back
- no secrets, tokens, or instance identity in Git
- no changes to Phase 2, Phase 3, or Phase 4 semantics

## Next possible PRs

1. openclaw-dry-run-adapter-contract - defined
2. openclaw-dry-run-adapter-skeleton - implemented
3. openclaw-placement-plan-schema - implemented
4. local-overlay-contract - defined in `docs/LOCAL_OVERLAY_CONTRACT.md`
5. disposable-openclaw-workspace-contract - defined in `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`
6. controlled-disposable-apply-contract - defined in `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`
7. controlled-disposable-apply
