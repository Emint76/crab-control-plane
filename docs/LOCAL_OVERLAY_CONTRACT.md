# LOCAL_OVERLAY_CONTRACT

## Purpose

This document defines the local-only overlay boundary for future OpenClaw integration work.
The local overlay is where instance-specific secrets, identity, credentials, endpoint config, and local runtime configuration may live.
The local overlay is never committed to this repository.

## Status

This is a contract-only document.
No local overlay implementation, rendering, apply, deploy, migration, or runtime integration is included in this PR.

## Scope

This contract defines what the repository may document, reference, and require before future disposable OpenClaw workspace apply work can consume any local-only overlay.
It does not authorize the current repo-native harness, current dry-run adapter, or Crab-safe orchestration wrapper to read local overlay contents.

## Local-only rule

The local overlay is outside the Git repository.
The repository may document expected overlay shape, but must not contain real overlay contents.

## What belongs in local overlay

- secrets
- tokens
- API keys
- OAuth credentials
- bot identity
- channel IDs
- endpoint URLs with credentials
- model/provider credentials
- instance-specific runtime config
- local operator preferences
- local OpenClaw target selectors
- local paths to disposable workspace/state

## What must never enter Git

- `.env`
- real token files
- OAuth refresh tokens
- private keys
- SSH keys
- cloud credentials
- browser profile credentials
- real bot IDs
- real channel IDs
- real KB data
- real memory data
- real OpenClaw state
- real OpenClaw workspace
- runtime logs from a real agent
- local overlay contents

## Example local layout

Example paths only:

```text
../crab-local-overlay/
  identity/
  secrets/
  runtime/
  targets/
  operator/

../crab-instance-data/
  disposable-openclaw-workspace/
  disposable-openclaw-state/
  logs/
```

These paths are examples only. The actual local path must be supplied outside Git.

## Required separation from repo

The repo must not assume that local overlay exists inside the repository.
Future scripts must accept explicit repo-relative or external local paths only through a contract that prevents accidental commits and secret leakage.

## Allowed future reads

Future components may read local overlay only when:

- a separate implementation contract exists
- the command is not dry-run-only
- the read is explicitly declared
- secret leakage checks exist
- the target is disposable workspace apply, not live runtime apply
- human review has approved it

## Forbidden reads

Current repo and current dry-run adapter must not read:

- local overlay
- secrets
- tokens
- OpenClaw real state
- OpenClaw real workspace
- real KB
- real memory
- runtime logs from real agent

## Allowed future writes

Only future disposable apply may write to:

- disposable local OpenClaw workspace
- disposable local OpenClaw state
- repo-local evidence directory

This requires a separate contract, tests, and CI before implementation.

## Forbidden writes

Always forbidden for current state:

- live OpenClaw runtime
- real personal agent workspace/state
- real KB
- real memory
- secrets
- local overlay
- production deploy target

## Relationship to OpenClaw dry-run adapter

The current OpenClaw dry-run adapter must not read local overlay.
It only reads repo-native Phase 2/3 evidence and writes repo-local dry-run evidence.

## Relationship to disposable workspace apply

The disposable workspace/state boundary is defined in `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`.
Disposable workspace apply may later consume local overlay selectors or config, but only after a separate disposable workspace contract and apply contract exist.
The local overlay contract may describe where disposable workspace/state paths are declared, but it does not implement disposable workspace creation or apply.

## Relationship to live runtime apply

Live runtime apply remains forbidden and out of scope.
Local overlay contract does not authorize live runtime writes.

## Relationship to Crab-safe orchestration

Crab may not access local overlay unless a future approved wrapper explicitly permits a bounded operation with tests, CI, and human review.

## Secret leakage rules

Future tools must ensure:

- no secrets copied to repo
- no secrets written into reports
- no secrets written into dry-run plans
- no host-specific private paths leaked into committed docs
- generated evidence redacts secret-like values

## Identity boundary

Bot identity, channel identity, endpoint identity, model/provider identity, operator identity, and instance identity are local-only unless represented by sanitized placeholder names.
Real identity values must remain outside Git and must not appear in repo-local evidence.

## Validation expectations

Future implementation must include:

- local overlay path validation
- secret file denylist
- git status cleanliness check
- evidence redaction checks
- no-secret-leakage validation
- safe cleanup behavior

## Promotion gates

Before disposable workspace apply:

- local overlay contract exists
- disposable workspace contract exists
- secret leakage checks exist
- dry-run adapter remains green
- human review approves the exact local overlay path
- no live runtime target is used

## Non-goals

- no local overlay implementation
- no secrets management implementation
- no deploy
- no migration
- no disposable workspace apply
- no live runtime apply
- no OpenClaw writes
- no real KB write-back
- no Crab permission to access overlay
- no Phase 2/3/4 behavior changes

## Acceptance criteria for future implementation

- local overlay implementation contract exists
- disposable workspace contract exists
- explicit local overlay path validation exists
- secret file denylist exists
- no-secret-leakage validation exists
- generated evidence redacts secret-like values
- tests cover allowed and forbidden overlay access
- CI or local validation proves overlay contents do not enter Git
