# F* typed-plan workflow API: implementation and evidence

**Status: prototype implemented; overall result incomplete against the specification.** The repository now contains a typechecked ordinary-F* workflow model with selected machine-checked lemmas, generated OCaml executable, inspectable file store, deterministic dummy adapters, restart scenarios, and a proof/test ledger. The missing continuation/refinement proof is a blocker, so these artifacts do not satisfy the specification's completion rule.

The implementation is in [`src/fstar/v0/WorkflowCore.fst`](../fstar/v0/WorkflowCore.fst), [`src/fstar/v0/WorkflowStore.fst`](../fstar/v0/WorkflowStore.fst), and [`src/fstar/v0/WorkflowExamples.fst`](../fstar/v0/WorkflowExamples.fst). The extracted host and deterministic runner are in [`Runner.ml`](../fstar/v0/Runner.ml); [`run_tests.sh`](../fstar/v0/run_tests.sh) checks the configured F* release string and exercises extraction, execution, and restart cases. This report replaces the earlier “design brief for later” status in the [outline](fstar_typed_plan_workflow_api_outline.md). The authoritative requirements remain in the [problem specification](fstar_pulse_workflow_api_problem_spec.md).

## Selected API

The implemented choice is **type-indexed combinators with an in-memory closure evaluator, a persisted manifest, and an event-sourced reducer**. Author code remains ordinary F*: the evaluator stores total F* functions, and the runtime handles only workflow structure and explicit external operations. This is not a defunctionalized first-order typed plan AST. The manifest describes plan identity/structure, while executable behavior resides in closures rebuilt by the compiled program.

```text
workflow<I,O> = {
  manifest : PlanManifest,
  evaluate : Context -> Path -> I -> Tot (Evaluation<O>)
}

CodeRef<C,I,O> = {
  id, version, capture : C,
  capture_codec : Codec<C>, input_codec : Codec<I>, output_codec : Codec<O>,
  apply : C -> I -> Tot O
}

pure       : CodeRef<C,I,O> -> Workflow<I,O>
then_flow  : Workflow<I,M> -> Workflow<M,O> -> Workflow<I,O>
fork       : Workflow<I,A> -> Workflow<I,B> -> Workflow<I,(A,B)>
lift       : Shape<S> -> Workflow<A,B> -> Workflow<Carrier<S,A>,Carrier<S,B>>
external   : OpSpec<C,I,O> -> Workflow<I,O>
so         : RouteCode<C,I,O> -> Workflow<I,O>
```

`CodeRef.apply`, `RouteCode.choose`, and `RouteCode.resolve` are normal `Tot` callbacks. They are not represented by another callback language or a general-F* interpreter. `external` is the persistence/effect boundary. A route sees its typed input and an immutable budget snapshot, then returns a value or a stable child reference. The reducer commits the route choice and child manifest before a later evaluation can enter the child. Resume uses that saved choice and snapshot; it does not rerun `choose` against a changed budget.

The API includes both `Lift` and `Fork`. This corrects an overstatement in the original outline: `Lift (Product Id Id) p` applies the **same** workflow to both values. It cannot express two different branch workflows. `Fork` is the typed same-input pairing primitive; `Lift` traverses `List`, `Option`, products, and nested shapes. Its path and tuple order are stable under opposite completion order.

`workflow` values are executable closure-backed values inside the compiled program and are not serialized. The persisted manifest carries code IDs, versions, codec tags, and encoded captures. Dynamic child code is rebuilt by a compiled resolver and checked against its saved manifest. This is safe only when the caller's build ID and compiled code registry are stable and truthful; the current model does not hash callback bodies or prove the supplied build ID identifies those bodies. The caller also supplies the persisted run header as the replay trust anchor: journal replay checks projections against that header, but does not authenticate it or bind its root input, initial budget, build ID, or manifest to an external digest. Header mutation can therefore change the replay basis while still producing a self-consistent replay; tamper resistance is not claimed.

## State, adapters, and persistence

`WorkflowStore` serializes a versioned `wire` tree containing the immutable run header and complete event journal. Reducer projections (budget, operation attempts, route expansions, artifacts) are rebuilt by replay and validated before evaluation. The runner writes one JSON snapshot per event. The JSON contains explicitly tagged wire values and a readable event summary; the reader checks the summary against the decoded F* journal.

