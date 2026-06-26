# KB_LAYOUT

## Purpose

Define the high-level layout and discipline for sanctioned assets in the live workspace KB.

This document lives in the repository so the control plane can document and govern KB storage discipline. It describes the live workspace KB layout, not a requirement that the full live KB corpus be stored in this repository.

## Storage boundary

The live KB corpus lives under the OpenClaw workspace KB root configured at runtime.

The repository path `knowledge/kb/` documents layout, admission discipline, and curated examples only. It must not be treated as the storage location for the full live KB corpus.

Examples in this document are illustrative path shapes only. They are not live KB assets.

## Knowledge extraction profile references

Proposed knowledge extraction profile documentation lives in:

* `control-plane/policy/KNOWLEDGE_EXTRACTION_PROFILE_POLICY.md` - governance for agent-led extraction profiles and candidate/admission boundaries
* `knowledge/kb/KNOWLEDGE_ASSET_TYPES.md` - output asset type registry and template links
* `knowledge/kb/KNOWLEDGE_CANDIDATE_ADMISSION_RUNBOOK.md` - practical staging and Phase3 admission workflow for prepared knowledge candidates
* `knowledge/kb/asset-templates/` - markdown templates for agent-prepared knowledge candidates and future admitted knowledge assets
* `knowledge/kb/extraction-profiles/` - Domain Extraction Profiles that define agreed data structures for agent-led extraction

These references describe structures, profiles, and templates only. They do not change live KB layout semantics, authorize KB admission, add runtime behavior, or make Phase perform semantic extraction.

## Knowledge distillation flow matrix

The canonical repository defines the generic Knowledge Distillation Flow Matrix contract in `knowledge/kb/KNOWLEDGE_DISTILLATION_FLOW_MATRIX.md`.

The active matrix is instance-local configuration. It declares allowed semantic transformation routes between accepted source captures and admitted knowledge assets. It controls which transformations an agent may attempt, not physical storage by itself.

Actual knowledge assets still use the typed domain-first placement model:

```text
<domain-area>/<publisher-id-or-source-family-id>/knowledge/<knowledge-type>/<asset-slug>/
```

Concrete matrix nodes, flows, `knowledge_type` values, and `knowledge_profile_id` values belong to the deployed instance, not to the canonical repository.

## Repo-defined live KB top-level layout

The workspace KB root uses a domain-first layout.

The first level under the workspace KB root is the domain area. The second level is the publisher, source family, or resource family. Asset layers live under that domain/source-family container:

* `sources/` - source-bearing assets and source capture packages
* `knowledge/` - canonical knowledge assets
* `collections/` - repo-defined prefix for curated groupings; reserved by default unless explicitly needed

Canonical container shape:

```text
<domain-area>/<publisher-id-or-source-family-id>/
```

Example:

```text
cosmetics-household-chemistry/humblebee-and-me/
```

## Asset classes

### Source-bearing assets

Primary purpose: preserve external source material and provenance in stable form.

Minimum required provenance:

* canonical pointer
* retrieval status
* retrieval timestamp
* content type
* stable representation
* human identifier
* linkage to related note, task, or review identifiers where relevant

A source admission creates a source-bearing asset. It does not create a canonical knowledge asset.

A captured page, stable source representation, or source capture package is not semantic extraction simply because it is useful for future retrieval or synthesis.

### Knowledge assets

Primary purpose: express reusable understanding, synthesis, or structured knowledge for retrieval.

Minimum expectations:

* clear knowledge role or type
* intelligible content without hidden workflow context
* source linkage where claims depend on external evidence
* review outcome suitable for KB placement
* stable identifier for retrieval and maintenance

Knowledge assets are separate from source-bearing assets. They require their own review and admission path.

## Domain-first live paths

Live KB paths use the domain/source-family container first, then the asset layer:

