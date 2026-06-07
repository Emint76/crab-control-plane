# KNOWLEDGE_EXTRACTION_PROFILE_POLICY

## Purpose

Define governance for Knowledge Extraction Profiles and Domain Extraction Profiles as agreed data structures for agent-led semantic extraction.

This is a corrective documentation policy. It does not add runtime behavior, Phase behavior, schemas, validators, source admission, knowledge admission, or live KB writes.

## Core model

Semantic work in this control plane remains agent-owned.

The agent:

- reads source material;
- understands domain content;
- proposes an extraction profile or data structure;
- incorporates user or reviewer approval/refinement of that structure;
- extracts knowledge candidates according to the agreed structure.

Phase does not perform semantic extraction, validate semantic correctness, or validate domain expertise. Phase 3 `kb_admission` performs controlled admission of already prepared artifacts only: freeze inputs, validate paths and manifests, verify hashes, copy byte-for-byte, emit evidence, and fail closed.

## Definitions

### Knowledge Extraction Profile

A Knowledge Extraction Profile defines the agreed output structure for agent-led extraction from provenance-bearing sources. It may specify fields, tables, entity types, relationships, claim categories, provenance requirements, and status boundaries.

A Knowledge Extraction Profile is not an admission decision and does not authorize KB placement.

### Domain Extraction Profile

A Domain Extraction Profile applies Knowledge Extraction Profile rules to a domain or task family. It defines domain/task scope, expected extracted entities, required fields, required tables, relationships, source handling, cautions, and claim-boundary rules.

A Domain Extraction Profile is an agreed structure for extraction, not proof of semantic correctness and not a KB admission mechanism.

### Data structure agreement

Data structure agreement is the user or reviewer approval/refinement of the proposed extraction profile before large-scale extraction. It answers: "Is this the right structure for the agent to use when extracting candidates?"

Data structure agreement is distinct from review decision.

- Profile approval = agreed extraction structure.
- Review decision = KB placement authorization.

Do not collapse these two gates.

### Knowledge candidate

A knowledge candidate is an agent-prepared extraction output. It may follow an approved extraction profile and may be ready for review, but it is not a sanctioned KB asset until a review decision and admission path authorize placement.

### Review decision

A review decision records candidate acceptability and may authorize KB placement when admission policy, placement policy, provenance, and asset expectations are satisfied.

### Phase-owned KB admission

Phase-owned KB admission starts after candidate preparation and review authorization. Phase 3 `kb_admission` admits prepared artifacts byte-for-byte according to the admission manifest. It proves controlled execution/admission evidence, not semantic correctness.

## Required lifecycle

```text
User defines domain/task
-> Agent proposes extraction profile / data structure
-> User or reviewer approves/refines the profile
-> Agent extracts knowledge candidates from admitted/reviewed/provenance-bearing sources
-> Review decision records candidate acceptability and placement authorization
-> Phase3 kb_admission admits the prepared candidate to the workspace KB
```

## Canonical formula

```text
Extraction profile defines the agreed data structure.
Agent performs semantic extraction.
Review decision authorizes KB placement.
Phase proves controlled admission evidence.
KB asset is the admitted sanctioned result.
```

## Invariants

- A source-bearing asset is not a knowledge asset.
- Captured source material is not semantic extraction.
- A knowledge candidate is not a sanctioned KB asset.
- Extraction profiles do not authorize KB admission.
- Profile approval means agreed extraction structure only.
- Review decision authorizes KB placement.
- Phase evidence proves controlled execution/admission, not semantic correctness.
- Phase does not perform semantic extraction.
- Phase does not validate semantic correctness.
- Phase does not validate domain expertise.
- Phase 3 `kb_admission` admits already prepared artifacts byte-for-byte.
- Source-stated, agent-interpreted, inferred, and not-stated content must be separated.
- Claims must be supported by provenance or explicitly marked as inferred, not stated, or not validated.
- The live KB corpus belongs under the runtime-configured workspace KB root, not this repository.

## What this repository defines

This repository may define:

- governance boundaries;
- expected extraction structures;
- extraction profile documentation;
- output asset type registries;
- markdown templates for candidates and future admitted assets;
- domain extraction profiles;
- illustrative path shapes.

This repository does not store the full live KB corpus and does not perform live extraction or admission through these docs.

## Extraction expectations

Agent-led extraction must keep these categories separate:

- directly stated source content;
- agent interpretation grounded in the source;
- inferred content;
- content not stated by the source;
- content not validated by the review path.

If evidence does not state a value, condition, relationship, validation outcome, or safety claim, the candidate must say so explicitly.

## Provenance expectations

A knowledge candidate must identify the evidence it depends on.

Minimum provenance expectations are:

- source family or publisher identifier;
- source title or human-readable source identifier;
- source URL or canonical pointer when applicable;
- source-bearing asset path when available;
- retrieval or capture status when available;
- hashes or stable representation identifiers when available;
- extraction workflow path or evidence reference when available;
- profile path or agreed structure reference when available.

Unsupported claims must be removed, constrained to the available evidence, or marked as inferred, not stated, or not validated.

## Review and admission boundary

Profile approval confirms the structure the agent should use for extraction. It does not approve any extracted candidate for KB placement.

Candidate review evaluates whether the prepared candidate is acceptable for its intended placement. A review decision is the artifact that may authorize KB placement.

Phase 3 `kb_admission` may then admit the already prepared candidate to the workspace KB by validating the manifest, verifying hashes, copying byte-for-byte, emitting evidence, and failing closed on mismatch.

## Phase boundary

Phase evidence may prove that a controlled process executed, copied the expected prepared artifacts, verified hashes, and produced admission evidence. It does not prove semantic correctness, scientific correctness, regulatory fitness, manufacturing fitness, or domain expert validation.

No extraction profile creates a new Phase target kind or changes Phase admission mechanics.

## Repository boundary

The live KB corpus belongs under the runtime-configured workspace KB root. Repository docs may show illustrative path shapes, but they are not live KB writes and are not repository storage targets for the full corpus.
