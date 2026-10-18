# A02 F* verification evidence

**Date:** 2026-10-14
**Command:**

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify
```

**Tool versions:** F* 2026.03.24; Z3 4.13.3; OCaml 5.3.0.

**Result:** exit status 0. All configured modules verified:

- `WorkflowV2.Kernel`
- `WorkflowV2.GraphCodec`
- `WorkflowV2.Identity`
- `WorkflowV2.Graph`
- `WorkflowV2.GenerationExample`
- `WorkflowV2.ChainProof`
- `WorkflowV2.Journal`

Output ended with `All verification conditions discharged successfully`.
The check reported two pre-existing warnings: a UInt library pattern uses a
subtraction term, and `GraphCodec.nodes_decode_encoding` is recursive but does
not use itself. `--warn_error @285` did not promote these warnings.

## Scope of this evidence

F* checked the current module bodies and all generated verification conditions
that are obligations in those bodies. It does not turn `assume`/`admit` into
proofs: legacy `Graph.fst` still contains assumed builder declarations and
admitted completeness/builder lemmas. The A02 diff adds no such declaration to
Kernel and makes no P0–P16 theorem claim. The current Makefile still builds
historical modules; later DAG nodes replace or retire their admitted trust
path before the final theorem closure.

This run verifies the dependent codec contract field types and the existing
sample codec proofs. Generic canonical manifest encoding, schema denotation,
artifact identity/carrier coherence, package lookup, journal replay, and the
P0–P16 system theorems remain later nodes.
