# Admission Check Ownership

Each check has one authoritative owner. Duplicate checks in another layer require a documented reason and must be treated as transitional debt unless ownership is changed explicitly.

| Check class | Owner |
|---|---|
| Producer semantic correctness | producer / extraction profile |
| Universal package shape | Admission Stage 1 contract |
| Review approval and admission policy | Phase2 |
| Identity and placement policy | Phase2 |
| Phase3 target and manifest schema | Phase3 |
| Safe relative paths | Phase3 |
| Input file existence | Phase3 |
| SHA-256 verification | Phase3 |
| Copy and overwrite behavior | Phase3 |
| Phase4 invocation metadata | Phase4, validated according to current accepted Phase contract |
| Canonical execution evidence | Phase3 |

## Duplicate-Check Rule

Do not add duplicate checks to another layer without a documented reason.

Current duplicate or transitional checks are debt:

- Admission Stage 1 still has an isolated dry-run executable validator for package shape and payload kind.
- The historical source-admission helper remains available for preflight reference, but it is not part of the Stage 2 route.
- Some Phase2 readiness checks inspect Stage 2 references and identity mapping so the Phase route can fail early. They must not expand into payload hash validation, copying, overwrite behavior, destination mutation, or canonical evidence ownership.
