# Manual Semantic Handoff Evidence

This document records the first successful manual semantic handoff evidence run after PR70, PR71, and PR72. It is a docs-only evidence marker, not an automation change and not a canonical KB admission.

## A. Evidence run

- run id: `admission-policy-semantic-handoff-001`
- source: `control-plane/policy/ADMISSION_POLICY.md`
- evidence surface: `operations/harness-knowledge-pipeline/runs/admission-policy-semantic-handoff-001/`

Validated sequence:

```text
capture-only -> exit_code=0
operator writes semantic artifacts under output/
semantic-required -> exit_code=0
```

The semantic writes were operator-mediated and scoped to:

```text
operations/harness-knowledge-pipeline/runs/admission-policy-semantic-handoff-001/output/
```

Generated run artifacts remain local evidence and are not committed by this docs-only marker.

## B. Accepted semantic artifacts

The successful handoff used the expected seven semantic artifacts under `output/`:

```text
normalized_note.md
normalized_note.json
result_packet.json
placement_decision.candidate.json
admission_decision.candidate.json
canonical_knowledge_candidate.md
wiki_derived_draft.md
```

The markdown artifacts are accepted as generated semantic handoff artifacts only. They are not canonical KB writes.

## C. Validated checks

The `semantic-required` validation accepted the handoff with `exit_code=0` after checking:

- schema validation for JSON artifacts;
- semantic artifact set mapping;
- markdown presence/non-empty;
- ref integrity;
- output path boundary;
- no outside-Git paths;
- no automatic canonical write;
- no live surface flags.

The accepted JSON artifact schemas are the harness-local PR71 contracts under:

```text
operations/harness-knowledge-pipeline/contracts/
```

## D. Boundaries

This evidence run preserves the current knowledge-pipeline boundaries:

- generated run artifacts remain local/ignored unless explicitly requested otherwise;
- no canonical KB admission was performed;
- the admission decision candidate remained `hold`;
- no OpenClaw use;
- no Docker use;
- no live/apply/rollout action;
- no Hermes config/skills/memory/SOUL changes;
- no external URL capture;
- no automatic canonical write.

## E. What this proves

This evidence proves the repo-native manual semantic handoff contour works end-to-end:

1. the runner can create a capture-only run from a repo-local source;
2. a Hermes/LLM operator can fill the expected semantic artifacts according to the PR71 schemas;
3. the runner can validate those artifacts in `semantic-required` mode;
4. a complete valid manual handoff reaches `exit_code=0`;
5. the contour remains bounded to repo-local evidence and run-dir semantic outputs.

## F. What this does not prove

This evidence does not prove or accept:

- automatic semantic generation;
- external URL capture;
- canonical KB write;
- synthesis layer;
- Hermes skill auto-sync;
- live/apply/rollout behavior.

Any future work on those surfaces requires separate scope, implementation, review, and evidence.
