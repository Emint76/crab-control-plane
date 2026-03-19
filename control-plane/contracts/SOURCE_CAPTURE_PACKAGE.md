# SOURCE_CAPTURE_PACKAGE

Minimum provenance package for a captured source.

## Purpose
Provide the minimum stable and reviewable representation of an external source so it can be trusted, cited, and later admitted as a source-bearing KB asset.

## Field semantics
- `source_id`: stable source identifier.
- `canonical_pointer`: original source locator such as a URL, document identifier, or repository path.
- `retrieval_status`: outcome of retrieval using a constrained status vocabulary.
- `retrieval_timestamp`: timestamp of the retrieval event in RFC 3339 format.
- `content_type`: captured content type.
- `stable_representation`: durable stored form used for later retrieval or inspection.
- `human_identifier`: readable label for operators and reviewers.
- `provenance_notes`: concise notes about capture conditions or limitations.
- `linkage`: related note, task, result, or asset identifiers.
- `capture_method`: coarse description of how the source was obtained.
- `hash`: optional content hash for integrity checking.

## Required fields
- `source_id`
- `canonical_pointer`
- `retrieval_status`
- `retrieval_timestamp`
- `content_type`
- `stable_representation`
- `human_identifier`

## Optional fields
- `provenance_notes`
- `linkage`
- `capture_method`
- `hash`

## Validation notes
- Stable representation must identify a retrievable preserved form, not only the volatile source pointer.
- Retrieval status should use a bounded vocabulary rather than arbitrary text.
- Timestamps must be machine-readable.
- Linkage should preserve enough identifiers to connect the package to notes, tasks, or review artifacts.

## Example object explanation
See `examples/sample-source-capture-package.json`.
- The example records the original pointer, retrieval status, timestamp, and local archive path.
- Its linkage points to a related note identifier, preserving provenance across layers.

## Workflow relation
- Produced during source capture or ingestion.
- Reviewed for provenance sufficiency before KB admission.
- Used later during retrieval to justify knowledge claims and to inspect the preserved source.
