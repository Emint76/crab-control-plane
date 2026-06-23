# Admission Check Ownership

Each check has one authoritative owner. Duplicate checks in another layer require a documented reason and must be treated as transitional debt unless ownership is changed explicitly.

| Check class | Owner |
|---|---|
| Producer semantic correctness | producer / extraction profile |
| Universal package shape | Admission Stage 1 contract |
| Universal handoff and mapping contract | Admission Stage 2 contract |
| Review approval and admission policy | Phase2 |
| Stage 1 package binding hash used by the handoff | Phase2 readiness and identity binding |
| Identity and placement policy | Phase2 |
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

- Admission Stage 1 still has an isolated dry-run executable validator for package shape and payload kind.
- `enabled_for_admission` remains a transitional Stage 1 runtime gate. Profile maturity/status should eventually become descriptive rather than evidence of profile-specific admission implementation.
- The historical source-admission helper remains available for preflight reference, but it is not part of the Stage 2 route.
- Some Phase2 readiness checks inspect Stage 2 references, canonical review approval, package binding, identity mapping, and placement so the Phase route can fail early. They must not expand into runtime payload hash validation, copying, overwrite behavior, destination mutation, or canonical evidence ownership.

Adding a new registered knowledge profile must not require new Stage 2 admission code. Stage 2 contains no profile-specific executable implementation; cleanup of the Stage 1 registry gate is deferred to a later dedicated audit.
