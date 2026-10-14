# Current F* workflow implementation map

**Evidence class:** source observations and analysis of existing documentation. No source was modified and no command or test was run in this audit. This map describes the current prototype, not the proposed design.

## Summary

The prototype is an ordinary-F* typed combinator evaluator backed by a persisted structural manifest and an event-sourced reducer. It stores no executable closures: the compiled workflow reconstructs them on each resume. Its type parameters are fixed endpoint types (`workflow i o`), so current workflows do not express dependent output families or postconditions. `external` creates a durable operation intent; an OCaml dummy runner interprets that intent. The F* source proves selected reducer, budget, codec, and local algebra lemmas. The report records successful extracted examples, but it also explicitly says that no end-to-end extracted-runtime refinement or all-crash-cut continuation theorem exists.

## Author-facing layer

| Construct | Source | Observed behavior | Limit relevant to redesign |
|---|---|---|---|
| `wire`, `codec` | [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L6), lines 15–21 | A closed wire algebra and a codec record with IDs, versions, total encode/decode, and a `decode(encode x) = Some x` lemma. | Round-trip only constrains encoded values; arbitrary wire input can decode to a value without a general soundness predicate. Store-level state codec has no general round-trip lemma. |
| `BlobTree` | [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L77), lines 77–225 | A domain representation of relative paths as Unicode scalar segments plus byte lists. Its codec has a round-trip lemma; validators check path, byte, and prefix-collision constraints. | A workflow can carry it as a value, but no materializer, process adapter, or filesystem refinement exists. This is a type-specific value, not a kernel resource abstraction. |
| `workflow`, `code_ref`, `pure` | [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L459), lines 459–481 | A workflow holds a manifest and an in-memory `evaluate` closure. `CodeRef.apply` is ordinary `Tot` F* code; manifest records an ID/version and encoded capture. | Manifest identity is metadata, not a digest or proof that a callback body is unchanged. Extracted execution has no proved refinement relation to the source model. |
| `then_flow`, `fork`, `lift` | [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L483), lines 483–560 | Sequential composition feeds the first output into the second. `fork` evaluates both branches against the same input and pairs outputs in declared left/right order. `lift` traverses list/option/product shapes with occurrence paths. | `fork` is same-input pairing; scheduler-level concurrency is not implied by its type. No `it`/`keep_input` helper exists. Types are not input-indexed. |
| `so` routing | [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L1033), lines 1033–1110 | A total route callback chooses a direct output or stable child reference. Choice, budget snapshot, and child manifest are saved before child execution; resume checks the saved identity and choice. | Route callbacks/resolvers are rebuilt ordinary closures. Stable IDs are not code hashes; there is no generic proof that resolution matches old code or preserves a route postcondition. |

## Durable reducer and operation model

`durable_state` is reconstructed from a header and journal. Reducer events include route expansion, prepared operation, status changes, definite-not-applied evidence, and artifacts. `apply_event` only accepts the next sequence (or an identical already-seen event); the body validates operation transitions, reserves/settles budgets, validates selected artifact structure, and checks provenance parents exist ([`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L681), lines 681–780).

The operation statuses include `Prepared`, `Pending`, `Unknown`, `Succeeded`, `Failed`, `Cancelled`, and `NotApplied`. On recovery, every `Prepared` intent becomes `Unknown` and retains its reservation. Pending or Unknown operations yield reconciliation actions. A new attempt is emitted only after a `NotApplied` state. Success is consumed by decoding the stored output wire with the currently rebuilt output codec ([`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L799), lines 799–831 and [`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L969), lines 969–1031).

`open_run` stores encoded root input, build ID, root manifest, codec tag, and initial budget. `resume_evaluate` checks journal replay validity and compares supplied build ID, manifest, and codec tag, then decodes the root input and evaluates the rebuilt closure ([`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L842), lines 842–864). Replay-validity is consistency relative to the header being replayed; there is no authentication or digest binding for the header. The examples explicitly demonstrate that a valid root-input edit can remain replay-valid and change the resumed result (`WorkflowExamples.fst:561–573`).

