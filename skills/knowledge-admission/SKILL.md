---
name: knowledge-admission
description: Prepare agent-owned knowledge extraction outputs from accepted provenance-bearing sources for canonical crab-control-plane/OpenClaw workspace KB admission. Use when a registered knowledge_profile_id exists and the user wants reusable knowledge prepared for KB admission. Semantic extraction is agent-owned; Admission and Phase validate contracts, placement, execution, hashes, and evidence, not semantic correctness.
---

# Knowledge Admission

Prepare **knowledge assets** for canonical KB admission from accepted provenance-bearing sources.

This skill is a preparation and routing policy. It does not admit anything by itself and does not validate semantic correctness.

Canonical route:

```text
accepted provenance-bearing source
→ select instance-registered knowledge_profile_id
→ agent-owned semantic extraction
→ knowledge candidate
→ admission-authorized knowledge package
→ Admission Stage 1 package and authorization artifact
→ instance-local typed placement
→ Phase3 manifest and execution target
→ Admission Stage 2 handoff
→ standalone admission preflight
→ accepted exact-HEAD Phase2 baseline
→ Phase4 default wrapper
→ Phase3 kb_admission
→ canonical Phase3 evidence
→ later semantic review in wiki layer
```

Phase3 remains the sole canonical execution owner. Phase4 is the default invocation route. Phase2 checks exact-HEAD repo/control-plane readiness. Admission Stage 1 and Stage 2 are contract layers, not runtime phases.

## Repository And Runtime Locations

Prefer the canonical repository checkout:

```text
/home/node/.openclaw/workspace/repos/crab-control-plane
```

The live KB corpus is normally under `OPENCLAW_WORKSPACE_KB_ROOT` or:

```text
/home/node/.openclaw/workspace/kb
```

Repository `knowledge/kb/` contains documentation, templates, profiles, and examples. It is not the live KB corpus.

## Activation

Use knowledge-admission mode when:

- the user asks to extract, distil, or prepare reusable knowledge from an accepted provenance-bearing source;
- the result is intended for canonical KB admission;
- an instance-registered and sufficiently defined `knowledge_profile_id` exists.

Do not start canonical admission when the user asks only for transient analysis, summary, discussion, draft extraction, or source capture.

If the source has not been accepted or admitted, stop and report that source admission is the prerequisite. Route to `source-admission` when the user wants to capture or admit the source.

## Responsibilities

The agent must:

1. identify the exact source asset and provenance;
2. choose an explicit instance-registered `knowledge_profile_id`;
3. follow the instance-local instruction referenced by that profile;
4. prepare the semantic extraction as a working candidate;
5. separate directly source-stated material, agent interpretation, inferred content, not stated, and not validated;
6. finalize bytes suitable for an admission-authorized knowledge package;
7. establish a new stable knowledge `asset_id`;
8. retain source lineage without reusing the source asset ID as the knowledge asset ID;
9. choose placement-only `asset_slug`;
10. load the explicit instance taxonomy config;
11. choose an allowed placement-only `knowledge_type`;
12. prepare the universal Stage 1 and Stage 2 artifacts;
13. run standalone admission preflight;
14. check or create the exact-HEAD Phase2 baseline;
15. invoke Phase4 by default;
16. verify Phase3 canonical evidence and admitted hashes.

## Profile Selection

Select a concrete `knowledge_profile_id` from the instance registry supplied by:

```text
ADMISSION_KNOWLEDGE_PROFILE_REGISTRY
```

The canonical repository supplies the generic profile contract:

```text
profile_contract_id: knowledge_extraction.v1
```

The concrete `knowledge_profile_id` is instance-defined, for example only `<instance-defined-profile-id>`.

The instance registry entry points to an instance-local instruction and selected output template. Follow that instruction and use that template.

The profile entry is routing and instruction metadata, not a semantic validator. Do not branch into custom admission logic by profile.

The presence of a generic template mechanism does not activate a concrete profile. Concrete profile registration and concrete output-template selection are instance-local.

## Semantic Boundary

Semantic extraction is agent-owned.

Admission, Phase2, Phase3, and Phase4 do not validate semantic correctness, domain-specific correctness, domain-specific safety or compliance, expert validation, vocabulary truth, or whether extracted claims are correct.

The required `review-decision.json` is admission authorization and placement authorization. It confirms that the final prepared bytes may proceed into the controlled admission path. It is not semantic review, independent expert review, validation of extracted claims, or proof that the extraction is correct.

Semantic review is deferred to the later wiki/semantic layer.

## Claim Discipline

The candidate and final package must distinguish:

- directly source-stated material;
- agent interpretation grounded in source evidence;
- inferred content;
- not stated;
- not validated.

Unsupported claims must be removed, narrowed, or marked as inferred, not stated, or not validated. Do not submit bytes to Phase if they still contain temporary candidate-only status that becomes false after admission.

## Placement Model

For knowledge assets:

```text
<domain-area>/<source-family-id>/knowledge/<knowledge-type>/<asset-slug>/
```

Rules:

- `asset_id` is stable global identity and lineage.
- `asset_slug` is a source-family-local placement segment.
- `knowledge_type` is an instance-local placement taxonomy segment.
- Neither `asset_slug` nor `knowledge_type` belongs in lineage identity.
- Do not derive `knowledge_type` from profile ID, asset ID, slug, or destination path.
- Do not hardcode a repository-owned knowledge taxonomy.

The repository must not define canonical values such as recipe, component, formulation, or product type.

## Local Taxonomy Config

Real knowledge admission requires:

```text
ADMISSION_KB_TAXONOMY_CONFIG=/path/to/instance/kb-taxonomy-config.json
```

