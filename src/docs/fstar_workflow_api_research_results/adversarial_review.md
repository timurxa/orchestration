# Adversarial review: resource adapters and proof semantics

**Scope:** Independent source and argument audit of `resource_adapter_architectures.md`, `durability_proof_semantics.md`, and `current_implementation_map.md`. No edits to implementation, build, or tests. Source observations below are direct; design assessments are labeled **Inference** or **Recommendation**. Signatures are semantic candidates, not compile-checked F*.

## Verdict

Retain the operational work-node model and dependent dataflow goals. Do not adopt the proposed hybrid `CapProgram` as a minimal kernel. As written, it is a second workflow language: it gives its own operation vocabulary (`Acquire`, `Materialize`, `Invoke`, `Read/Write/Query`, `Collect`, `Release`, `Checkpoint`) and says the driver interprets it. The escape hatch—compile arbitrary F* between effects into protocol calls—does not define a persistable continuation or explain who interprets the resulting calls. It either restricts callbacks to this DSL or brings closure identity/replay problems back.

For the target static-analysis case, the smallest honest design is one durable external work node for materialize/run/collect, followed by ordinary typed F* parse and verification nodes. Keep resource-specific lifecycle code inside a driver contract. Add scoped resource capabilities only if demonstrated workflows need F* code to interleave multiple resource operations. That is a library or later extension, not kernel minimum.

No representation removes the host trust boundary. A can be proved against an abstract driver contract; B can expose protocol calls to F* proofs but still trusts each foreign call; C increases the modeled protocol and persistence surface without making host actions atomic.

## Architecture critique

### A. Whole-operation adapter: viable minimum

`resource_adapter_architectures.md` correctly identifies A as a natural boundary for a CLI analyzer and existing single-call operations. It matches current `external` most closely: persist one intent and request; let the adapter acquire/materialize/run/collect; commit a raw typed response or explicit failure/unknown; then validate/check in F*.

**Strongest objection:** A hides lifecycle steps from F* and can make a large adapter contract hard to verify. This is real. It does not justify the hybrid DSL by itself: an adapter can expose a precise contract and remain a replaceable boundary. If an operation has useful restart points, make those points explicit protocol states under the adapter contract, with stable evidence and `Unknown` handling. Do not expose every filesystem call as a kernel node preemptively.

**Required correction:** Draft signatures use `IO`, but current F* model and extracted runner do not define an F* `IO` runtime. Treat `start`/`reconcile` as host-driver operations that consume durable intents and return typed events, or define the exact F* effect and extraction/refinement contract. A pseudo-`IO` field is not executable semantics.

### B. Scoped capabilities: plausible, not automatically safe

An abstract `Workspace`, `Session`, or `Txn` capability can help state local protocol preconditions. The rank-2 callback sketch is not enough to prove handle safety. It can prevent a direct handle return when result type is independent of the hidden handle, but it does not by itself provide linear use, prevent aliases, prove release, or stop an effectful callback from stashing state elsewhere. F* effect specifications and a host refinement would need to prove those properties. The capability API must thread state transitions explicitly or use an effect discipline whose semantics establish them.

Possible state-threaded shape (illustrative):

```fstar
with_workspace : Desc ->
  (forall h. Workspace h Open -> HostStep (Workspace h Closed) result) ->
  HostStep result
```

Even this only states a type-level protocol. It does not establish that extracted OCaml closes a descriptor, that process termination preserves files, or that the host cannot duplicate a token. These require runtime/refinement premises. B is useful where F* must reason about a sequence of resource operations; it is not minimal for a one-shot analyzer call.

### C. Hybrid typed effect program: misleading as currently specified

`CapProgram` is a typed AST interpreted by the adapter/runtime. That is a second language, even if its constructors are narrowly typed. “Ordinary F* between effects” conflicts with an AST whose execution protocol is separately interpreted. Persisting stable operation IDs and typed inputs is insufficient when an F* callback may have local state or choose the next action from runtime data. The design must either:

1. interpret the `CapProgram` language instead of executing arbitrary F* callbacks; or
2. execute F* callbacks, persist/checkpoint their continuation somehow, and prove re-execution cannot repeat effects.

