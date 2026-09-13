# Slice 1 — artifact metadata and run-root allocation

## Purpose

Give every active typed value enough provenance for generated submit to find source payloads and allocate destination payloads.

## Status

Complete. Runtime metadata, fresh model/join roots, submit working-directory
plumbing, and composition coverage are implemented.

## Files

- `src/vecherinka_runtime.nim`
- `src/vecherinka_comptime.nim`
- runtime execution tests

## Work

1. Add `ArtifactID` and `ArtifactMeta`.
2. Extend `RuntimeContext` with:
   - runtime directory (program CWD, the base for `Location` values);
   - run directory;
   - next artifact ID;
   - optional `CodexRuntime` owner pointer;
   - pending agent-start records.
3. Create one run directory during `execute_flows`.
4. Add allocator returning fresh `artifact-N` directory and metadata.
5. Seed entry activation with source root equal to current working directory.
6. Add metadata to `Activation` and `WorkNode`.
7. Add metadata to pending model state and runtime/global events.
8. Change `Flow.fk_model.submit` boundary to accept input metadata and the
   fresh model working directory.
9. Preserve metadata through immediate `fk_it`, `fk_so`, and raw continuation paths.
10. Allocate the output artifact directory before calling `submit`; store its
    metadata in pending and completed model state.

## Important invariant

Typed artifact payload remains separate from filesystem provenance. Relative
`Location` strings resolve from the common runtime directory, never from an
individual artifact directory and never become absolute model-facing values.

## Test gate

Add tests that:

- entry input receives current-directory metadata;
- model allocation creates distinct roots for two model calls;
- `it` preserves metadata;
- `so` child receives metadata;
- work-node input/output metadata is recorded;
- runtime event preserves metadata through channel serialization fields;
- source root remains unchanged after allocation.
- submit receives the pre-created working directory.

## Rollback point

Metadata fields can be removed without changing generated artifact union layout if this slice stays isolated.