The host commits to a same-directory temporary file, flushes and `fsync`s it, atomically renames it, then attempts to `fsync` the containing directory. An advisory lock serializes each snapshot write; it does not cover the full read/evaluate/dispatch transaction. Correct use therefore assumes one active runner per run. Directory `fsync` errors `EINVAL` and `EBADF` are ignored, so power-loss durability depends on filesystem behavior. A `Prepared` record is durable before adapter dispatch; result status is durable before the next evaluation consumes it; an expansion is durable before its child is evaluated. The process restart tests use separate executable invocations. This is an inspectable file store rather than SQLite.

The logical scheduler queue is reconstructed by evaluating the root plan against the replayed state; it is not serialized as a separate queue. Occurrence paths and event history reconstruct branch slots. This relies on the exact same total code and plan manifest being supplied after restart. `Pending` and `Unknown` produce reconciliation requests. The ready-action selector skips those requests so another branch can progress. The runner polls them only after dispatchable work is handled, and returns a waiting state if a poll makes no progress.

The extracted runner has a deterministic FIFO event queue for scripted adapter replies. Immediate dispatch replies and deferred reconciliation results enter the queue and are applied one at a time, with a snapshot after each accepted reducer event. The deferred script returns the right branch before the left, then redelivers a terminal result and sends a conflicting late result; the reducer accepts the duplicate and rejects the conflict. Failure and unknown outcomes also run through the queue. The queue and the remaining scripted replies are process-local, however, and are not included in snapshots. After a crash, pending work must be reconciled by the adapter; the prototype does not prove recovery of queued-but-uncommitted events.

The adapter protocol distinguishes a durable prepared intent, dispatch, pending result, reconciliation, terminal success/failure/cancellation, and unknown outcome. A confirmed `NotApplied` has its own reducer event and permits a new attempt after releasing the reservation. Local IDs do not establish exactly-once remote execution. Refund safety depends on a trusted adapter receipt; F* checks the declared capability and nonempty evidence ID, but cannot authenticate that receipt.

## Alternative formulations reviewed

| Formulation | Same cases considered | Finding |
|---|---|---|
| Implemented: type-indexed combinators + closure evaluator + manifest + reducer | typed sequential composition, ordered pair, shape traversal, dynamic child, suspension, restart | Selected prototype. Endpoints remain typed; effects and saved route choices are visible; callbacks remain ordinary F*. Closures are rebuilt from pinned code, never persisted. Proof cost remains high at extraction, registry, and storage boundaries. |
| Defunctionalized typed plan AST + callback registry | same cases, with explicit serialized node tags and stable callback references | Unimplemented alternative. It could make plan position and structural state explicit, but callbacks still need ordinary F* execution, stable code/capture IDs, and a proof that registry resolution matches persisted identities. No AST evaluator or comparison prototype exists here. |
| Arbitrary higher-order workflow closures without manifest/replay protocol | composition, dynamic route, restart | Rejected as a durable representation. Native closures and captured heaps are not stable persisted state. The implemented evaluator uses closures only in memory and pairs them with manifests and replay; it does not solve code identity automatically. |
| Free effects/handler with continuation | typed operations, pending operation, dynamic route, resume | Not selected. A suspended handler continuation is itself a closure; it must be replayed or defunctionalized into stable code references. That adds a continuation registry and its proof obligations without removing the ordinary-F* callback identity problem. |
| Applicative/arrow typed DAG | static fork, ordering, scheduling | Useful for fixed independent graphs, but dynamic `So` expansion needs an additional node and persistence protocol. It does not replace the selected route boundary. |
| Untyped serialized operation AST / interpreter for callbacks | route and restart | Rejected for author code because it would restrict or reinterpret ordinary F*. Interpreting the small workflow protocol is allowed; interpreting a second callback language is not. |

The choice is a design result, not a proof of superiority. `Fork` is primitive because `Lift` alone does not provide distinct branches. A library can derive projections, fan helpers, and recovery policies while preserving these kernel types.

## Artifact decision

