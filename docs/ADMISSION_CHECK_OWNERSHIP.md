# Admission Check Ownership

Each check has one authoritative owner. Duplicate checks in another layer require a documented reason and must be treated as transitional debt unless ownership is changed explicitly.

| Check class | Owner |
|---|---|
| Producer semantic correctness | producer / extraction profile |
| Universal package shape | Admission Stage 1 contract |
| Universal handoff and mapping contract | Admission Stage 2 contract |
| Review approval and admission policy | admission preparation / standalone policy preflight |
| Stage 1 package binding hash used by the handoff | admission preparation / standalone policy preflight |
| Identity and placement policy | admission preparation / standalone policy preflight |
| Source-versus-knowledge classification | admission preparation / standalone policy preflight |
| Profile registration checks | admission preparation / standalone policy preflight |
| Target/manifest mapping checks | admission preparation / standalone policy preflight |
| Reusable repo/control-plane baseline validation | Phase2 |
| Generic render/apply-plan/runtime-ready/handoff readiness | Phase2 |
| Phase3 target and manifest schema | Phase3 |
| Runtime input file existence | Phase3 |
| Runtime staged payload file hashes | Phase3 |
| Destination/copied-result hashes | Phase3 |
| Copy and overwrite evidence | Phase3 |
| Phase4 invocation metadata | Phase4, validated according to current accepted Phase contract |
| Canonical execution evidence | Phase3 |

## Duplicate-Check Rule

Do not add duplicate checks to another layer without a documented reason.

Current duplicate or transitional checks are debt:

- Admission Stage contracts are pre-Phase contracts, not runtime Phases.
- `check_admission_policy.py` is a standalone repo-native preflight utility. Its output is manual/agent/batch-runner proof, not generic Phase2 bundle evidence and not canonical admission evidence.
- The generic Phase2 bundle does not consume, approve, freeze, or prove a specific admission handoff. One accepted Phase2 baseline may be reused while the relevant repo/control-plane baseline is unchanged.
- Phase3 does not need to prove or freeze the entire pre-Phase governance chain.

Adding a new registered knowledge profile must not require new Stage 2 admission code. Stage 2 contains no profile-specific executable implementation.