The note does not choose or formalize either route. The claim that an adapter may interpret the full typed program or individual typed calls “with semantic meaning unchanged” is overstrong: call granularity changes crash cuts, visible partial effects, retry/reconciliation points, and ordering. Equivalence needs a refinement proof for each interpretation and a trace relation; shared IDs and schemas do not imply equivalence.

**Recommendation:** Remove C from the minimal-kernel recommendation. Retain it as a research alternative only if a concrete use case needs multiple effect steps to be visible as durable work occurrences. Specify whether each step is a work node or an operation-internal event, and prove same observable traces before claiming whole-op/stepwise equivalence.

## Dataflow and dependent verification

The source map accurately observes that current `workflow i o` has fixed endpoint types and no dependent output family; see `WorkflowCore.fst` `workflow`, `then_flow`, and `fork` (current source around lines 459–499). The candidate research in `api_composition_alternatives.md` gives useful dependent encodings, but it should choose one primary representation rather than layering “dependent output,” `Verified`, fixed-carrier `Flow`, `Checked`, and several parallel sequencing names into the kernel.

A compact candidate kernel model is:

```fstar
type Work (i:Type0) (o:i -> Type0)

type Verified (i:Type0) (o:i -> Type0)
              (p:(x:i) -> o x -> Type0) =
  Work i (fun x -> Sigma (fun y:o x -> p x y))

val id : #i:Type0 -> Work i (fun x -> x)
val seq : Work i m -> Work (Sigma (fun x:i -> m x)) n ->
          Work i (fun x -> Sigma (fun y:m x -> n (x,y)))
val fan : Work i a -> Work i b -> Work i (fun x -> a x & b x)
val external : OpSpec c i raw -> Work i (fun _ -> raw)
```

Here `m`, `n`, `a`, and `b` are output families. `seq` receives original input and intermediate result, so dependent proof evidence can be carried inside `m x` as a sigma. A library can name the context and provide ergonomics:

```fstar
type Ctx (i:Type0) (m:i -> Type0) = Sigma (fun x:i -> m x)
val then_keep : Work i m -> Work (Ctx i m) n ->
                Work i (fun x -> Sigma (fun y:m x -> n (x,y)))
val keep_input : Work i m -> Work i (fun x -> i & m x)
```

`then_keep` is only an alias/record-friendly version of `seq`; do not add both to the kernel. For contracts, put evidence in `m x` as `Σ y. P x y`, or choose one `Verified` wrapper as a library alias. Avoid a parallel fixed-carrier contract API unless examples show a concrete inference/schema benefit.

A useful verifier stage has an input-dependent result:

```fstar
val verify : Work (Source & Parsed)
  (fun c -> Sigma (fun finding:Finding -> Sound (fst c) finding))
```

A parser can establish report syntax. It cannot establish that analyzer findings are true of source. A semantic checker must prove `Sound`, verify a certificate, or return an explicitly unverified finding type. Codecs cannot manufacture this evidence.

### `it`, fan, and projectors

`fan` has same-input product semantics, not inherent scheduler parallelism. This distinction in the source map and composition study is correct. Existing `fork` already implements the same typed operation and returns ordered pairs. Renaming it `fan` is API polish, not additional expressive power.

`keep_input p` is the useful convenience: it expresses retaining original context without authors spelling `fan id p`. `id` can be a built-in structural node with a stable manifest tag, or an ordinary polymorphic F* function supplied through `CodeRef`; choose based on identity/codec ergonomics. Do not require an arbitrary code registry entry for identity if a structural node gives same semantics. `fst`, `snd`, and named record selectors should be ordinary typed functions/library combinators. A path-style `it(State)` selector is likely misleading in ordinary F*: F* already has typed functions and record projections, and path syntax risks a second projection language.

Product combinators are library candidates:

```fstar
val first : Work a b -> Work (a & c) (fun z -> b (fst z) & c)
val second : Work a b -> Work (c & a) (fun z -> c & b (snd z))
```

But if `Work` is a dependent family as above, type variables must be expressed with proper dependent function syntax; signatures here are schematic. Prove that untouched fields are preserved and specify how effectful work is scheduled. `fan`/`keep_input` probably cover primary use; retain `first`/`second` only if sample workflows show repeated value.

