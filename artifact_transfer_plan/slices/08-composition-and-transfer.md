# Slice 8 — composition and multi-root transfer

## Purpose

Prove artifact transfer across current flow composition, including branch boundaries.

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

- same-root branch outputs preserve root;
- distinct roots merge into fresh join root;
- merge copies referenced payload trees without changing relative `Location` values;
- incompatible relative-path collisions fail explicitly;
- no branch root is silently discarded.

If composite root merge proves too invasive for first implementation, gate multi-root joins behind explicit failure and record follow-up. Sequential transfer must still complete.

## Test gate

- two sequential model calls;
- model after `it`;
- model inside `so`;
- model inside lift;
- model fanout with same root;
- model fanout with distinct roots;
- join collision failure;
- branch directory isolation;
- source artifact remains unchanged;
- continuation sees typed value plus correct metadata.

## Done when

Every supported composition preserves both typed payload semantics and filesystem provenance.

