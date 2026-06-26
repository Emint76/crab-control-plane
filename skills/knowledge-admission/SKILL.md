---
name: knowledge-admission
description: Prepare agent-owned knowledge extraction outputs from accepted provenance-bearing input assets for canonical crab-control-plane/OpenClaw workspace KB admission. Use when an active instance Knowledge Distillation Flow Matrix flow and registered knowledge_profile_id exist and the user wants reusable knowledge prepared for KB admission. Semantic extraction is agent-owned; Admission and Phase validate contracts, placement, execution, hashes, and evidence, not semantic correctness.
---

# Knowledge Admission

Prepare **knowledge assets** for canonical KB admission from accepted provenance-bearing input assets.

This skill is a preparation and routing policy. It does not admit anything by itself and does not validate semantic correctness.

Canonical route:

```text
accepted provenance-bearing input asset
→ select active instance distillation flow
→ select the flow-defined knowledge_profile_id
→ use the output node knowledge_type
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

- the user asks to extract, distil, or prepare reusable knowledge from an accepted provenance-bearing input asset;
- the result is intended for canonical KB admission;
- an explicit instance Knowledge Distillation Flow Matrix is available;
- an active flow authorizes the requested transformation;
- an instance-registered and sufficiently defined `knowledge_profile_id` exists.

Do not start canonical admission when the user asks only for transient analysis, summary, discussion, draft extraction, or source capture.

Inputs may be accepted `source_capture` assets or already admitted `knowledge_asset` assets. For a knowledge-to-knowledge flow, the input knowledge asset must already have successful canonical Phase3 admission evidence.

If the source has not been accepted or admitted, stop and report that source admission is the prerequisite. Route to `source-admission` when the user wants to capture or admit the source. Do not mutate any upstream input asset.

## Responsibilities

The agent must:

1. identify the exact input asset and provenance;
2. determine the input asset kind;
3. load the explicit instance Knowledge Distillation Flow Matrix;
4. determine the input node and requested output node;
5. select one active flow or ordered active path authorized by the matrix;
6. select each hop's flow-defined `knowledge_profile_id`;
7. use each hop's output node `knowledge_type`;
8. follow the instance-local instruction referenced by that profile;
9. prepare the semantic extraction as a working candidate;
10. separate directly source-stated material, agent interpretation, inferred content, not stated, and not validated;
11. finalize bytes suitable for an admission-authorized knowledge package;
12. establish a new stable knowledge `asset_id`;
13. retain direct lineage to the actual input asset and transitive lineage back to originating source assets;
14. choose placement-only `asset_slug`;
15. load the explicit instance taxonomy config;
16. prepare the universal Stage 1 and Stage 2 artifacts;
17. run standalone admission preflight;
18. check or create the exact-HEAD Phase2 baseline;
19. invoke Phase4 by default;
20. verify Phase3 canonical evidence and admitted hashes.

## Distillation Flow Matrix

Real knowledge admission requires an explicit instance matrix:

```text
KNOWLEDGE_DISTILLATION_FLOW_MATRIX=/path/to/instance/knowledge-distillation-flow-matrix.json
```

The canonical contract is `knowledge_distillation_flow_matrix.v1`. The canonical repository defines the generic matrix contract and placeholder template only. The deployed instance owns concrete nodes, flows, `knowledge_type` values, `knowledge_profile_id` values, extraction instructions, output templates, and the active matrix.

The matrix is a directed graph:

- nodes describe instance-defined input and output asset classes;
- flows declare allowed semantic transformation routes;
- each flow is exactly one edge from one declared input node to one declared output node;
- only `active` flows may be executed;
- draft or disabled flows must not be executed or silently activated;
- the flow-defined `knowledge_profile_id` selects the instance profile;
- the output node's `knowledge_type` selects the requested placement type.

The flow matrix is not the profile registry and not the taxonomy config:

```text
flow matrix = allowed semantic transformation routes
profile registry = instructions and output template for a selected transformation
taxonomy config = allowed physical placement mapping from knowledge_profile_id to knowledge_type
```

## Flow Selection

The agent must:

1. identify the exact input asset;
2. determine whether it is `source_capture` or `knowledge_asset`;
3. determine the input node in the instance matrix;
4. determine the requested output node;
5. load the explicit instance matrix;
6. find matching active flows;
7. select the flow-defined `knowledge_profile_id`;
8. use the output node's `knowledge_type`;
9. preserve direct and transitive lineage;
10. continue through the existing knowledge-admission process.

## Node Resolution

A concrete input asset must be mapped to a declared matrix input node before flow selection.

For an admitted `knowledge_asset`, `asset_kind` and its admitted `knowledge_type` may identify the node.

For a `source_capture`, or whenever several nodes match the same asset characteristics, node selection is not automatically unique.

If exactly one declared node matches, the agent may use it.

If multiple declared nodes match, the agent must stop and ask the user to select the input node, output node, or concrete flow.

The same ambiguity rule applies to requested output-node resolution.

Flow execution begins only after both input and output nodes are unambiguous.

The agent must not guess a node from folder name, source-family name, asset ID, asset slug, profile ID, or undocumented semantic interpretation.

If exactly one active direct flow matches the requested input and output nodes, use it.

If multiple direct flows match and the request does not disambiguate them, stop and ask the user to choose the route.

If no active direct flow matches, determine whether the requested result requires a connected multi-step path. Do not invent a direct shortcut.

If no active direct flow or connected active path exists, stop and report that the instance matrix does not authorize the requested distillation.

Do not infer a flow from folder names, profile IDs, asset IDs, slugs, or knowledge types.

## Multi-Step Paths

A downstream result may require an ordered sequence of connected active flows. Path order is derived from graph connectivity, where each flow's output node is the next flow's input node.

A path considered for one user request must be finite and simple. The same `flow_id` must not occur more than once in one path. The same `node_id` must not occur more than once in one path.

The agent must not execute a cyclic or indefinitely repeating path. A matrix may contain cycles for separately requested transformations, but one execution request must not traverse a cycle.

Exactly one active path means exactly one matching finite simple active path.

If exactly one finite simple active path matches and all referenced profiles are already registered and usable, the agent may proceed through that path in response to the user's downstream request.

If path resolution remains ambiguous because of cycles or several simple paths, stop and ask the user to choose.

Process one flow at a time:

```text
input asset
→ execute one active flow
→ prepare knowledge candidate
→ run normal knowledge admission
→ obtain successful Phase3 evidence
→ use admitted output as the next input asset
→ execute the next active flow
```

Every hop produces a separate knowledge asset with its own candidate, admission package, typed destination, Phase execution, and canonical evidence. The next hop may begin only after successful Phase3 evidence for the previous hop.

Each flow in a path has its own `knowledge_profile_id`. Each hop uses that flow's profile and output-node `knowledge_type`. Profile availability and usability are checked separately before each hop. A later hop does not inherit the preceding hop's profile.

Do not combine several hops into one knowledge candidate, one admission package, or one Phase execution. Do not use an unadmitted intermediate candidate as canonical input to a downstream flow.

Graph reachability does not authorize an undeclared direct flow. If the matrix declares `node A -> node B` and `node B -> node C`, the agent must not execute `node A -> node C` unless a separate active direct flow from `node A` to `node C` is declared.

## Branching And Multiple Incoming Flows

The matrix may contain branching paths and multiple independent incoming flows to the same output node.

Each incoming flow is independently selectable. Each execution uses one actual input asset, and the resulting output asset preserves lineage to that actual input.

Multiple flows targeting the same output node do not imply semantic equivalence. Admission and Phase do not reconcile conflicting or overlapping results. Semantic reconciliation remains the responsibility of the later wiki/semantic layer.

## Profile Selection

Select a concrete `knowledge_profile_id` from the instance registry supplied by:

```text
ADMISSION_KNOWLEDGE_PROFILE_REGISTRY
```

The canonical repository supplies the generic profile contract:

```text
profile_contract_id: knowledge_extraction.v1
```

The concrete `knowledge_profile_id` is instance-defined, for example only `<instance-defined-profile-id>`. In normal operation it is selected from the active flow, not invented from the destination path or requested `knowledge_type`.

The instance registry entry points to an instance-local instruction and selected output template. Follow that instruction and use that template.

The profile entry is routing and instruction metadata, not a semantic validator. Do not branch into custom admission logic by profile.

The presence of a generic template mechanism does not activate a concrete profile. Concrete profile registration and concrete output-template selection are instance-local.

The selected flow's `knowledge_profile_id` must already be registered and usable. If the referenced profile is absent, placeholder-only, missing a usable instruction, or missing a selected output template, stop before extraction and admission.

The agent may prepare a draft profile, draft instruction, or draft output template for user review. It must then stop and request explicit user approval. Do not draft a profile, register it, and execute it in the same uninterrupted run without explicit user approval. After approval, registration and later reuse remain instance-local operations.

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

- input asset identity or provenance is missing;
- the explicit instance Knowledge Distillation Flow Matrix is missing, invalid, or unavailable;
- no active direct flow or connected active path authorizes the requested distillation;
- multiple matching flows or paths are ambiguous and the user has not selected the route;
- the requested flow is draft or disabled;
- the selected profile is absent, placeholder-only, or lacks a usable instruction document;
- a newly drafted profile has not been explicitly approved before registration and later use;
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
- `knowledge/kb/KNOWLEDGE_DISTILLATION_FLOW_MATRIX.md`
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

- input asset reference;
- input asset kind;
- selected matrix ID and flow ID or ordered path;
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