```text
<domain-area>/<publisher-id-or-source-family-id>/sources/<asset-slug>-<YYYYMMDD>/
<domain-area>/<publisher-id-or-source-family-id>/knowledge/<knowledge-type>/<asset-slug>/
<domain-area>/<publisher-id-or-source-family-id>/collections/<collection-id>/
```

For Humblebee & Me:

```text
cosmetics-household-chemistry/humblebee-and-me/sources/<asset-slug>-<YYYYMMDD>/
cosmetics-household-chemistry/humblebee-and-me/knowledge/<knowledge-type>/<asset-slug>/
cosmetics-household-chemistry/humblebee-and-me/collections/<collection-id>/
```

For knowledge assets, `<knowledge-type>` is an instance-local placement taxonomy segment. The repository defines the typed placement shape and validation interface, but it does not define a canonical taxonomy of concrete knowledge type values. Local KB instance configuration owns allowed knowledge types and mappings from `knowledge_profile_id` to allowed `knowledge_type` values.

`asset_id` remains the stable globally traceable identity and may differ from `<asset-slug>`. `asset_slug` and `knowledge_type` are placement metadata only; they are not lineage fields and must not be derived by parsing the destination path.

Do not use the older role-first layout for new live assets:

```text
sources/<domain-area>/<publisher-id-or-source-family-id>/...
knowledge/<domain-area>/<topic-id>/...
collections/<collection-id>/...
```

## Domain-first non-live and process paths

Non-live workflow and process paths also use the same domain/source-family container:

```text
<domain-area>/<publisher-id-or-source-family-id>/workflow/<run-id>/
<domain-area>/<publisher-id-or-source-family-id>/raw/
<domain-area>/<publisher-id-or-source-family-id>/proofs/
<domain-area>/<publisher-id-or-source-family-id>/distilled/
```

These process areas are not live KB retrieval layers:

* `workflow/` - preparation, manifests, and process evidence for a run
* `raw/` - archive or capture material; non-live by default
* `proofs/` - derivation notes, drafts, validation materials, and other non-live proof artifacts
* `distilled/` - legacy ambiguous layer; do not develop further

Do not represent legacy paths as recommended live storage.

## Raw storage nuance

A `raw/` directory directly under a domain/source-family container is a non-live archive area. It is not a live KB asset layer.

Raw source files can appear inside an admitted source-bearing asset when they are part of that asset's package and provenance, for example:

```text
<domain-area>/<publisher-id-or-source-family-id>/sources/<asset-slug>-<YYYYMMDD>/raw/source.html
```

That nested `raw/` directory is allowed only as part of an admitted source-bearing asset with package/provenance. Do not use raw examples as live KB assets, and do not use `sources/.../raw/` as a loose dump for unreviewed material.

## Source containers and archives

A section, category, archive, folder, or bundle is a source container by default.

A container should normally be expanded into discrete child source candidates. Each child source should be admitted separately as its own source-bearing asset.

A container may produce manifest or workflow evidence, such as a list of discovered child URLs or files. That evidence must not replace child-level source admissions.

## Collections

Collections organize sanctioned assets for retrieval or navigation. They do not represent tasks, queues, approvals, or mutable operational ownership.

The `collections/` layer is repo-defined but reserved by default. Use it only when a collection is explicitly needed and the collection content is made of sanctioned assets.

## Discipline

* KB stores sanctioned assets only.
* New KB writes use domain/source-family-first layout.
* Source-bearing assets and knowledge assets must stay distinguishable.
* Source admission does not create a knowledge asset.
* Captured source material is not semantic extraction.
* Raw workflow and task objects do not belong in the live KB because they encode transient operational state, not reusable sanctioned knowledge.
* Draft semantic notes stay outside the live KB until reviewed and admitted.
* Full live corpus payloads belong in the runtime-configured workspace KB root, not in this repository, unless explicitly curated as examples.
* This document defines layout discipline only; enforcement, validators, migrations, and cleanup are future work unless a later PR explicitly adds them.
