# PHASE4_MANDATORY_INVOCATION_GATE

## Purpose

For `target_kind: kb_admission`, Phase3 now requires proof that the exact Phase3 run was invoked by a real Phase4 wrapper run.

The accepted governance route for new real Source and Knowledge admissions is:

```text
Phase2 -> Phase4 wrapper -> Phase3 kb_admission
```

This gate applies only to `kb_admission`. Other Phase3 target kinds, including `phase3_staging` and `repo_admission`, keep their existing behavior.

## Ownership Boundary

Phase3 remains the canonical execution owner. It owns apply, canonical evidence, reports, `execution_result.json`, and `exit_code`.

Phase4 remains a thin invocation/operator wrapper. It owns wrapper metadata and the invocation claim only. It must not create or own Phase3 canonical outputs.

The string `invoked_by: phase4-wrapper` is not proof.

This is repo-enforced exact-run linkage under the existing trusted local operator model. It is not cryptographic authentication.

## Claim

For `kb_admission`, Phase4 writes:

```text
operations/harness-phase4/runs/<WRAPPER_RUN_ID>/phase4_invocation_claim.json
```

The claim conforms to:

```text
operations/harness-phase4/contracts/phase4_invocation_claim.schema.json
```

The claim binds:

- schema name and version;
- stable claim identity;
- Phase4 wrapper run id and repo-relative wrapper run ref;
- exact Phase3 run id and repo-relative Phase3 run ref;
- `target_kind: kb_admission`;
- repo-relative execution-target ref;
- SHA-256 of the exact execution-target bytes supplied to Phase3;
- Phase2 run ref;
- UTC creation timestamp;
- explicit invocation intent;
- Phase3/Phase4 ownership invariants.

It does not include secrets, tokens, credentials, or host-specific absolute paths.

## Transfer

Phase4 passes the claim explicitly to Phase3:

```text
--phase4-invocation-claim operations/harness-phase4/runs/<WRAPPER_RUN_ID>/phase4_invocation_claim.json
```

Phase3 does not derive proof from `invoked_by`.

## Phase3 Enforcement

Before apply or canonical mutation, Phase3 freezes the exact claim bytes at:

```text
operations/harness-phase3/runs/<PHASE3_RUN_ID>/input/phase4_invocation_claim.json
```

Phase3 records freeze metadata at:

```text
operations/harness-phase3/runs/<PHASE3_RUN_ID>/input/phase4_invocation_claim_freeze.json
```

Phase3 validates the frozen claim and writes evidence at:

```text
operations/harness-phase3/runs/<PHASE3_RUN_ID>/checks/phase4_invocation_validation.json
```

Validation checks schema conformance, byte identity, SHA-256 preservation, repo-contained Phase4 claim path, no symlink claim path components, wrapper run identity, Phase3 run identity, target kind, execution-target ref, execution-target hash, Phase2 run ref, and claim identity.

Missing, malformed, schema-invalid, mismatched, replayed, traversed, symlinked, or substituted claims fail closed before apply.

## Non-Goals

- No change to Admission Stage 1.
- No type-specific admission schemas.
- No semantic validation of `profile_data`.
- No Phase4 ownership of Phase3 canonical outputs.
- No cryptographic authentication claim.
- No cleanup, retention, archive, migration, or batch-runner change.
