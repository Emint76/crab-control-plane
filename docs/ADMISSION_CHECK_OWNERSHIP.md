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
| Typed knowledge placement structure and config interface | Admission Stage 2 contract / standalone policy preflight |
| Concrete allowed `knowledge_type` values and profile-to-type mappings | local KB instance configuration |
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
- The generic Phase2 bundle does not consume, approve, freeze, or prove a specific admission handoff.
- A Phase2 baseline is reusable only when the Phase2 run completed successfully, its canonical report and handoff-readiness result are passing, the tracked repository working tree is clean, the operator or batch runner recorded the exact repository Git HEAD when the baseline was accepted, and the current repository Git HEAD exactly equals that recorded HEAD.
- Any new repository commit makes the previous Phase2 baseline stale. After any merge into `main`, including merge of this PR, a new Phase2 baseline must be created before the next admission pilot or batch.
- The recorded relationship `phase2_run_id -> repo_head` belongs to operator or batch-runner operational state/logging. It is not canonical Phase2 evidence, admission handoff evidence, Phase3 frozen input, or a second canonical evidence surface.
- Allowed claim: `Accepted Phase2 baseline <RUN_ID> was created for and reused at repository HEAD <SHA>.`
- Forbidden claim: `Phase2 baseline is current.`
- No operator override may permit reuse across different Git HEADs.
- Phase3 does not need to prove or freeze the entire pre-Phase governance chain.

Adding a new registered knowledge profile must not require new Stage 2 admission code. Stage 2 contains no profile-specific executable implementation.

For knowledge assets, standalone policy preflight consumes instance-local KB taxonomy configuration through `ADMISSION_KB_TAXONOMY_CONFIG`. That config is local operator/instance input, not canonical repository taxonomy. Missing config, invalid config, unknown `knowledge_type`, profile/type mismatch, or shape-only diagnostic mode fails closed and must not be reported as real admission readiness.

Review decisions used by Stage 2 are admission authorization and placement gates. They authorize the package for KB placement when the canonical review decision says `decision: approve` and `approved_destination: kb`; they do not mean Phase approved knowledge quality, do not replace semantic review in later wiki/semantic layers, and do not make Phase2, Phase3, or Phase4 semantic validators.
