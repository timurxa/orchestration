# Slice 8 — composition and multi-root transfer

## Purpose

Prove artifact transfer across current flow composition, including branch boundaries.

## Status

Complete for composition and multi-root routing. Metadata survives sequential
models, `so`, fanout, lift, and distinct-root joins. Physical `Location`
copying remains part of input materialization in Slices 3 and 5.

## Files

- `src/vecherinka_runtime.nim`
- `src/vecherinka_comptime.nim` pack/unpack emitters
- composition tests

## Work

Sequential transfer:

1. Model A writes `result.txt`.
2. Model B receives typed output from A.
3. B receives `result.txt` under B's fresh root.
4. B returns new typed output.

Immediate transformations:

- `fk_it` preserves metadata;
- `fk_so` preserves metadata into child activation;
- raw values use current source root;
- lift preserves source root for non-model transformations.

Fanout/lift joins:

- same-root and distinct-root branch outputs are both addressable because
  `Location` values are relative to the common runtime directory;
- the join allocates a fresh artifact ID and directory for its constructed
  typed value;
- no branch root is silently selected or merged;
- all referenced runtime-relative locations retain their source paths after the
  join.

No composite artifact-root merge is required. A later model materializes any
referenced payloads into its own fresh working directory from the common
runtime directory.

## Test gate

- two sequential model calls;
- model after `it`;
- model inside `so`;
- model inside lift;
- model fanout with same root;
- model fanout with distinct roots;
- distinct-root join retains both branch locations;
- branch directory isolation;
- source artifact remains unchanged;
- continuation sees typed value plus correct metadata.

## Done when

Every supported composition preserves typed payload semantics and filesystem
provenance. Runtime-relative paths provide multi-root transfer without root
merging; physical copying is tested by the materialization slices.