`valid_artifact` accepts validated BlobBytes and BlobTree structure, a minimally nonempty URI/digest reference, and unconstrained typed/operation wire payloads with a nonempty codec ID. It explicitly rejects `MaterializedFile` and `LiveCapability` kinds ([`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L654), lines 654–668). `materialization_available` must be false. Thus the store records logical bytes/trees/references but never proves a live path or handle exists.

The external declaration is `op_spec c i o` with operation/version/capability, codecs for capture/input/output, a capture value, and maximum charge ([`WorkflowCore.fst`](../../fstar/v0/WorkflowCore.fst#L945), lines 945–1031). It has no adapter implementation field and no semantic output validator. The operation result is only as meaningful as its output codec; decode does not prove a property such as “prime” or “report corresponds to source.”

## Store and host runner

`WorkflowStore.encode_state` writes schema version 1, header, and complete journal only when replay validation succeeds. `decode_state` decodes header/events and rebuilds reducer projections through replay ([`WorkflowStore.fst`](../../fstar/v0/WorkflowStore.fst#L327), lines 327–339). This is a well-defined encoding strategy, but no general `decode_state(encode_state s) = Some s` theorem is provided.

The host runner [`Runner.ml`](../../fstar/v0/Runner.ml#L87) translates wire values to tagged JSON; its decoder rejects duplicate/missing object fields, noncanonical or negative natural numbers, and bytes above 255. Snapshot write uses a same-directory temporary file, flush/fsync, rename, attempted directory fsync, and a per-write advisory lock ([`Runner.ml`](../../fstar/v0/Runner.ml#L94), lines 94–140). This is host evidence, not an F* theorem. The report notes that only individual snapshot writes are serialized, so correct operation assumes one active runner per run; directory-fsync errors `EINVAL`/`EBADF` are ignored.

The adapter cases are OCaml functions returning hard-coded outcomes for named operations (`Immediate`, `Deferred_reverse`, `Scripted_faults`) ([`Runner.ml`](../../fstar/v0/Runner.ml#L143), lines 143–171). The FIFO event queue and remaining scripted responses are process-local. The run loop applies events through F*'s reducer and snapshots accepted events ([`Runner.ml`](../../fstar/v0/Runner.ml#L193), lines 193–290). It does not launch a process, access a network service, or persist the queue. Restart tests therefore establish selected host control-flow behavior under the scripted adapter, not real remote exactly-once behavior.

## Existing proof and execution evidence

The implementation report is the source for previously executed test evidence; this audit intentionally did not rerun it. Its proof ledger records:

- **Proved in F\*:** concrete codec round-trips (including pair/BlobTree), selected fork-slot and list/option laws, replay append law, accepted-event replay-validity preservation, budget invariants/preservation, and a scheduler selector lemma allowing a pending operation not to block a ready action ([report](../fstar_typed_plan_workflow_api_report.md#L94), lines 94–107).
- **Tested in extracted execution:** typed sequential/fork/lift examples, routing and selected expansion restores, selected process restarts, dummy adapter reorder/duplicate/conflict, failures/unknown, retry after `NotApplied`, artifact structural checks, and deterministic logs/snapshots. The detailed list and limitations are recorded in the report, lines 78–88.
- **Not established:** every-cut continuation equivalence; “committed completion never reruns” theorem for extracted runtime; adapter authenticity/idempotency; semantic validation of operation output; host JSON/store refinement; power-loss guarantees; filesystem materialization/collection; code identity beyond caller-provided IDs; or liveness without fairness/availability assumptions (report lines 94–115).

F* supports dependent function types, refinements, total functions, and user-defined effect specifications; ordinary F* extraction to OCaml is documented by the primary [F* tutorial introduction](https://fstar-lang.org/tutorial/book/intro.html), [refinement/total-function tutorial](https://fstar-lang.org/tutorial/book/part1/part1_getting_off_the_ground.html), and [effects tutorial](https://fstar-lang.org/tutorial/book/part4/part4_pure.html). These language capabilities make input-indexed result families and effect specifications plausible, but they do not supply this workflow system's persistence or extracted-runtime simulation theorem.

## Design implications (derived)

1. Keep the authoring language as statically composed work nodes with ordinary typed F* callbacks; do not serialize arbitrary continuations. A structural plan AST could improve runtime identity checking, but current manifests are not executable ASTs.
2. Separate same-input pairing/retention (`fan`, `keep_input`, `it`) from scheduler concurrency. The current `fork` already supplies the pairing behavior under an awkward name.
3. Add dependent result evidence at typed node boundaries, then require persisted results to decode into a witness/proof pair via a checker or explicit assumption. Do not treat a codec round-trip lemma as a semantic validator.
4. Make the adapter boundary explicit and resumable: intents and logical resource recipes are durable; handles are scoped/live; validated collected bytes or references commit before downstream use. Current `op_spec` and artifact records are too small to implement this.
5. Prove no-rerun at the durable success linearization point. The current reducer stores successful operation output and replay reconstructs it, but the required theorem linking this fact to the evaluator/host dispatch loop is absent.
6. Model a capability adapter's safety and progress contract as part of the trusted/refined boundary; otherwise adding filesystem/network access only moves the unmodeled effects into OCaml.

## Strongest objection and follow-up

This map relies on the implementation report for historical test results, not an independently reproduced test run. Source inspection confirms the relevant declarations and host paths, but not the report's exact build or test environment. The next design comparison should treat the report as execution evidence with that provenance and keep theorem claims separate. A later authorized verification phase can reproduce tests and develop a machine-checked model-to-runtime relation.