## Static-analysis case: preferred shape

Use one operation node to contain host-specific resource lifecycle. Use F* work nodes for pure typed parsing and checking:

```fstar
type Source = BlobTree
type Raw = { report:BlobBytes; outputs:BlobTree }
type Parsed = { findings:list Finding; certificate:option BlobBytes }

val analyze : OpSpec Source Raw -> Work Source (fun _ -> Raw)
val parse : Work (Source & Raw)
  (fun c -> Sigma (fun parsed:Parsed -> ReportWellFormed (fst c) (snd c) parsed))
val check : Work (Source & Parsed)
  (fun c -> Sigma (fun findings:VerifiedFindings -> Sound (fst c) (snd c) findings))
val pipeline : Work Source (fun s -> ...)
```

`analyze` is a durable whole-operation node whose adapter ingests/snapshots `BlobTree`, materializes into an isolated workspace, runs a pinned analyzer, captures outputs, and returns bytes/tree plus provenance. If it crashes after process launch but before committed result, recovery yields reconciliation or `Unknown`; no false completion. `parse` and `check` are ordinary total F* callbacks, with evidence in result family. If verified findings are not achievable, output remains parsed/unverified.

The adapter contract must define path normalization, symlink/race handling, required output paths, byte caps, artifact staging/commit order, and crash recovery. Atomicity between workflow journal and artifact store needs a storage contract: separate filesystems/SQLite cannot be assumed one transaction. Stage content-addressed bytes first, then atomically publish references; prove orphan staging is safe and committed refs never point to missing bytes.

A later multi-step resource API should be justified by a case where one external operation is too coarse. If needed, make a typed `Workspace` library driver and expose each durable phase as a work node. Do not put a generic `Acquire/Use/Collect/Release` interpreter in kernel just to demonstrate adapters.

## Durability theorem critique

`durability_proof_semantics.md` is unusually clear about theorem vs assumption, and countermodels correctly reject exactly-once inference and codec-roundtrip-as-validation. These pieces should remain. Tighten following statements before using them as proof targets:

1. **Trace equivalence and concurrency.** `Obs` records ordered external effects, while `T3` compares resumed and uninterrupted runs under unspecified future outcomes/schedules. Independent ready branches can complete in different orders after restart. Either define deterministic scheduling/order, or compare traces modulo commuting independent effects while preserving causal order and per-occurrence outcomes. Otherwise the theorem can be false for harmless branch reorderings.
2. **Backend outcomes.** “Same future backend outcomes” must be keyed by stable `(run, occurrence, attempt, request digest)` and define duplicate/reconciliation behavior. If it means same sequence of replies, changed dispatch count/order makes the premise ambiguous. If adapters deduplicate, state that in the adapter contract, not just as an assumed phrase.
3. **No-rerun scope.** T2 is appropriate for durably completed nodes. State explicitly that incomplete pure local callbacks may be recomputed after restore unless their outputs are committed. The draft does this in a boundary note; retain that distinction and do not claim universal no-rerun from deterministic `Tot` code.
4. **Completion atomicity.** T5 and T3 posit completion plus artifact bytes/references atomically. With filesystem content and a journal, this may require a staged publication protocol rather than one transaction. State the actual commit linearization point and recovery behavior for staged bytes, manifest, and terminal event.
5. **Unknown semantics.** `Unknown` is described as quiescent/absorbing for dispatch, yet may refine to terminal on reconciliation. Specify state as append-only evidence plus current projection; do not model reconciliation as overwriting the historical `Unknown`. Bound repeated polls with explicit deadline/attempt state or state that reconciliation is user-triggered.
6. **Progress assumptions.** Watchdogs do not automatically imply bounded calls unless host can safely interrupt/kill process and record unknown after kill. Store finite-time append, scheduler fairness, watchdog authority, and clock semantics are premises. Avoid implying F* termination can bound an external process.
7. **Budget equation.** Define sum over the latest attempt only for each occurrence. `NotApplied` releases its reservation; a subsequent attempt must not count both attempts. Clarify that a failed/cancelled operation charging the full reservation is a kernel policy, not actual cost evidence.
8. **Event identity and header trust.** Event sequence/replay checks consistency against the supplied header, not authenticity. The current implementation demonstrates valid root-input edits can remain replay-valid; mention this in theorem assumptions or require a digest/MAC/immutable trusted header. Replay-validity is not anti-tamper, anti-rollback, or storage durability.
9. **Adapter equivalence.** Inline and library placement does not imply equivalent semantics. Equivalence requires a relation between handler implementations, same config/operation/version identity, and matching effect/recovery contracts; equal string IDs and codecs alone do not prove it.

