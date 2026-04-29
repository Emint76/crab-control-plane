# DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT

## Purpose

This document defines the disposable local OpenClaw workspace/state boundary for future controlled apply work.
A disposable workspace/state target is the first permitted non-dry-run target after dry-run evidence, placement plan schema validation, and local overlay contract.

## Status

This is a contract-only document.
No disposable workspace creation, apply, deploy, migration, OpenClaw mutation, or runtime integration is included in this PR.

## Scope

This contract defines future disposable local OpenClaw workspace/state requirements.
It does not authorize controlled apply, live runtime apply, deploy, migration, local overlay reads, or Crab invocation.

## Disposable workspace definition

A disposable OpenClaw workspace is a local test workspace created only for validation.
It must be safe to delete.
It must be separated from any real personal agent workspace.
It must not contain real KB, real memory, real runtime logs, real secrets, or production identity.

## Disposable state definition

Disposable OpenClaw state is local test state created only for validation.
It must be safe to delete.
It must not be the state directory of a real running agent.
It must not contain real tokens, credentials, OAuth state, bot identity, or live runtime configuration.

## Required separation from real agent state

Disposable workspace/state must never point to a real OpenClaw instance used by a personal agent.
Future scripts must fail closed if the target path appears to be a real agent workspace/state or if the target is not explicitly marked disposable.

## Example local layout

Example paths only:

```text
../crab-instance-data/
  disposable-openclaw-workspace/
  disposable-openclaw-state/
  disposable-openclaw-logs/

../crab-local-overlay/
  targets/
    disposable-openclaw-target.json
```

These paths are examples only and are not canonical Git contents.
Actual local paths must be supplied outside Git and must not be committed.

## Required local-only rule

Disposable workspace/state live outside Git.
This repository may document their expected shape, but must not contain real disposable workspace/state contents.

## Allowed future inputs

Future controlled disposable apply may consume:

- schema-validated `proposed_openclaw_placement_plan.json`
- Phase 3 repo-native evidence
- dry-run adapter evidence
- local overlay target selector
- explicit disposable workspace path
- explicit disposable state path
- human approval flag or record

Only after separate apply contract, tests, and CI.

## Forbidden inputs

Current and future disposable apply must not use:

- real OpenClaw workspace
- real OpenClaw state
- real KB
- real memory
- real runtime logs
- secrets as source content
- tokens as source content
- production bot/channel identity as source content
- live runtime config as committed source

## Allowed future writes

Only future controlled disposable apply may write to:

- explicit disposable OpenClaw workspace path
- explicit disposable OpenClaw state path
- repo-local evidence directory

But only after:

- separate controlled apply contract
- tests
- CI or local validation
- secret leakage checks
- human review

## Forbidden writes

Always forbidden at current stage:

- live OpenClaw runtime
- real personal agent workspace/state
- real KB
- real memory
- local overlay
- secrets files
- production deploy target
- Git-tracked runtime contents

## Cleanup and rollback expectations

Future implementation must support:

- safe cleanup of disposable workspace/state
- refusal to delete unexpected paths
- path prefix validation
- direct-child validation where applicable
- rollback evidence
- cleanup evidence
- no cleanup of real agent state

## Evidence requirements

Future controlled disposable apply must produce evidence such as:

- `apply_meta.json`
- `input_refs.json`
- `target_refs.json`
- `pre_apply_snapshot.json`
- `post_apply_snapshot.json`
- `cleanup_plan.json`
- `rollback_plan.json`
- `apply_report.md`
- `apply_report.json`
- `exit_code`
- `checks/run_dir_invariants.json`
- `checks/target_path_validation.json`
- `checks/no_secret_leakage_validation.json`
- `checks/no_live_runtime_validation.json`

This PR does not implement these artifacts.

## No-secret-leakage requirements

Future implementation must prove:

- no secrets copied to disposable workspace/state
- no secrets copied to repo-local evidence
- no tokens in reports
- no OAuth refresh tokens in reports
- no private keys in reports
- no real bot/channel IDs in reports unless explicitly redacted
- no host-private paths leaked into committed docs

## Relationship to local overlay

The disposable workspace contract depends on `docs/LOCAL_OVERLAY_CONTRACT.md`.
Local overlay may later provide target selectors and local paths, but this contract does not implement overlay reading.
Current dry-run adapter still must not read local overlay.

## Relationship to OpenClaw dry-run adapter

The dry-run adapter produces schema-backed proposed placement plans.
Disposable workspace apply may later consume those plans, but only after a separate controlled apply implementation contract.

## Relationship to controlled disposable apply

Controlled disposable apply is the next possible implementation stage after this contract.
The controlled disposable apply boundary is defined in `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`.
This document does not authorize or implement controlled apply.
The disposable workspace/state contract alone does not authorize apply.

## Relationship to live runtime apply

Live runtime apply remains forbidden and out of scope.
Successful disposable workspace validation does not automatically authorize live runtime apply.

## Relationship to Crab-safe orchestration

Crab may not invoke disposable workspace apply unless a future approved wrapper explicitly permits it with bounded args, tests, CI, and human review.

## Validation expectations

Future implementation must include:

- disposable target marker validation
- path containment validation
- real-agent-state denylist
- secret file denylist
- no-secret-leakage validation
- no-live-runtime validation
- safe cleanup validation
- evidence shape validation

## Promotion gates

Before controlled disposable apply:

- disposable workspace contract exists
- local overlay contract exists
- dry-run adapter remains green
- placement plan schema validation remains green
- no-secret-leakage checks exist
- target path is explicitly disposable
- human review approves the target path
- no live runtime target is used

Before live runtime apply:

- separate live runtime contract
- separate live runtime risk review
- rollback plan
- operator approval
- secret handling contract
- production safety checks

Live runtime apply remains out of scope.

## Non-goals

- no disposable workspace implementation
- no controlled apply implementation
- no OpenClaw writes
- no live runtime apply
- no deploy
- no migration
- no secrets handling code
- no local overlay implementation
- no real KB write-back
- no Crab permission to invoke apply
- no Phase 2/3/4 behavior changes
- no workflow changes

## Acceptance criteria for future implementation

- disposable workspace/state implementation contract exists
- explicit disposable target marker validation exists
- path containment validation exists
- real-agent-state denylist exists
- no-secret-leakage validation exists
- no-live-runtime validation exists
- rollback evidence exists
- cleanup evidence exists
- tests cover safe cleanup and refusal to touch real agent state
- CI or local validation proves no disposable workspace/state contents enter Git