| Representation | Decision and durable meaning |
|---|---|
| Ordinary typed value | Keep transient inside pure callbacks. Persist only at a suspension boundary through a codec with a round-trip law. |
| `BlobBytes` | Useful for large opaque payloads; persist bytes and codec identity. Artifact validation rejects byte values above 255. The general `blob_bytes_codec.decode` does not enforce this bound. |
| `BlobTree` | Useful for generated source bundles and multi-file outputs. Persist each file's bytes and Unicode-scalar path segments. Artifact validation rejects empty segments, invalid scalars, byte overflow, and file/directory prefix collisions. The general `blob_tree_codec.decode` does not validate these invariants. A future materializer should hex-encode each scalar under a controlled root. No materializer is implemented here. |
| External operation input/result | Persist in the operation intent/result using its input/output codec tags. It is effect protocol data, not a universal artifact. |
| Materialized file or live capability | Do not persist a process-local path, file descriptor, socket, or handle. The prototype rejects these artifact kinds; a library adapter must persist bytes or a reacquisition recipe and report unavailable when reacquisition fails. |
| Durable reference | Persist URI and digest, and require both nonempty. A store-specific adapter must check existence, digest, and schema after restart; that resolver is not implemented here. |
| Provenance and validation | Persist producer occurrence, parent artifact IDs, and validator name/version. The reducer checks that named parents already exist. It does not prove semantic validity of a validator's claim or content lineage. |

The current prototype keeps concrete Blob/reference checks in the core so reducer artifact validation is executable. These checks do not establish general codec validity: operation/root decoders can accept values that artifact validation would reject. Pair codec tags include both component versions using Cantor pairing, and escape composite delimiters in component IDs; executable cases check changed versions and delimiter-heavy IDs. This changes the old composite tag (which always used version 1); no migration is implemented for snapshots written with that tag. No F* injectivity theorem for the composite version formula is present. A production split should keep the generic codec-tagged artifact record at the persistence boundary and place BlobTree/materialization and durable-reference resolution in an ordinary F* library. Arbitrary `TypedValue` and `OperationInput` tags still require a build-pinned codec registry; the current core cannot validate every user codec on its own.

## Verification and executable evidence

Run from the repository root:

```sh
src/fstar/v0/run_tests.sh
```

The recorded toolchain is F* 2026.09.27 (`7deb38a27c86990664c6b41e4b6093597acdebd4`) and OCaml 5.3.0 with `fstar.lib`, Yojson, and Unix. The script checks only the F* release string; it does not verify the commit, OCaml version, or package versions, and its paths can be overridden. The latest run passed all modules and all executable cases. Its generated build is in `/tmp/fstar-typed-plan-workflow-build`.

Executed cases cover typed composition, `Fork` order, nested `Lift`, empty lists and absent options, direct/identity/child routes, saved expansion restore, zero-operation and two-operation children, three nested fuel-bounded expansions, exact resource boundaries, pending progress, reordered completion, duplicate and late status events, stale sibling actions, failure/cancellation/unknown, `NotApplied` retry, artifact validation/provenance, and a recorded `clock.sample` effect. Separate runner processes stage and restore a committed intent, pending operation, child expansion, and direct expansion with an absent child manifest. The same compiled `fork_demo_plan` runs through an immediate adapter and a deferred/reordered adapter. The queue tests accept a duplicate result and reject a conflicting late result. Runner fault scripts exercise failure and unknown. Two identical deferred runs produce byte-identical logs and JSON snapshots.

The extracted runner is execution evidence, not a proof of its own correctness. It simulates asynchronous outcomes by dispatching one operation at a time and letting the deferred adapter return `Pending`; it does not create OS threads or contact a service. Failure, cancellation, and unknown reducer paths are also exercised by F* model cases; runner fault scripts exercise failure and unknown. The deterministic clock case is an explicit recorded operation, not a host clock read.

## Proof and trust ledger