## Concrete claim corrections

- `resource_adapter_architectures.md` says rank-2 scope prevents handle escape. Qualify: it can rule out direct typed return of a handle under parametricity and a result type independent of the hidden handle; it does not establish linearity, safe release, or host confinement.
- It says A/B/C interpretations can share semantic meaning. Replace with a proof obligation; effect granularity changes observable partial traces and recovery cuts.
- It says hybrid is the recommended general interface but calls its program “serializable” while requiring ordinary F* between effects. Label this unresolved/possibly second DSL; do not recommend until callback execution and continuation reconstruction are defined.
- `durability_proof_semantics.md` T3 strict ordered-effect equality needs scheduler determinism or trace quotienting as above.
- `current_implementation_map.md` correctly limits source facts and reports no independent build/test in its audit. Keep that provenance distinct from report's executed test claims.

## Candidate choice and strongest counterargument

**Recommendation:** Minimal core = dependent typed work nodes, sequencing with retained context, same-input pairing, generic durable external operation, dynamic routing if already needed, codec/evidence boundary, occurrence/reducer protocol. Add `id`, `keep_input`, projections, `first`/`second`, named context records, Blob helpers, and analyzer adapter as ordinary F* library operations. Keep operation drivers outside serialized workflow values; persist stable identities and logical request/result data only.

**Strongest counterargument:** One whole-operation analyzer adapter puts materialization, process launch, collection, and partial-crash semantics behind a large host contract. F* proves only parser/checker, not that the analyzer saw exact source tree or returned complete outputs. If workflow authors must reason about resource lifecycle or share it across operations, a scoped capability protocol may enable stronger modular guarantees. This argues for researching B as a library boundary with a formal host contract; it does not yet justify C's interpreter in kernel.

## Unresolved proof/interface questions

- What exact dependent `Work I O` encoding typechecks and extracts without unsafe casts? Does extraction preserve endpoint/evidence invariants?
- Is proof evidence carried as `Σ value. P` in every node result, or can a `Verified` wrapper avoid redundant runtime contexts without complicating codecs?
- What decoder soundness theorem is required for arbitrary untrusted wire, indexed by input and schema version?
- How does `keep_input` affect occurrence paths and compatibility when desugared to `fan id p`? Which canonical lowering is versioned?
- Does `fan` only pair values, or also promise scheduler progress/concurrency? If scheduler policy is external, what stable order does `Obs` require?
- How are static analyzer config, binary digest, argv, environment, and input tree bound to a request identity? Which outputs are allowed and how are symlinks/races handled?
- How is artifact publication atomic across blob storage and journal? What does recovery do after staged bytes, after manifest, and before terminal status?
- What adapter evidence establishes `NotApplied`, actual charge, output completeness, or analyzer response authenticity?
- What compatibility proof or content digest binds code IDs, validators, adapters, codecs, and root header across resume?
- If stepwise resources are later required, what minimal example demonstrates benefit over one operation node, and how does each step avoid becoming a second callback language?

## Evidence boundaries

Direct implementation observations come from `current_implementation_map.md` and current `src/fstar/v0/WorkflowCore.fst`, `WorkflowStore.fst`, `WorkflowExamples.fst`, and `Runner.ml`. Resource architecture and theorem notes are proposals, not implementation evidence. Current source supports fixed endpoint workflows, pure evaluator callbacks, event-replay model, selected codec/artifact checks, and fake adapter traces; it does not implement a real process adapter, materializer, dependent result family, or the proposed resource DSL. All signatures above remain candidates pending actual F* typechecking/extraction and proof refinement.
