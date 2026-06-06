# KB_LAYOUT

## Purpose

Define the high-level layout and discipline for sanctioned assets in the live workspace KB.

This document lives in the repository so the control plane can document and govern KB storage discipline. It describes the live workspace KB layout, not a requirement that the full live KB corpus be stored in this repository.

## Storage boundary

The live KB corpus lives under the OpenClaw workspace KB root configured at runtime.

The repository path `knowledge/kb/` documents layout, admission discipline, and curated examples only. It must not be treated as the storage location for the full live KB corpus.

Examples in this document are illustrative path shapes only. They are not live KB assets.

## Repo-defined live KB top-level layout

The workspace KB root uses these repo-defined top-level layout entries:

* `sources/` - source-bearing assets and source capture packages
* `knowledge/` - canonical knowledge assets
* `collections/` - repo-defined prefix for curated groupings; reserved by default unless explicitly needed

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

A captured page, stable source representation, or source capture package is not semantic distillation simply because it is useful for future retrieval or synthesis.

### Knowledge assets

Primary purpose: express reusable understanding, synthesis, or structured knowledge for retrieval.

Minimum expectations:

* clear knowledge role or type
* intelligible content without hidden workflow context
* source linkage where claims depend on external evidence
* review outcome suitable for KB placement
* stable identifier for retrieval and maintenance

Knowledge assets are separate from source-bearing assets. They require their own review and admission path.

## Prefix-first live paths

Live KB paths use the top-level role prefix first:

```text
sources/<domain-area>/<publisher-id-or-source-family-id>/<asset-slug>-<YYYYMMDD>/
knowledge/<domain-area>/<topic-id>/<asset-id>/
collections/<collection-id>/
```

The domain area belongs immediately after the live prefix. Do not invert the path into domain-first shapes such as `<domain-area>/sources/...`.

## Prefix-first non-live and process paths

Non-live workflow and process paths also use prefix-first layout discipline:

```text
workflow/<domain-area>/<publisher-id-or-source-family-id>/<run-id>/
raw/
proofs/
distilled/
```

These process areas are not live KB retrieval layers:

* `workflow/` - preparation, manifests, and process evidence for a run
* `raw/` - top-level archive or capture material; non-live by default
* `proofs/` - derivation notes, drafts, validation materials, and other non-live proof artifacts
* `distilled/` - legacy ambiguous layer; do not develop further

Do not represent legacy paths as recommended live storage.

## Raw storage nuance

Top-level `raw/` is a non-live archive area. It is not a live KB asset layer.

Raw source files can appear inside an admitted source-bearing asset when they are part of that asset's package and provenance, for example:

```text
sources/<domain-area>/<publisher-id-or-source-family-id>/<asset-slug>-<YYYYMMDD>/raw/source.html
```

That nested `raw/` directory is allowed only as part of an admitted source-bearing asset with package/provenance. Do not use raw examples as live KB assets, and do not use `sources/.../raw/` as a loose dump for unreviewed material.

## Source containers and archives

A section, category, archive, folder, or bundle is a source container by default.

A container should normally be expanded into discrete child source candidates. Each child source should be admitted separately as its own source-bearing asset.

A container may produce manifest or workflow evidence, such as a list of discovered child URLs or files. That evidence must not replace child-level source admissions.

## Collections

Collections organize sanctioned assets for retrieval or navigation. They do not represent tasks, queues, approvals, or mutable operational ownership.

The `collections/` prefix is repo-defined but reserved by default. Use it only when a collection is explicitly needed and the collection content is made of sanctioned assets.

## Discipline

* KB stores sanctioned assets only.
* Source-bearing assets and knowledge assets must stay distinguishable.
* Source admission does not create a knowledge asset.
* Captured source material is not semantic distillation.
* Raw workflow and task objects do not belong in the live KB because they encode transient operational state, not reusable sanctioned knowledge.
* Draft semantic notes stay outside the live KB until reviewed and admitted.
* Full live corpus payloads belong in the runtime-configured workspace KB root, not in this repository, unless explicitly curated as examples.
* This document defines layout discipline only; enforcement, validators, migrations, and cleanup are future work unless a later PR explicitly adds them.