| Guarantee | Evidence | Status / limit |
|---|---|---|
| Typed composition, endpoint preservation | F* signatures for `then_flow`, `fork`, `lift`, `external`, and `so`; extracted typechecks | F* source-level type safety verified. The OCaml extractor erases indices and emits `Obj.magic` for some polymorphic carriers. No compiler-correctness or extracted-value refinement proof is supplied. |
| Inert construction and ordinary-F* route code | Workflow constructors build records; route/code callbacks have `Tot` types; examples use normal F* functions and recursion | Type-level and source evidence only. No theorem connects extraction to “no effect during construction.” External effects must stay behind the adapter contract. |
| Codec round trips | `codec` requires a round-trip lemma; concrete nat/text/bool/pair/BlobTree codecs verify | Proved for these codec values. `WorkflowStore` event/record/state encode/decode has no general round-trip theorem. JSON parser/rendering is host code and tested only. |
| Budget safety | `reserve_preserves_budget`, settlement lemmas, `apply_event_preserves_budget`, `replay_preserves_budget` | Machine-checked for the F* reducer model; does not model remote spend before a reply arrives. Unknown retains reservation. |
| Replay and recovery | `replay_append_law`; `apply_event_preserves_replay_valid`; state validity requires exact equality with replay; crash-after-intent example turns `Prepared` into `Unknown`; a valid root-input edit remains replay-consistent and changes the resumed result | Replay composition and preservation of replay consistency under accepted `apply_event` calls are proved. Replay consistency is not header integrity. No all-cut continuation theorem follows from append composition. |
| Fork order and traversal edges | Fork slot commutation/order lemmas, empty-list and absent-option lemmas, extracted nested-shape tests | Local algebra and examples are proved/tested. Slot lemmas are not connected to a formal concurrent scheduler refinement. |
| Pending progress | `pending_does_not_block_ready`; runner tests a pending left branch while preparing/dispatching right | Availability safety is proved for the selector. Eventual progress requires weak fairness, terminating callbacks, and an available adapter; no liveness theorem is proved. |
| `So` bounds and recovery | `Tot` route callback, fuel-decreasing recursive example, expansion-count lemma, persisted route choice/snapshot and restart execution | Example bound is proved and tested. No generic route callback/refinement or route-resolution identity theorem is present. |
| Reducer transitions, duplicate/late/stale events | Transition guards in `apply_event_body`; extracted scenarios | Tests cover examples. A general transition safety theorem (attempt uniqueness, terminal monotonicity, result-before-consumption, artifact invariants) is missing. |
| Artifact invariants | Executable validators for BlobBytes, BlobTree, durable references, producer run, existing provenance parents; BlobTree codec round trip | Structural checks exist. No semantic provenance proof, generic codec-registry proof, digest verification, path materializer, or reacquisition proof. |
| Durable file and JSON bridge | Host atomic-snapshot implementation; separate-process restart tests including `WOption None`; host checks reject missing/duplicate fields, negative/noncanonical naturals, and out-of-range bytes | Assumes one active runner per run, `fsync`, same-filesystem atomic rename, and filesystem durability. Snapshot locks cover individual writes only. Journal replay consistency is relative to the supplied header, which is not authenticated or digest-bound. No verified JSON parser/renderer, crash-injected partial-write proof, or power-loss test. |
| Callback/build identity | Build ID, manifest, codec tags, resolver ID/version checked on resume | **Assumption/blocker:** IDs and build ID are caller-supplied metadata; there is no digest-bound code registry or proof that unchanged IDs mean unchanged callback bodies. A changed callback reusing its IDs may run. |
| `NotApplied` refund | Dedicated reducer event validates attempt/capability/evidence-ID fields | **Assumption:** adapter receipt authenticity and adapter identity are trusted. A nonempty string alone is not evidence. |
| End-to-end continuation and implementation refinement | Restart traces show selected examples | **Blocker:** no formal observation semantics, extracted-runner simulation, or theorem for every termination cut preserving values, ordered effects, artifacts, budgets, failures, and progress. Current process tests exercise selected committed boundaries only. |

Further trust assumptions are that codecs are total and stable, local `Tot` code terminates, the exact compiled workflow/resolver set is restored, the store returns complete committed snapshots, only one runner owns a run, reducer events are serialized through that runner, and adapter statuses obey the declared protocol. A local event ID cannot resolve the lost-reply window at a remote service.

## Remaining blockers and completion judgment

The main blocker is the required continuation theorem for the **actual extracted implementation**. Closing it needs: (1) a formal workflow observation semantics and semantic state invariant; (2) a proof that reducer transitions preserve those semantic invariants and that replay reconstructs the same observations; (3) a proved or explicitly accepted JSON/store refinement contract; (4) a simulation relation for extracted OCaml and the scheduler; and (5) adapter assumptions that cover dispatch/reconciliation without assuming the conclusion. Callback identity also needs a build-bound registry or verified digest mechanism. Serializer round-trip and artifact-lineage/materialization proofs are additional gaps.

Accordingly, this work fully replaces the outline with a concrete API, executable artifact, alternatives, artifact decision, evidence, assumptions, and explicit blockers. It does **not** meet the specification's “complete only when” criteria yet. The implementation is useful as a tested F* prototype, but the result must remain marked incomplete until those proofs and the remaining durable-boundary obligations are discharged.
