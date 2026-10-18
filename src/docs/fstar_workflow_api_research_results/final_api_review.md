# Final API signature review

**Scope.** Read-only audit of `design_comparison_and_decision.md` §§4–7. No compile, extraction, build, or test run. F* feature claims checked against official tutorial pages linked below. Candidate API signatures remain uncompiled semantic notation, as the integrated report states.

## Findings

### 1. External operation lacks durable codec for accepted output — fix before implementation

`CodeRef` declares an input-indexed output codec, but `Operation` has only request and raw-response codecs. Its validator produces `(y, proof)` and `OpOutcome.Accepted` carries that pair, while the durable contract later requires validated output bytes and restore-time reconstruction. There is no operation field defining how accepted `o x` is encoded, decoded, or checked after restart. The `prop` proof is not a substitute for runtime bytes; F*'s ghost/proposition evidence may erase in OCaml.

Add an indexed accepted-result codec/checker to `Operation`, for example:

```fstar
encode_result : x:i -> y:o x{p x y} -> Tot wire
decode_result : x:i -> wire -> Tot (option (y:o x{p x y}))
```

Require round-trip for encoded results and decoder soundness for arbitrary accepted wire. If codec only decodes `o x`, store raw response and rerun a pinned validator/checker before constructing `Accepted`. Specify which representation enters the completion record. F* documents refinements and `GTot` erasure; it does not make erased proof values durable. See [refinements/dependent functions](https://fstar-lang.org/tutorial/book/part1/part1_getting_off_the_ground.html), [ghost erasure](https://fstar-lang.org/tutorial/book/part4/part4_ghost.html), and integrated source `design_comparison_and_decision.md` §§5–6.

### 2. `Sigma` and proof-package notation need an explicit F* encoding

The integrated report explicitly calls signatures semantic notation, so `Sigma` is not a demonstrated compile error. Before treating the surface as a real F* API, define/import `Sigma` or spell dependent pairs using F*'s supported dependent-pair syntax, and typecheck all universes and implicit binders. Official F* materials use value-dependent arrows and dependent pairs such as `(t:Type & f t)`; notation alone does not establish that this exact `then_keep` elaborates. See [F* dependent functions](https://fstar-lang.org/tutorial/book/part1/part1_getting_off_the_ground.html) and [F* sigma-pair example](https://fstar-lang.org/papers/ussl.pdf).

`then_keep`'s semantic shape is otherwise coherent: `g` receives `(x,m)` with `m : M x`, and output retains `m` plus `g`'s result. If `m` is a refinement/sigma, its proposition is available to F* proofs. Keep proof evidence erased/logical; put any runtime certificate needed by `g` in the data result explicitly.

## Claims not overstated

- `Work i (fun x -> O x)`, value-indexed refinements, and pure `Tot` local functions fit documented F* dependent arrows/refinement types. Exact ergonomics, equality transports, indexed codecs, and extracted API remain untested.
- F* user-defined/indexed effects can specify effectful computations and proof rules. They do not supply durable continuation serialization, host resource confinement, filesystem/DB/network atomicity, or an extracted OCaml refinement for the proposed adapter. The integrated decision correctly labels these boundaries as separate assumptions/refinements. See [Computational Effects](https://fstar-lang.org/tutorial/book/part4/part4.html), [indexed effects](https://fstar-lang.org/papers/indexedeffects/indexedeffects.pdf), and [OCaml extraction limits](https://fstar-lang.org/tutorial/book/part1/part1_execution.html).
- Extraction erases proof-only material and loses F* type precision at OCaml boundary. Integrated proposal correctly requires host-side codecs/validation and does not claim the OCaml type enforces `P`.
- `Verified` is an alias/helper over any family `o`; it is not limited to fixed-carrier results. The prose in §4 says it “spells the fixed-carrier case,” which is narrower than the displayed type. Replace with “adds a postcondition to any output family; for fixed carrier, it is the fixed-carrier/postcondition form.”

## Provenance

Repository review: `design_comparison_and_decision.md` §§4–7; `fstar_feasibility.md`; `api_composition_alternatives.md`; `resource_adapter_architectures.md`; `WorkflowCore.fst:459–560,945–1031`. External language claims rely only on official F* documentation/research links above. No signatures were compiled or extracted in this review.
