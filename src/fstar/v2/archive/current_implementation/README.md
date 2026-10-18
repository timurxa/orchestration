# Archived F* implementation

This is the source tree that existed before the active top-down redesign. It
is retained so its data types, schema machinery, proof attempts, and admitted
boundaries can be inspected while formalizing the new specification. It is not
the implementation of the active theorem contracts.

The original verification target is preserved with the source. From the
repository root, run:

```sh
make -C src/fstar/v2/archive/current_implementation verify
```

The active design is in [`theory/system_spec.md`](../../theory/system_spec.md);
the previous theorem task table is retained in
[`state/work_dag.md`](../../state/work_dag.md).
