# F* feasibility: dependent workflows and resource capabilities

**Finding.** Input-indexed output families plus proof-bearing contracts are expressible in ordinary F*. Static context composition is plausible and avoids persisting continuations. F* supports user-defined effects, but a scoped resource effect that survives extracted-OCaml restart is a design proposal, not a feature supplied by F*; host behavior, effect-handler extraction, and no-rerun still need separate contracts and proofs.

## F* facts and limits

- **Known language feature:** F* arrows are dependent; result types may depend on argument values. Refinements and `Tot` let local code state and prove `x:I -> Tot (y:O(x){P(x,y)})`. This supports the mathematical shape of input-relative results and postconditions. See [F* tutorial: Getting off the ground](https://fstar-lang.org/tutorial/book/part1/part1_getting_off_the_ground.html) and [F* introduction](https://fstar-lang.org/tutorial/book/intro.html).
- **Known language feature:** F* has user-defined computational effects, indexed computation types, and effect abstractions for modeling and reasoning about state, I/O, and other behavior. Indexed effects/Dijkstra monads are established F* mechanisms, not a workflow-specific recovery protocol. See [Computational Effects](https://fstar-lang.org/tutorial/book/part4/part4.html), [Computation Types to Track Dependences](https://fstar-lang.org/tutorial/book/part4/part4_background.html), and [Programming and Proving with Indexed Effects](https://fstar-lang.org/papers/indexedeffects/indexedeffects.pdf).
- **Known extraction limit:** ordinary F* extraction to OCaml is supported, but proof-only terms are erased and target types lose precision. Unverified OCaml callers can violate guarantees F* proved about typed callers. Use checked constructors/codecs at host boundaries; do not treat extracted OCaml types as runtime enforcement. See [Executing programs](https://fstar-lang.org/tutorial/book/part1/part1_execution.html) and [Erasure and the Ghost Effect](https://fstar-lang.org/tutorial/book/part4/part4_ghost.html).
- **Current source fact:** repository workflow uses constant-family `workflow i o`; its `pure`, `then_flow`, `fork`, and `lift` do not express value-dependent outputs or contracts. `Tot` evaluator plus external intent reducer is implemented; scoped resource handles, materialization, and collection are not. See [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L459) and [current implementation map](current_implementation_map.md).
- **Not established by F* alone:** stable code identity, durable codec soundness, filesystem confinement, adapter authenticity/idempotency, safe process recovery, or correspondence between an abstract effect and actual extracted host calls. These need explicit trusted contracts or verified host refinement.

## Recommended type surface

Use `prop`-valued contracts so proof evidence is logical/erasable; keep runtime data in `O(x)`. The following is F*-style notation; dependent-pair/refinement encodings need a compile experiment before being called a verified declaration.

```fstar
type Work (I:Type0) (O:I -> Type0)

type Verified (I:Type0) (O:I -> Type0)
             (P:(x:I) -> O x -> prop)
  = Work I (fun x -> { y:O x | P x y })

val verified_local :
  code_id:string -> code_version:nat ->
  run:(x:I -> Tot (y:O x{P x y})) ->
  Verified I O P

type Ctx (I:Type0) (M:I -> Type0)
         (P:(x:I) -> M x -> prop)
  = Σ x:I. { m:M x | P x m }

val then_keep :
  Verified I M P ->
  Work (Ctx I M P)
       (fun c -> { y:N(root c, mid c) |
                    Q(root c, mid c, evidence c, y) }) ->
  Verified I
    (fun x -> Σ m:M x. { y:N(x,m) | P(x,m) /\ Q(x,m,y) })
```

Here `then_keep` law is: run first node at `x`, pack `(x,m)` with `m` refined by `P`, run statically selected second `Work`, return both results. Second stage is a work plan with stable identity, not an arbitrary continuation closure serialized in the run. Persist plan/node IDs, encoded inputs/results, and codec/schema versions; resolve compiled code from a pinned registry. The context refinement carries proof for F* reasoning; extraction must not let host code fabricate it. A production signature should avoid duplicate proof fields if refinements and sigma packages make them redundant.

This keeps proof inside refinement. If later code needs explicit evidence, F* can use the refinement in its proof context; it must not computationally inspect erased evidence. If a certificate is runtime data, model the certificate separately in `O` and prove a checker soundness theorem. F* documents `GTot` erasure and prevents `Tot` code from depending computationally on erased values.

The fixed-carrier alternative is also feasible:

```fstar
type Checked (I B:Type0) (P:I -> B -> prop)
  = Work I (fun x -> { b:B | P x b })
```

It simplifies carrier codecs but requires rechecking `P x b` on restore. An output-family design makes dependent structure explicit; a checked-carrier design separates wire shape from proof. Keep both in comparison until extraction and codec burden are measured.

## Fallible external operation

Keep semantic success separate from protocol status. Validator ordinary F* code stays pure and total:

```fstar
type ExternalResult (x:I) (O:I -> Type0)
                     (P:(x:I) -> O x -> prop) =
  | Verified : y:O x{P x y} -> ExternalResult x O P
  | Rejected : Diagnostic -> ExternalResult x O P
  | Failed   : Error -> ExternalResult x O P
  | Unknown  : RecoveryInfo -> ExternalResult x O P

validate : x:I -> Raw -> Tot (option (y:O x{P x y}))
```

The adapter returns raw bytes/status; kernel decodes raw schema, calls versioned validator, then commits canonical validated output and artifact manifest before exposing `Verified`. On restore, decode canonical result and re-establish `P` with indexed codec/checker; a decoder round-trip law alone does not validate arbitrary bytes. `Rejected`, `Failed`, and `Unknown` remain explicit workflow outcomes, not values inhabiting `O(x)`.

Do not persist `validate` closure. Persist validator ID/version, schema and codec IDs, canonical request/result bytes; resolve implementation from pinned compiled registry. Effect recovery remains adapter-specific: stable key, reconciliation or idempotent same-attempt redelivery; otherwise durable `Unknown`.

## Resource effects for extracted OCaml

Three shapes have different feasibility:

| Shape | F* feasibility | Recovery/extraction boundary | Recommendation |
|---|---|---|---|
| Whole-operation adapter | Direct fit to current durable `external` node. F* checks typed request, validator, and output. | OCaml adapter owns acquire/materialize/run/collect/reconcile. One coarse durable intent; crash outcome requires adapter receipt/idempotency or `Unknown`. | Use first for CLI, network, and DB calls. Put `BlobTree` and domain resource codecs in libraries, not kernel primitives. |
| Scoped capability effect | F* can describe indexed state transitions and user-defined effects. A rank-2/abstract handle API is plausible. | Not established: extracted handle/index erasure, host code can violate abstract protocol; ordinary F* permits duplicable values unless effect/state transition itself carries and checks current state. A continuation paused inside effectful F* code is not durable state. | Research only. Require a closed capability interface, threaded protocol state, host boundary checks, and extraction simulation before relying on scope/lifetime proofs. |
| Hybrid | F* local parser/checker remains ordinary `Tot`; small resource operations go through typed adapter boundary. | Journal each externally visible step or package lifecycle as one adapter operation. Resume from stable node + durable inputs/events; rebuild code, never serialize continuation. | Best path if multiple steps need visible proofs; keep kernel operations minimal and resource-specific operations in F* libraries. |

**Important distinction:** F* effect system can specify computations and their reasoning rules. It does not by itself provide durable continuations, transactional files/network/DB, host capability confinement, or exactly-once effects. A custom scoped capability effect extracted to OCaml is therefore speculative until a small prototype checks actual handler extraction and proves/assumes its OCaml interpreter contract.

For CLI, prefer `BlobTree -> External Analyzer -> RawReport/BlobTree -> Tot parser/checker`. Adapter validates/materializes input under an owned root, launches pinned executable, collects only declared regular files, persists exact bytes before manifest/result commit. Return paths/FDs/PIDs only as ephemeral adapter-local values. For network/DB/JEV, use capability-specific typed request/result and recovery policy; do not wrap every handle in a generic persisted resource value.

## Provenance and scope

- **Primary language sources:** F* links above are official documentation/research. Claims above distinguish documented language mechanisms from proposed workflow encodings.
- **Repository sources:** [`api_composition_alternatives.md`](api_composition_alternatives.md) compares dependent family, explicit context, and fixed carrier designs; [`resource_adapter_architectures.md`](resource_adapter_architectures.md) compares whole adapter, scoped capability, and hybrid protocols; [`durability_proof_semantics.md`](durability_proof_semantics.md) defines no-rerun and recovery theorem targets.
- **Method/limits:** source/report review and official-documentation review only. No F* signature was compiled, no extraction was run, and no adapter/runtime was changed. Treat displayed signatures as candidate notation pending typecheck and OCaml extraction probe.
