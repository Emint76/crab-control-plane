# harness-e2e

## Purpose

`operations/harness-e2e/` contains repo-native end-to-end smoke tests for the harness.

It proves that the local repo-native path is wired:

Phase 2 `repo-native-scaffold` -> Phase 3 canonical execution owner -> Phase 4 thin wrapper.

## Non-goals

- no live OpenClaw runtime mutation
- no deploy
- no migration
- no plugin/gateway/channel/model/auth/token/config changes
- no production install

## Entrypoint

```bash
make smoke-e2e
```

Direct fallback command for environments where `make` is unavailable:

```bash
bash operations/harness-e2e/tests/test_smoke_e2e.sh
```

## What this proves

* Phase 2 can prepare a repo-native package for Phase 3 intake.
* Phase 3 can consume Phase 2 output and produce canonical repo-native execution evidence.
* Phase 4 can wrap Phase 3 without owning canonical outputs.

## What this does not prove

* live OpenClaw apply
* deployment readiness
* production runtime integration
* real source ingestion
