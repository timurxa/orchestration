# A03 shared identity-codec migration verification

**Scope:** move the previously verified byte framing, identity codecs, and
suffix roundtrip lemmas from `WorkflowV2.GraphCodec` into `WorkflowV2.Kernel`.
Graph syntax encoders, decoders, and their proofs remain in GraphCodec. This
keeps both ManifestCore and GraphCodec as Kernel-only dependents under A01.

**Command:**

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify
```

**Result:** exit 0. F* 2026.03.24 and Z3 4.13.3 verified the seven configured
modules: Kernel, GraphCodec, Identity, Graph, GenerationExample, ChainProof,
and Journal. Output ended with `All verification conditions discharged
successfully`.

The same existing warnings remain: Warning 271 in `FStar.UInt` about a
pattern trigger, and Warning 328 for unused recursive
`GraphCodec.nodes_decode_encoding`. No new `assume`, `admit`, or unchecked
declaration was introduced. This validates the code move and dependent graph
syntax proofs only; it does not establish A03 manifest laws or P0–P16.