The config path is explicit. Absolute paths are accepted. Relative paths resolve against the repository root supplied to the standalone checker. Missing, nonexistent, non-file, invalid, schema-invalid, or unauthorized selected profile/type config fails closed. The canonical repository does not own active instance taxonomy values, and physical filesystem containment is not enforced by the checker.

The selected `knowledge_profile_id -> knowledge_type` mapping must be allowed by the instance-local config.

## Required Artifacts

Prepare:

- `admission_package.json` with `admission_kind: knowledge_asset`, `profile_id: knowledge_asset.v1`, stable `asset_id`, instance-registered `knowledge_profile_id`, package-relative `payload_path`, and opaque non-empty `profile_data`;
- canonical `review-decision.json` with `decision: approve`, matching `artifact_id`, and `approved_destination: kb`;
- Phase3 `admission_manifest.json`;
- Phase3 `execution_target.json`;
- Admission Stage 2 `admission_handoff.json` with typed placement and references to the already existing package, authorization, manifest, and execution target.

Run standalone preflight after all referenced files exist:

```bash
ADMISSION_KNOWLEDGE_PROFILE_REGISTRY=/path/to/instance/knowledge-profile-registry.json \
ADMISSION_KB_TAXONOMY_CONFIG=/path/to/instance/kb-taxonomy-config.json \
python3 operations/harness-phase2/bin/check_admission_policy.py \
  /home/node/.openclaw/workspace/repos/crab-control-plane \
  /path/to/knowledge-admission-proof/admission_handoff.json
```

## Phase2 Baseline Rule

Reuse a Phase2 baseline only when:

1. the Phase2 run completed successfully;
2. its canonical report and handoff-readiness result are passing;
3. the tracked repository working tree is clean;
4. the operator or batch runner recorded the exact repository Git HEAD when the baseline was accepted;
5. the current repository Git HEAD exactly equals that recorded HEAD.

Any new repository commit makes the previous Phase2 baseline stale. No operator override may permit reuse across different Git HEADs.

Allowed claim:

```text
Accepted Phase2 baseline <RUN_ID> was created for and reused at repository HEAD <SHA>.
```

## Phase4 And Phase3

Phase4 is the default operator-facing invocation route.

Do not invoke Phase3 directly during normal knowledge admission.

Phase3 `kb_admission` is the sole canonical execution and evidence owner. Only Phase3 freezes execution inputs. Phase4 does not own canonical execution evidence. Phase2 baseline readiness is not admission.

Do not claim admission until Phase3 succeeds, emits canonical evidence, and the admitted destination hashes match expected values.

### Exceptional Direct Phase3 Fallback

Direct Phase3 use is allowed only when Phase4 is unavailable or defective, the limitation is reported, and the operator explicitly approves the fallback.

The final report must record why Phase4 was not used, who approved direct Phase3 execution, the canonical Phase3 run directory, and that no Phase4 wrapper metadata exists. Use existing Phase contracts for command details.

### Future Shared Procedure

When the shared Phase admission procedure Skill exists, use it for standalone preflight, Phase2, Phase4, Phase3, freeze, fallback, evidence, and reporting details instead of duplicating those procedures here.

## Fail Closed

Stop before Phase execution when:

- source identity or provenance is missing;
- the selected profile is absent, placeholder-only, or lacks a usable instruction document;
- the candidate contains unsupported claims presented as source facts;
- final bytes still contain temporary candidate-only status;
- admission authorization is missing;
- local taxonomy config is missing, nonexistent, not a file, invalid JSON, schema-invalid, or disallows the selected profile/type mapping;
- typed destination is unresolved;
- expected hashes are missing or inconsistent;
- exact-HEAD Phase2 baseline is unavailable and cannot be created;
- Phase4 or Phase3 prerequisites are unresolved.

## Contract References

Use these canonical contracts instead of duplicating generic route details:

- `docs/ADMISSION_CONTRACT.md`
- `docs/ADMISSION_STAGE2_CONTRACT.md`
- `docs/ADMISSION_CHECK_OWNERSHIP.md`
- `operations/admission/README.md`
- `knowledge/kb/KB_LAYOUT.md`
- `knowledge/kb/KNOWLEDGE_CANDIDATE_ADMISSION_RUNBOOK.md`
- `operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md`
- `operations/harness-phase3/PHASE3_EXECUTION_CONTRACT.md`

## Allowed claims

- Prepared a knowledge candidate using `<knowledge_profile_id>`.
- Prepared an admission-authorized knowledge package.
- Standalone admission preflight passed.
- Accepted Phase2 baseline `<RUN_ID>` matches repository HEAD `<SHA>`.
- Phase4 invoked Phase3.
- Phase3 admitted the knowledge artifact and emitted canonical evidence under `<RUN_DIR>`.
- The admitted destination hash matches the expected SHA-256.

## Forbidden claims

- The Skill admitted the knowledge.
- Phase2 admitted the knowledge.
- Phase4 admitted the knowledge.
- Phase validated semantic correctness.
- Admission authorization proves semantic review.
- The knowledge is admitted before successful Phase3 evidence exists.

## Required Final Report

Include:

- source asset reference;
- `knowledge_profile_id`;
- knowledge `asset_id`;
- `asset_slug`;
- `knowledge_type`;
- typed destination;
- standalone preflight status;
- accepted Phase2 baseline run and exact repo HEAD;
- Phase4 wrapper run or approved fallback reason;
- Phase3 canonical run directory and exit status;
- admitted destination path;
- expected and observed SHA-256;
- limits or unresolved blockers.
