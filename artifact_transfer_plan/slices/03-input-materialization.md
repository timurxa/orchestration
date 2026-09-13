# Slice 3 — input materialization from resolved records

## Purpose

Restore the historical recursive materializer while keeping compile-time
walking and generated model input on ordinary A values.

## Status

Rework required after registry migration.

## Work

At model activation, runtime resolves input_id to ArtifactRecord[A], then calls
the existing generated materializer with record.data and record.meta.

Generated materializer behavior stays nearly unchanged:

- scalar, enum, object, tuple, variant, sequence, option, and distinct wrapper
  traversal;
- active variant branch only;
- one-based sequence paths;
- explicit absent-option marker;
- Location payload copy into fresh model working directory.

The materializer may keep its current processing signature:

    input: A
    input_meta: ArtifactMeta
    runtime_dir: Path
    artifact_dir: Path

ArtifactRecord is not emitted into generated code. input_meta is a resolved
field, not persistent paired runtime storage.

## Test gate

- Existing scalar/nested/variant/sequence/option/location tests pass.
- Materializer receives data from the registry lookup.
- Repeated model inputs copy independently.
- Missing or invalid sources fail before transport submission.
- Generated source contains no ArtifactRecord dependency.
