# F* workflow API redesign: integrated design decision

**Status:** Research decision for the next implementation specification. This file resolves the API and adapter direction from the current draft and the independent reports in this directory. It is not an implementation report. Candidate signatures are F*-shaped semantic notation; none were compiled in this research pass. No source code, build, or tests were changed or run.

## 1. Decision in one page

Design a **dependent work-node API**. A workflow node has a statically declared input type and an output family indexed by the input value. Put a refinement or proof-bearing package in that output family. Compose nodes with static context pairs, so the next node can see both the original input and the previous result without a runtime-selected continuation.

Use a small dataflow vocabulary:

- `it` (also named `id`) returns the current input.
- `fan f g` runs two statically declared nodes on the same input and returns an ordered pair. It says nothing about parallel scheduling.
- `then_keep f g` runs `g` on a typed pair of original input and `f`'s result, then retains the intermediate result with the final result. This is the ergonomic name for a context-passing composition combinator.
- `keep_input f` is the short form for retaining input, equivalent in values to `fan it f`.
- `fst`, `snd`, record selectors, `first`, and `second` are ordinary typed F* functions/library combinators; there is no string-path projector language.

The minimal durable effect boundary is **one whole external operation node**. Its adapter owns the resource lifecycle: acquire, materialize, invoke, collect, release, and reconcile. F* declares and validates typed request and response schemas, parses reports, and proves semantic properties when it has a checker or certificate verifier. Do not put a generic `Acquire/Use/Collect/Release` interpreter in the kernel. A scoped capability library may be added for a demonstrated multi-step algorithm that must interleave resource calls.

The kernel does not treat `BlobBytes` or `BlobTree` as primitive workflow values. A file adapter library may define `SourceTree` and `OutputTree` and interpret them as files. The durable value layer knows codecs, byte objects, schema IDs, and references; it does not decide that every artifact is a file tree.

Define a node as durably complete only after its validated output and durable artifact references are committed. The resume interpreter must check a completion record before invoking that node's body or dispatching its external effect. This makes “completed work is not rerun” provable for local and external nodes. If a process crashes before a local node's completion commit, a pure deterministic body may run again; that node had not durably completed. Long-running local algorithms need explicit checkpointed subnodes to retain intermediate progress.

For crash recovery, require prefix safety at every concrete cut as the unconditional base claim. Claim uninterrupted/restarted observation equivalence only with a backend-state relation or bisimulation, storage refinement, code pinning, and a scheduler trace relation. Without backend idempotency or truthful reconciliation, preserve `Unknown`; exactly-once remote effects cannot be derived from a local operation ID.

## 2. Basis and evidence labels

This decision synthesizes:

- [`current_implementation_map.md`](current_implementation_map.md): direct source audit of `WorkflowCore.fst`, `WorkflowStore.fst`, `WorkflowExamples.fst`, and `Runner.ml`; historical execution results are kept separate from the audit.
- [`api_composition_alternatives.md`](api_composition_alternatives.md): three dataflow/dependent-result alternatives and prime/static-analysis encodings.
- [`durability_proof_semantics.md`](durability_proof_semantics.md) and its critique [`proof_model_critique.md`](proof_model_critique.md): quantified theorem targets, impossible guarantees, and cut-state objections.
- [`resource_adapter_architectures.md`](resource_adapter_architectures.md), [`adversarial_review.md`](adversarial_review.md), and [`whole_operation_adapter_contract.md`](whole_operation_adapter_contract.md): adapter choices, resource lifecycles, and the critique of a mandatory lifecycle DSL.
- [`fstar_feasibility.md`](fstar_feasibility.md): official F* source review distinguishing supported language mechanisms from workflow/runtime conjectures.
- [`api_surface_candidate.md`](api_surface_candidate.md) and [`refined_proof_targets.md`](refined_proof_targets.md): Round 2 dependent API and cut-level theorem candidates.
- [`final_proof_review.md`](final_proof_review.md), [`final_api_review.md`](final_api_review.md), and their resolution reports: independent audits of trace quantification, host cuts, artifacts, budgeting, result codecs, dependent syntax, and analyzer provenance.
- [`final_resource_review_resolution.md`](final_resource_review_resolution.md) and [`final_api_provenance_recheck.md`](final_api_provenance_recheck.md): final checks of live-resource lifecycle, visibility gates, and the provenance correction.

Labels in this report:

- **Observed:** verified from current source or existing report, with provenance.
- **Derived:** follows from a type, transition rule, or counterexample.
- **Decision:** selected for the next specification.
- **Assumption:** external to the F* theorem or requiring a separately verified refinement.
- **Open:** unresolved choice that does not block this direction.

F* documentation confirms dependent arrows, refinements, total functions, user-defined effect specifications, ghost erasure, and OCaml extraction. That establishes language expressivity, not persistence or host correctness ([dependent refinements](https://fstar-lang.org/tutorial/book/part1/part1_getting_off_the_ground.html), [effects](https://fstar-lang.org/tutorial/book/part4/part4.html), [extraction](https://fstar-lang.org/tutorial/book/part1/part1_execution.html), [ghost effect](https://fstar-lang.org/tutorial/book/part4/part4_ghost.html)).

## 3. Current prototype: starting point and gaps

**Observed:** current `workflow i o` has constant input/output types and an in-memory evaluator closure; `then_flow`, `fork`, and `lift` are typed but nondependent. `fork` evaluates both sides on the same input and returns a left/right pair. The persisted manifest describes structure and code identities but is not an executable AST. (`WorkflowCore.fst:229–260,459–560`.)

**Observed:** `pure` invokes its `CodeRef.apply` during every evaluation. `resume_evaluate` decodes the root and re-evaluates the plan. Local outputs are not memoized. External operations persist intents/status/output wire, but have no semantic output validator. (`WorkflowCore.fst:459–481,842–864,945–1031`.)

**Observed:** the reducer has selected event/replay/budget invariants, but no general theorem links the extracted OCaml runner, JSON snapshot operations, adapters, and process recovery to those model transitions. The existing runner uses hard-coded immediate/deferred/fault outcomes and a process-local queue. It does not run a real analyzer or service call. (`Runner.ml:87–140,143–171,193–290`; implementation report §proof ledger.)

**Observed:** artifact validation accepts some byte/tree/reference shapes but rejects `MaterializedFile` and `LiveCapability`. There is no real filesystem materializer, output collector, or digest-backed external blob store. (`WorkflowCore.fst:654–668`; `Runner.ml`.)

**Decision:** keep the typed work-node and event-reducer ideas; redesign the output index, context composition, local completion protocol, semantic validator boundary, and adapter/resource contract. Do not claim the current prototype already has no-rerun or all-cut recovery properties.

## 4. API alternatives and choices

| Choice | Alternative A | Alternative B | Decision and reason |
|---|---|---|---|
| Workflow result | Fixed `I -> B` carrier | Dependent family `O : I -> Type` | Use `Work I O`. It directly types results such as prime numbers greater than the particular input. A fixed carrier plus input-indexed postcondition remains a convenient alias. |
| Correctness contract | Separate `P : I -> B -> prop` wrapper | Result itself is a refinement/sigma containing evidence | Put evidence in `O x`, with `Verified` as a helper adding a postcondition to any output family. For fixed-carrier outputs it is the familiar postcondition form. Avoid two kernel notions of verified work. |
| Sequencing | Runtime continuation selected from computed output | Static second work node over packed `(input, intermediate)` context | Use static context composition. No arbitrary closure is persisted; F* sees original input and proof evidence. |
| Same-input pairing | `fork` | `fan` | Call it `fan`: it describes same-input product dataflow, not a promise of concurrent execution. `fork` may be kept temporarily as a deprecated synonym if compatibility matters. |
| Retention/projector | Explicit `fork(it, f)` only | `keep_input(f)` helper plus ordinary projections | Restore `it`; provide `keep_input`. Ordinary F* `fst`/`snd` and record projections stay the projectors. |
| Resource interpretation | One opaque whole operation | Scoped effect/capability or a kernel protocol AST | Use a whole-operation adapter in the kernel. It is smallest and directly fits static analysis/JEV; optional scoped resource libraries can expose stepwise proof only when a real case needs it. |
| Persisted plan | Serialize arbitrary continuation/author callback | Persist structural plan IDs and typed events; rebuild callbacks from pinned code | Persist stable structure, IDs, schemas, requests/results, and state. Do not serialize arbitrary callbacks or captured native handles. A defunctionalized AST for all F* author code is not required. |
| `Blob` | Universal kernel artifact | Domain type interpreted by an adapter | Choose the latter. File libraries may define file-tree types; network/database libraries need their own types. |

### Why not a continuation API?

A continuation chosen after a computed value is ordinary F* code but not a durable value. After restart it must be reconstructed through stable code identity, registry lookup, and saved captures. Static context composition gives the same dependent expressivity while the entire plan remains declared before execution. A routing node such as current `so` can still select a stable child reference and persist that choice; it does not serialize a new callback.

### Why not a mandatory capability DSL?

A `CapProgram` with its own `Acquire`, `Invoke`, `Collect`, and `Release` constructors is a second workflow language if the runner interprets it. If ordinary F* code is allowed between those instructions, its continuation and local state still need a recovery representation. Fine-grained protocol states also add crash cuts without making filesystem or remote effects atomic. Keep lifecycle details in an adapter contract until an example requires them as independently composed work nodes.

## 5. Candidate F* surface

All signatures below are semantic F* notation. A follow-up typecheck must settle exact syntax, universes, equality transports, extraction, and codecs.

### Work family and proof-bearing outputs

```fstar
type Work (i:Type0) (o:i -> Type0)

// A work node whose result establishes p for its exact input.
type Verified (i:Type0) (o:i -> Type0)
              (p:(x:i) -> o x -> prop) =
  Work i (fun x -> { y:o x | p x y })

// Ordinary nondependent output B is Work i (fun _ -> B).
```

The output family can use an input refinement directly, such as `O x = { n:nat | prime n /\ n > x }`. `Verified` adds a postcondition to any output family; with a fixed carrier it is the familiar fixed-carrier/postcondition form. The proof is type-level evidence, not a durable byte field. If a later algorithm needs evidence computationally, make a certificate or witness part of the runtime output and prove its checker sound.

### Dataflow and context composition

```fstar
val it : #i:Type0 -> Work i (fun _ -> i)

val fan : #i:Type0 -> #a #b:(i -> Type0) ->
  Work i a -> Work i b -> Work i (fun x -> a x & b x)

// Semantic notation: Sigma means F*'s dependent pair, e.g. (x:i & m x).
type Ctx (i:Type0) (m:i -> Type0) = Sigma (fun x:i -> m x)

val then_keep : #i:Type0 -> #m:(i -> Type0)
  -> #n:(Ctx i m -> Type0)
  -> Work i m -> Work (Ctx i m) n
  -> Work i (fun x -> Sigma (fun y:m x -> n (x,y)))

val keep_input : Work i m -> Work i (fun x -> i & m x)
let keep_input f = fan it f
```

`then_keep f g x` evaluates the fixed node `f` on `x`, forms context `(x, f(x))`, evaluates fixed node `g` on that context, then returns `(f(x), g(x,f(x)))`. If `m x` is a sigma/refinement, the context carries its proof evidence to `g`. The result retains the intermediate output and final output. A convenience sequencing form that drops the intermediate is a typed projection over this result and is library-level.

`it` is a structural identity work node with a fixed manifest tag; it needs no callback registry entry. `keep_input` should have a canonical versioned manifest lowering (`KeepInput` + one child slot) rather than accidentally changing occurrence paths when implemented as `fan it f`. `fan` declares ordered slots. F* `fst`, `snd`, and named record selectors are pure typed functions, not durable nodes unless explicitly wrapped as one.

### Typed local work and durability hook

```fstar
type CodeRef (c:Type0) (i:Type0) (o:i -> Type0) = {
  code_id:string; code_version:nat;
  capture_codec:Codec c; input_codec:Codec i;
  output_codec:(x:i -> IndexedCodec (o x));
  capture:c;
  apply:c -> (x:i) -> Tot (o x)
}

val local : CodeRef c i o -> Work i o
```

These are API shapes, not proof that a currently extracted runner can resume them. To make strict no-rerun apply to every work node, evaluation must consult a completion table by stable occurrence before invoking `apply`. A missing node yields a local-run action; the result is encoded, checked, and durably committed as a `NodeCompleted` record before downstream nodes consume it. A complete record binds the exact run/plan/occurrence/input key, pinned code/schema identity, result wire, evidence/checker identity, artifact manifest, and terminal status. Conflicting duplicate completion is rejected.

An incomplete pure local node can be recomputed after a crash because it has no `NodeCompleted` record. This is safe under `Tot`/purity plus extracted refinement, but it may repeat expensive CPU work. If interrupted prime search must retain progress, represent chunks/checkpoints as separate durable work nodes or give the algorithm an explicit typed checkpoint state.

### Codec and proof restoration

An indexed result codec has the semantic form:

```fstar
encode : x:i -> o x -> Tot wire
decode : x:i -> wire -> Tot (option (o x))
roundtrip : forall x y. decode x (encode x y) == Some y
soundness : forall x wire y. decode x wire == Some y ==> ValidOutput x y
```

When `o x` is a refinement, the F* decoder must reconstruct a proof/check result for any accepted wire; its result type prevents a well-typed F* decoder from returning an invalid value. If proof evidence comes from a certificate, make certificate bytes part of the decoded value and prove the checker. Persist `schema_id`, version, input/index codec, checker ID/version, and code/build digest. Round-trip on encoder outputs does not prove integrity of arbitrary bytes, semantic correctness of an external report, or host parser correctness.

## 6. External operation and adapter contract

Separate a pure F* declaration/validator from a host driver. The host driver receives a committed intent and returns candidate correlated events; it does not write workflow state directly. Avoid assigning pseudo-`IO` semantics until an actual F* effect/runtime mapping is selected.

```fstar
type DriverCallKind = Dispatch | Redelivery | Poll | Reconcile
type OperationContext = {
  run_id:string; plan_digest:string; occurrence_path:string;
  attempt:nat; operation_key:string; request_digest:string;
  operation_digest:string; adapter_digest:string; config_digest:string;
  resource_digest:string
}

type Operation (i:Type0) (raw:Type0)
                (o:i -> Type0)
                (p:(x:i) -> OperationContext -> o x -> prop) = {
  operation_id:string; operation_version:nat;
  request_codec:Codec i; raw_codec:Codec raw;
  context_codec:Codec OperationContext;
  accepted_result_codec:(x:i -> ctx:OperationContext
    -> IndexedCodec ({ y:o x | p x ctx y }));
  diagnostic_codec:Codec Diagnostic; error_codec:Codec Error;
  validator_id:string; validator_version:nat;
  validate:(x:i) -> ctx:OperationContext -> raw
    -> Tot (option { y:o x | p x ctx y });
  maximum_charge:(x:i -> DriverCallKind -> nat)
}

type OpOutcome (x:i) (o:i -> Type0)
               (p:(x:i) -> OperationContext -> o x -> prop) =
  | Accepted : ctx:OperationContext & { y:o x | p x ctx y }
      -> OpOutcome x o p
  | Rejected : ctx:OperationContext & Diagnostic -> OpOutcome x o p
  | Failed   : ctx:OperationContext & Error -> OpOutcome x o p

val external : Operation i raw o p
  -> Work i (fun x -> OpOutcome x o p)
```

The evaluator's pending/dispatch/reconcile statuses are runtime states, not successful output values. `OperationContext` is constructed by the evaluator from the committed run/plan/occurrence/attempt/request and pinned operation/config identities; author code cannot choose it. Before `Accepted` is exposed, the result must correlate to this exact context, decode as `raw`, pass the F* validator, pass artifact checks, and commit. A terminal malformed response or failed validator becomes `Rejected`; a definite terminal process/service error becomes `Failed`; unresolved possibly-applied effects put the run in durable `Unknown` status and suspend the workflow. A workflow can handle terminal `OpOutcome` cases through typed F* branches. Pending is not converted into success or failure.

`Unknown` is not a memoized `OpOutcome` constructor. It is the durable projection of an unresolved attempt, exposed by the run/status API while the workflow is suspended at that occurrence. Reconciliation resumes that same occurrence/attempt and appends evidence; it does not mutate a previously completed output. If the attempt becomes terminal, the node commits an `Accepted`, `Rejected`, or definite `Failed` result under its result codec. A new attempt after authenticated `NotApplied` requires an explicit retry policy. `Rejected` describes output/policy validation and by itself does not prove that an external side effect was not applied; only correlated effect-disposition evidence authorizes that conclusion. Unknown remains distinct from operation-level errors and can never flow downstream as a fabricated typed result.

**Retry decision:** automatic dispatch retries, polls, and reconciliation calls have finite configured limits and per-call budget reservations. When that policy is exhausted, persist `Unknown` and stop automatic calls. A caller may explicitly request another bounded reconciliation call for the same unresolved attempt; it receives a new call ID and reservation but the same operation key. Only authenticated `NotApplied` may authorize a fresh dispatch attempt, and only if the operation's declared retry policy permits it. This prevents unbounded polling and makes user-driven recovery auditable.

`context_codec`, `accepted_result_codec`, and codecs for the `Rejected` and `Failed` payloads define the tagged terminal `OpOutcome` wire. The accepted branch codec is required because the validator's proof may erase during extraction. It encodes the accepted data value, and its indexed decoder reconstructs `{ y:o x | p x ctx y }` by running a pinned F* checker or verifying a stored runtime certificate against the persisted context. Require round-trip for encoded accepted values and soundness for every accepted wire. Restore compares the context wire with the exact completion key before exposing the result. Persist either this validated result/context wire plus checker identity, or the raw response and rerun the pinned validator against the saved context; do not persist only an erased proof object. The operation completion record binds which representation it stores.

The durable key is derived from `(run, occurrence, attempt, operation content/version, immutable config fingerprint, canonical request digest)`. Persist the key, request, code/adapter/schema versions, reservation, and evidence. After a lost reply, only these paths are safe: reconcile the same key; redeliver the same key under an idempotency contract; accept authenticated definite `NotApplied` then admit a new attempt; or persist `Unknown`. A local ID is not remote exactly-once.

### Inline and library authoring

Both forms instantiate exactly the same `Operation` and `Driver` contract:

```text
Inline module:  define Operation + validator + binding next to workflow
Library module: export Operation constructor + validator + binding; application configures/imports it
```

Workflow types, codec laws, validation obligations, status protocol, budget rules, recovery, and proof assumptions are identical. Module placement/reuse is the only intended distinction. The binding/closure itself is not serialized; resume resolves pinned operation/adapter code from a registry or reports it unavailable. Equivalent behavior is proved or assumed by a relation between implementations; equal string IDs/config labels are necessary but not sufficient.

Verified adapter logic can be ordinary F* code over abstract host operations and typed results. F* can prove the local protocol logic and validator under their effect specifications. The concrete OCaml/OS implementation must separately refine those specifications. Filesystem safety, process termination, remote authentication/idempotency, billing truth, and storage durability do not follow from F* typing alone.

## 7. Resource and artifact interpretation

### Kernel versus libraries

Kernel persistence is generic: a typed codec/schema, a completion record, durable bytes or an opaque content reference, provenance IDs, and an atomic/recoverable commit. It does not define a universal `Blob` value or persist native paths, descriptors, sockets, PIDs, DB cursors, sessions, or closures.

A domain library defines a type and its meaning to an adapter:

- CLI library: `SourceTree` and `OutputTree` describe relative file paths and exact file bytes.
- Network library: typed request/response, endpoint/config identity, server receipt, and idempotency/reconciliation key.
- Database library: query/snapshot/cursor/checkpoint description and typed rows/aggregate.
- JEV/model library: prompt/context/request and raw result/usage evidence, with provider-specific charge/retry semantics.

Large values may be stored in a generic content-addressed byte store and represented in workflow state by a typed, versioned reference. The domain codec says whether the bytes mean a file tree, report, model context, or something else. A digest checks correspondence to bytes under the hash/store contract; it does not prove provenance or semantic truth.

### Static analyzer

```text
SourceTree
  -- external analyze operation --> RawAnalysis { report bytes, collected output files }
  -- F* parse node -------------> ParsedFindings + ReportWellFormed proof
  -- F* check node -------------> VerifiedFindings + Sound(source, findings) proof
```

The analyzer adapter receives a versioned request containing the exact source-tree digest, path schema, pinned executable/container digest, argv/config, output allowlist, and budget. It validates and materializes the tree into a fresh isolated workspace, runs the tool, captures exit status/diagnostics, collects only declared outputs, and returns report bytes plus a typed output manifest. It never exposes its temporary paths or live process handle as workflow artifacts.

The returned `RawAnalysis` also carries a `ReportProvenance` receipt containing the exact source-tree digest, pinned tool-build digest, config digest, operation key, report digest, and output-manifest digest. The validator compares this receipt with the committed `OperationContext` and hashes of the actual report/output bytes before accepting it. Persist the provenance receipt with the accepted output and artifact manifest. The F* checker proves that these fields agree; it does not prove that a real analyzer actually read those files or generated those bytes. That final fact remains an adapter/host-refinement assumption or a trusted tool attestation. `Sound(source, findings)` still requires the separate F* checker or certificate proof.

The digest abstraction is proved only relative to a correct digest implementation. If content identity relies on cryptographic hashes, assume canonical encoding and collision resistance; otherwise use exact structural equality in the model.

The adapter must satisfy or refine contracts such as:

```text
ValidTree(t) / Materialize(root,t)=Ok(paths)
  ==> confined(paths, root) / Read(paths)=t

Collect(root, contract)=Ok(tree)
  ==> ValidTree(tree)
      / dom(tree) subset contract.allowed
      / contract.required subset dom(tree)
      / each returned byte string equals bytes from a confined regular file
```

Confinement includes symlink/race policy, path collision rejection, regular-file checks, output byte caps, required/optional output rules, and atomic publication. File metadata is excluded unless explicitly part of the file contract. A safe reversible filename encoding must preserve the logical relative path; analyzer diagnostics that mention encoded paths need a proved mapping back to source paths.

Persist content bytes first and verify digests. Stage the manifest privately; do not make it consumer-visible until the workflow completion record commits, or make visibility reads require that completion record. If blob storage and journal do not share a transaction, use idempotent staged records and prove repair for every state. Orphan staging bytes are safe; a committed result pointing at absent/corrupt bytes is not. On restore, rematerialize from bytes/references or report unavailable. Never treat a saved temporary path as content.

Parsing proves syntax/shape only. To claim findings are true, a checker must recompute the property in F* or verify a certificate with a proved checker. Otherwise return `ParsedFindings` or `UnverifiedFinding`, not `VerifiedFinding`.

### Network, database, and JEV cases

- **Simple read request:** a library operation encodes typed request, pins endpoint/TLS/schema identity, and returns raw status/body/receipt. F* validates schema and requested predicates. A read can be retried under a declared idempotent/read-consistency contract; changing remote state means retry may return different data unless a snapshot/version is bound.
- **Mutation or model request:** key binds the same occurrence/attempt/request/config tuple. A provider idempotency token or authenticated reconciliation is required after lost reply. Otherwise return `Unknown`, hold reservation, and forbid fresh-key retry. JEV-like library code supplies the same declaration/validator/driver shape as inline code; usage/billing is an assumption unless authenticated evidence is validated.
- **Database scan/transaction:** the adapter owns transaction and cursor lifecycle as one operation. If F* must validate each page and aggregate, a scoped `Cursor h Open` capability may live inside the adapter library and thread protocol state. The cursor is never serialized; persist a durable snapshot/token/checkpoint if supported. Without a stable snapshot or recoverable cursor, resume reports `Unknown`/unavailable or restarts only under a declared safe-read contract. A lost commit reply is unresolved until reconciliation.

The scoped capability is not a kernel primitive. Rank-2 typing may prevent a direct handle from escaping under its type assumptions, but does not prove linear use, release, process confinement, or host behavior. F* effect specs can verify local call ordering and invariants; concrete handler/extraction/OS refinement remains separate.

## 8. Durable state machine and theorem targets

Use an append-only journal with a current projection. Model durable store `D`, volatile runner `V`, backend state `B`, artifact store `A`, scheduler state `Q`, and pinned workflow/plan `W`. Crash drops volatile state; it may not erase effects already applied in `B`. “Committed observation” means a locally journaled and durably acknowledged event, or an externally published effect explicitly included in the observation model. A backend effect that happened without a committed receipt is not locally known; recovery must preserve the possibility that it happened and may therefore report `Unknown`.

For each occurrence/attempt, distinguish at least:

```text
Absent
IntentCommitted(key, request_digest, max_charge, pinned identities)
DispatchMayHaveOccurred(key)      // durable before entering driver
CallEntered                         // volatile only
BackendMayHaveApplied               // backend state, not local knowledge
ReplyReceived                       // volatile until receipt commit
ReplyReceiptCommitted(raw digest)
OutputValidated(value digest, checker identity)
ArtifactBytesDurable(digests)
ManifestStaged(refs)                 // private; consumers cannot resolve it
ManifestValidated(refs)
CompletionCommitted(value, evidence, refs, charge, terminal outcome)
ManifestVisible(refs)                // visibility is gated by committed completion
Consumed(value digest)
Unknown(reason)                      // dispatch-quiescent projection
```

`DispatchMayHaveOccurred` is intentionally conservative. A crash between committing it and entering the driver is treated as possibly sent. `CompletionCommitted` is a structural record that links a node occurrence, pinned identities, encoded value/evidence identifiers, all artifact refs, and one settlement. **Do not define it as “recoverable”; prove that committed records survive allowed cuts under a storage refinement contract.**

The durable completion key binds at least `(run_id, plan_digest, occurrence_path, input_or_request_digest, node_kind, output_schema_id/version, code_build_digest, checker_validator_digest, adapter_digest)`. The journal proves this key is unique for a run occurrence and immutable across retries. A record at the same path with a different input, plan, or pinned identity is a conflict and fails closed. If completion bytes, evidence, or artifact references later fail validation or are unavailable, recovery reports `Unavailable/Corrupt`; it never silently invokes the body again. Staged manifests are private. A resolver exposes references only when it can also verify the matching committed completion. Cross-store implementations must prove this gate even when a crash occurs between manifest staging, validation, journal commit, and any physical publication/index update.

`Unknown` is dispatch-quiescent, not history-erasing or terminally immutable. Reconciliation may append correlated evidence that refines its current projection to `Applied`, `Failed`, or authenticated `NotApplied`; its prior Unknown event remains. It may not launch a fresh attempt while unresolved, infer non-application from timeout/process death, or automatically poll forever. Pending may have a bounded policy; after deadline/attempt budget it reaches durable `Unknown`.

### P1 — dependent composition

For `f : Work I M` and `g : Work (Σ x:I. M x) N`, for every `x:I`, if `f(x)=m` and `g(x,m)=n`, prove:

```text
then_keep(f,g)(x) = (m,n)
and has type Σ m:M(x). N(x,m).
```

When `M(x)` and `N(x,m)` contain refinements/sigma evidence, the result retains it. No cast, arbitrary closure serialization, or proof reconstruction from an untrusted byte is used. `fan` preserves declared pair order; projections preserve untouched fields. Pending/failure is evaluator state and never forges an output value.

### P2 — memoized completed work is not reinvoked

For all pinned plans and every trace `t` generated by the specified resume transition relation from a valid initial state, under an exact run, plan, input, occurrence, and pinned-code identity:

```text
TerminalCompletion(D0, A0, run, planDigest, occurrence, inputDigest,
                   nodeKind, outputSchema, codeBuild, checkerValidator,
                   adapter, terminalWire, evidence, refs)
/ ValidatedByReplayAndTypedDecode(D0, A0, W, exactKey)
/ ResumeTrace(D0, V0, B0, A0, Q0, W, run, planDigest, inputDigest, t)
  ==> count(t, InvokeLocalBody(exactKey)) = 0
      / count(t, DispatchFreshAttempt(exactKey)) = 0
      / every Consume(exactKey, y) uses the checked decode of exactly
        (terminalWire, evidence, refs) under those pinned identities.
```

The completion uniqueness/injectivity invariant must show that one exact key denotes one node occurrence and one input in the pinned plan. If an implementation stores hashes, canonical encoding and collision resistance are assumptions; the mathematical model uses injective content identities. This theorem does not assume “resume short-circuits”; prove that evaluator rule and then prove extracted runner simulation. It excludes reducer lookup, decoding, and separately identified sound checkers from `InvokeLocalBody`. For an incomplete pure node, recomputation is allowed and can be costly. For an incomplete external operation, recovery reconciles/same-key redelivers under the adapter contract or reaches Unknown; it does not pretend prior process success. Retries after definite NotApplied occur inside the still-incomplete occurrence under its explicit retry policy. Once any terminal outcome is committed, no fresh body invocation or attempt occurs for that occurrence. An invalid or unavailable completion takes the explicit `Unavailable/Corrupt` path and is not recomputed.

### P3 — recovery prefix safety at every concrete cut

Let `e` be a finite concrete execution and `c` any concrete cut. For the current extracted runner, enumerate JSON snapshot cuts at temp-file creation/write, flush, file `fsync`, rename, directory `fsync`, in-memory projection update, adapter dispatch-marker commit, driver entry, backend effect, reply arrival/receipt commit, validation, each artifact byte write/flush/`fsync`, manifest staging/validation, completion commit, and downstream consume. If SQLite is chosen later, separately enumerate transaction begin, every write, commit, and recovery. Map each cut to the exact old/new/uncertain state allowed by the concrete storage contract; do not silently assume JSON and SQLite have the same failure semantics. Under those per-primitive storage refinements, pinned-code compatibility, reducer correctness, adapter safety, and evidence checks, prove:

```text
RecoveryPrefixSafety(e,c)
  ==> all post-restore effects are allowed by the keyed adapter protocol
      / no committed consumer reads invalid or missing output
      / no attempt settles budget twice
      / unresolved effect is never reported success or given a fresh key
      / every durably committed local observation before c is preserved
      / every unjournaled backend effect remains represented as possible/Unknown
      / uncertain effects remain Unknown until valid evidence arrives.
```

If a downstream consumer can observe a file/reference before node completion, that publication is itself an external effect and must be included in this cut model. Prefer to fence visibility through the completion record. If durable storage cannot append while unavailable, no theorem can promise a durable `Unknown` record until storage progress resumes.

The target refinement must give concrete outcomes for every cut. For a JSON snapshot on a supported filesystem: before rename, the prior snapshot is authoritative and an incomplete temp file is ignored; after atomic rename but before successful directory sync, recovery may see the complete old or complete new snapshot and must validate/replay either; after successful file and directory sync, the new snapshot is durable under the OS/filesystem contract. A torn or invalid snapshot fails closed and cannot authorize dispatch. If directory sync reports an unsupported/error status, the runner must not treat the write as a durable commit unless a platform-specific contract supplies an equivalent guarantee. The current runner ignores `EINVAL`/`EBADF` from directory sync, so this target rule is not established by current code. Before a dispatch marker commits, no driver call may occur; after it commits or its commit is ambiguous, recovery treats dispatch as possibly occurred. Before a reply receipt commits, a lost volatile reply leaves the attempt unresolved; after receipt commit, replay checks correlation and validation before completion. Partial staged artifact bytes are unreferenced; a private manifest cannot be resolved; only a completion-gated manifest is consumable. Before a local completion commit, pure work may be recomputed; after a valid completion, lookup/decode must bypass its body. These are required mappings to prove against actual host calls, not claims about the present runner.

This is the base guarantee. Stronger uninterrupted/restarted observation equivalence additionally requires related backend states plus adapter and scheduler bisimulation. Define fan traces modulo swaps of independent events while preserving causal order; exact ordered trace equality needs a deterministic scheduler. Do not use “same future replies” without binding replies to the same backend state/history and operation key.

For the first implementation refinement, target the existing single-writer JSON snapshot store and its same-directory temp/write/fsync/rename/directory-sync protocol. The abstract journal semantics do not depend on JSON. Require a supported OS/filesystem profile with durable file and directory sync, and make unsupported/error sync results fail the durable-commit contract; do not treat the current ignored `EINVAL`/`EBADF` cases as proved durability. The current per-write lock is not a single-run-loop lock, so the target contract also requires one active runner per run. A later SQLite backend is a separate refinement proof against the same abstract journal.

Without backend idempotency or truthful authenticated reconciliation, two worlds can have the same local bytes after a lost reply while one effect happened and the other did not. Resending duplicates one world; skipping loses work in the other. `Unknown` is the strongest truthful result.

### P4 — adapter safety and progress

Safety obligations per `(run, occurrence, attempt, operation digest, config fingerprint, request digest)`:

- Every driver call follows a durable committed intent/reservation and a dispatch marker; prove there is no bypass path.
- Results correlate to that exact key; stale/conflicting replies cannot overwrite committed terminal state.
- Raw bytes are decoded and semantically validated before downstream use.
- Fresh attempt follows authenticated `NotApplied` or an explicitly weaker policy. Same-key redelivery requires backend deduplication.
- Output artifacts and proof/certificate evidence are committed before success becomes visible.
- Overcharge becomes durable violation/quarantine, never silently clamped verified success.
- Construction/importing an operation descriptor has no effect.

Make adapter evidence semantics explicit. For each exact `OperationContext`, `ReportsApplied(receipt)` must imply that the keyed backend effect occurred and the receipt belongs to that request; `ReportsNotApplied(receipt)` must imply that the backend did not apply that keyed effect. F* can verify receipt structure, signatures, key binding, and transition use. Signer authenticity and truth about backend state require a sound provider/attestation contract or remain trusted assumptions. A signature alone proves only that the signer made a statement.

Prove local attempt quiescence from `DispatchMayHaveOccurred` under **nonvacuous** assumptions: after finitely many crashes a stable runner interval exists; scheduler is weakly fair; every unresolved attempt has an enabled durable timeout action; deadline/retry state advances; each adapter call is bounded and killable/isolateable; durable commits finish in finite time; local validation terminates. Then every unresolved attempt reaches a durable terminal projection or durable `Unknown`. If the store is unavailable, durable quiescence is not promised until it recovers. A timed-out worker is fenced by `(run, occurrence, attempt, request digest)`; any late reply is recorded only as evidence for that same attempt and cannot overwrite a newer terminal state or launch a fresh attempt. This does not imply remote success. Eventual remote completion needs backend liveness. A watchdog cannot bound an uninterruptible foreign call unless the host can kill/isolate it.

```text
Unresolved(run, occurrence, attempt) / StableStoreAndRunner / FairScheduler
/ BoundedKillableCalls / EnabledDurableTimeout / TerminatingLocalChecks
  ==> eventually (DurableTerminal(run, occurrence)
                 or DurableUnknown(run, occurrence, attempt)).
```

This is a conditional quiescence theorem, not a promise that the remote operation eventually succeeds. If storage stops progressing, no durable-terminal/Unknown conclusion follows until commits resume.

### P5 — budget

**Decision:** use a per-call ledger because dispatch, polling, same-key redelivery, and reconciliation can each incur distinct charges. Every cost-bearing call has a stable call ID under its run/occurrence/attempt, a declared maximum, one reservation, and at most one settlement. A call cannot start unless its reservation fits the configured admission cap. Unknown calls keep the unused reservation until charge evidence arrives or policy conservatively settles the maximum. The kernel ledger is an admission/accounting bound; it is not a claim about actual provider spend. Track provider-reported spend separately and prove a spend bound only under truthful charge evidence and provider behavior. This keeps the two claims distinct.

```text
valid(budget) and not Quarantined
and reserved = sum(reservation(call) for open cost-bearing calls)
and spent = sum(charge(call) for settled calls)
and every call has one immutable reservation and settles at most once
and spent + reserved <= limit.
```

Admission plus reservation linearizes against the latest serialized state before dispatch. Track actual charge separately from whether the requested effect applied: authenticated `NotApplied` does not imply zero charge. Release only unused reservation and settle any known charge; define failure/cancellation and reconciliation charges explicitly. The journal must prove attempt/call identity, immutable reservations, unique settlement event IDs, rejection of duplicate/late conflicting settlements, and serialized concurrent admission. Kernel proves local ledger arithmetic only. Real provider spend is bounded only if adapter/provider charge evidence is truthful and the provider honors each maximum. If observed charge exceeds a reservation, record the full charge and overage, enter durable `Quarantined`, stop admission, and report the cap violation; do not clamp the charge or claim the normal budget invariant still holds. Current reducer status transitions do not verify authenticated adapter evidence, so those lemmas are not this stronger charge theorem.

### P6 — artifacts and materialization

Under an OS/adapter contract, prove input materialization preserves the exact logical tree within a confined root; collection returns only declared confined regular files with exact bytes and all required paths. Distinguish staged bytes, a private staged manifest, manifest validation, workflow completion, and consumer visibility. Completion is the visibility gate: no consumer can resolve a result reference until a matching completion commits, even if blob bytes or a manifest index were published physically earlier. If the store uses a separate publication step, it must be idempotent and hidden from consumers until completion. Restore either reloads/rematerializes verified bytes or reports unavailable/corrupt; it never consumes a temporary path as durable content. Availability after acknowledged durability is guaranteed only under a storage contract that promises retention/readback; otherwise recovery may report unavailable and must not re-run the node.

F* can prove path/tree validation, codec/checker logic, and abstract transition rules. Filesystem race/symlink behavior, process isolation, persistence ordering, hash implementation, and host parser correctness require verified host refinement or explicit assumptions. Tests do not replace them.

### P7 — model-to-runtime refinement

Prove the actual extracted scheduler/runner and store implement the abstract action/event machine. Relate F* values, manifests, occurrence paths, JSON/SQLite bytes, local task invocation, external calls, artifact writes, and exception/timeout handling. Verify that the exact compiled callback/validator/adapter set matches persisted content/build IDs, and that host crash recovery returns only committed state. Existing F* reducer lemmas do not imply this simulation.

## 9. What each language/runtime layer proves

| Layer | Proof or evidence it can own | Boundary that remains |
|---|---|---|
| F* work types and combinators | Endpoint typing, input-indexed refinements, proof-preserving composition, branch order, local functions' stated contracts | Does not persist values or establish extracted behavior. |
| F* codec/checker library | Round-trip, decoder soundness, indexed proof reconstruction, report parser/checker soundness | Does not prove host JSON bytes, file writes, real process output, or a third-party analyzer's truth. |
| F* reducer/model | Event legality, unique attempts, replay projection, budget accounting, completion immutability, selector availability | Does not establish filesystem/SQLite crash semantics or runner refinement. |
| Adapter contract | Correlation, idempotency/reconciliation, materialization/collection, output completeness, bounded-call policy, evidence format | Actual adapter/provider/OS behavior must refine contract or be trusted explicitly. |
| Extracted OCaml and host | May provide the executable adapter/store and can be tested at selected cuts | Needs a simulation proof or narrow trusted boundary; tests alone do not prove all cuts. |

No proof is rejected because it is long. If a property is true under explicit and acceptable assumptions, the next phase should attempt the proof, however intricate. If a property is false without an assumption, retain the counterexample and state the assumption instead of hiding it.

## 10. Representative designs and acceptance cases

These are the required authoring examples for the next spec. Examples are semantic pseudocode until typechecked.

### Retain input and use both pieces later

```fstar
val attempts : Work State (fun s -> List Attempt)
val with_attempts = fan it attempts
// output: (state, attempts)
val summarize : Work (State & List Attempt) Summary
```

Equivalent ergonomic form:

```fstar
val retained = keep_input attempts
```

The pair order and projection use normal typed F* fields. A pending attempt branch does not erase already completed sibling values; the join is exposed only when its typed output is available.

### Dependent verified computation

```fstar
type PrimeAfter (x:nat) = { n:nat | prime n /\ n > x }
val next_prime : Work nat PrimeAfter
val next_prime_again : Work (Sigma (fun x:nat -> PrimeAfter x))
  (fun c -> PrimeAfter (fst (snd c)))
val two_primes = then_keep next_prime next_prime_again
```

The second node is declared statically and receives original `x` plus the first prime/proof. The result retains both witnesses. On restore, decode the natural and re-establish primality and inequalities with checked F* code/certificate; never deserialize an erased proof object.

### Static-analysis files

```fstar
type Source = CliFiles.SourceTree
type ReportProvenance = {
  source_tree_digest:string; tool_build_digest:string; config_digest:string;
  operation_key:string; report_digest:string; output_manifest_digest:string
}
type Raw = {
  report:ReportBytes; outputs:CliFiles.OutputTree;
  provenance:ReportProvenance
}
type AdapterReportShape (s:Source) (ctx:OperationContext) (r:Raw) : prop =
  r.provenance.source_tree_digest = digest(s)
  /\ CanonicalRequestBindsSource(ctx.request_digest, digest(s))
  /\ r.provenance.tool_build_digest = ctx.resource_digest
  /\ r.provenance.config_digest = ctx.config_digest
  /\ r.provenance.operation_key = ctx.operation_key
  /\ r.provenance.report_digest = digest(r.report)
  /\ r.provenance.output_manifest_digest = digest(r.outputs)
type RawResult (s:Source) =
  OpOutcome s (fun _ -> Raw) (fun s ctx r -> AdapterReportShape s ctx r)
type AcceptedRaw (s:Source) (r:RawResult s) (raw:Raw) : prop =
  | IsAcceptedRaw : ctx:OperationContext &
      proof:AdapterReportShape s ctx raw ->
      AcceptedRaw s (Accepted (ctx, { raw | proof })) raw
type Parses (report:ReportBytes) (p:ParsedReport) : prop
type ParseResult (s:Source) (r:RawResult s) =
  | Parsed : raw:Raw & AcceptedRaw s r raw & p:ParsedReport &
      Parses raw.report p & WellFormed s p -> ParseResult s r
  | ParseRejected : Diagnostic -> ParseResult s r
  | ParseFailed : Error -> ParseResult s r
type Analyzed (s:Source) = Sigma (fun r:RawResult s -> ParseResult s r)
// Relational witness: a contains (Accepted raw, Parsed p), Parses raw p,
// and f is extracted from p. No constructor exists for rejected/failed input.
type HasSuccessfulParse (s:Source) (a:Analyzed s) (f:ParsedFindings) : prop =
  exists (r:RawResult s) (raw:Raw) (p:ParsedReport).
                  a = (r, Parsed(raw, acceptedProof, p, parseProof, shapeProof))
                  /\ AcceptedRaw s r raw /\ Parses raw.report p
                  /\ ExtractsFindings p f
type CheckedResult (s:Source) (a:Analyzed s) =
  | SoundFindings : (f:VerifiedFindings & Sound s f) -> CheckedResult s a
  | Unverified : f:ParsedFindings & HasSuccessfulParse s a f -> CheckedResult s a
  | CheckRejected : Diagnostic -> CheckedResult s a
  | CheckFailed : Error -> CheckedResult s a

val analyze : Operation Source Raw (fun _ -> Raw)
  (fun s ctx r -> AdapterReportShape s ctx r) -> Work Source RawResult
val parse_report : Work (Ctx Source RawResult)
  (fun c -> ParseResult (fst c) (snd c))
val after_parse : Work Source Analyzed
  = then_keep analyze parse_report
val check_findings : Work (Ctx Source Analyzed)
  (fun c -> CheckedResult (fst c) (snd c))
val workflow : Work Source (fun s -> Sigma (fun a:Analyzed s -> CheckedResult s a))
  = then_keep after_parse check_findings
```

The adapter materializes input files and collects output files. F* parses and checks. If `Sound` cannot be proved, use the parsed/unverified output family. The workflow can return output files as typed file-tree content or durable references and rematerialize them after restore.

### Simple request, event queue, JEV

The representative suite should include a scripted typed API request with success, malformed payload, timeout/lost reply, duplicate/late response, `Unknown`, reconciliation, and budget accounting. A deterministic event queue tests reducer progress/order without a network. A reusable JEV-like library packages the same operation/driver interface used inline and records provider config identity and charge evidence. Loopback HTTP may add host-boundary coverage, but does not replace the abstract adapter proof.

### DB/resource extension

Use a concrete cursor-scan case only to justify scoped capability work: F* validates each page and maintains a verified aggregate while an adapter owns a database snapshot/cursor. Persist logical snapshot token and checkpoint; recover/reacquire under adapter contract. If the DB cannot provide stable resume, expose `Unknown`/unavailable. Do not store native cursor/session values.

## 11. Required future acceptance matrix

| Case | What the test demonstrates | Theorem or assumption still required |
|---|---|---|
| Basic `it`/`fan`/`keep_input`/projection | Typed result shape and deterministic output | Type/composition theorem and stable occurrence slots |
| Dependent prime and `then_keep` | F* expresses input-indexed refinement and feeds proof-bearing context | F* typechecking/proof; indexed codec soundness; extraction refinement |
| CLI analyzer with nested files | Real materialization, process output, parser, returned files | Filesystem/process contracts, semantic checker proof, artifact commit/recovery theorem |
| Simple API and deterministic queue | Correlation, errors, pending/reorder/duplicate/late/unknown handling | Adapter authenticity/idempotency and conditional progress |
| Crash cuts around local and external work | Specific crash/restart paths preserve committed completion | All-cut transition induction and runtime/storage refinement |
| Inline and library binding | Same interface and sample trace under equal configuration | Implementation equivalence relation or same pinned implementation proof |
| Blob return/rematerialization | Typed files persist/reload and can be materialized again | Byte store integrity/durability and path confinement refinement |
| Budget boundaries | Reservation, latest-attempt accounting, overcharge and unknown behavior | Reducer theorem; remote spend still requires honest provider evidence |
| DB cursor library | Scoped F* checking within an adapter-owned resource | Capability effect/host refinement and DB snapshot/recovery contract |

Testing is future work in the implementation phase; this research pass did not run it.

## 12. Staged proof and implementation path

1. **Typecheck the dependent surface.** Prototype `Work I O`, `it`, `fan`, `then_keep`, `keep_input`, refinements, and indexed codecs in a small F* module. Compile to the target runtime and inspect the extracted dependent-pair/evidence representation. Resolve universe annotations and equality transport without weakening types.
2. **Define abstract execution semantics.** Add stable completion records for every local work node, external intent protocol, terminal outcomes, `Unknown` history, artifact staging, and attempt-aware budgets. State evaluator rules before implementing runner changes.
3. **Prove core theorems.** Prove composition/evidence preservation, node-slot uniqueness, codec round-trip/soundness, reducer invariants, terminal/completion immutability, local memo lookup-before-call, P1/P2/P5, and conditional progress under explicit premises.
4. **Prove cut recovery in the abstract machine.** Enumerate each durable/volatile/backend/artifact substate and prove prefix safety. Add backend bisimulation for stronger equivalence only if a concrete adapter supports it.
5. **Establish extracted-host refinement.** Specify the selected JSON commit operations, immutable build/registry identity, worker isolation/watchdog, artifact store, clock, and crash outcomes. Prove the extracted runner simulates the F* machine or list each narrowly trusted host primitive. Treat SQLite as a separate later refinement.
6. **Implement and test one local CLI adapter.** Materialize a nested `SourceTree`, run a pinned analyzer, collect a declared report/tree, stage/commit bytes, restore and rematerialize. Use injected crash points. Keep tests separate from theorem evidence.
7. **Add API/JEV library and deterministic queue.** Reuse exact operation types/contracts; cover retries, unknown, charge evidence, inline/library equivalence. Add network only if useful.
8. **Evaluate scoped DB capability.** Only after a concrete cursor workflow, compile a small capability effect and prove its page/aggregate invariant and extraction boundary. Keep it in a library unless minimal kernel requirements change.

Proof complexity is not a reason to stop any phase. A phase blocks only if the proposed property is false without a stronger external premise, and then the premise/result must be revised transparently.

## 13. Rejected or deferred choices

- **Arbitrary persisted continuations:** rejected because closures/captures are not durable values; static typed context composition carries required data and evidence.
- **Kernel path projector DSL:** rejected because F* projections are already typed functions, and string paths add schema/runtime semantics without stronger proof ability.
- **`fork` as concurrency promise:** rejected; same-input pairing is a dataflow combinator, while scheduling/fairness is a separate runtime theorem.
- **Fixed carrier-only API:** not selected as core; it can hide a missing input-dependent type. Keep `Verified I (fun _ -> B) P` as a convenience form.
- **Universal Blob type:** rejected; adapter-specific domain types express whether values are source files, reports, model contexts, network payloads, or database results.
- **Mandatory `CapProgram`/hybrid protocol interpreter:** rejected as minimum because it is a second DSL and adds cuts without removing host trust. Keep resource-specific scoped effects as optional library research.
- **Round-trip as external-output proof:** rejected; it says encoder-produced values decode, not that arbitrary returned bytes satisfy semantic predicates.
- **Unconditional exactly-once or unconditional crash equivalence:** rejected by the accepted-vs-not-applied lost-reply countermodel.
- **Proof effort as design penalty:** rejected; select for expressibility, truth, ergonomic use, and explicit trust boundary, then use agentic proof-oriented programming to discharge complex proofs.

## 14. Remaining open decisions

1. Exact F* syntax and universes for `Work I O`, dependent pairs, refinement evidence, `Verified`, and `then_keep`; the signatures are semantic notation pending a typecheck.
2. Whether local completion stores full values inline, content-addressed refs, or both under a size threshold. The theorem must be storage-path independent.
3. Exact F* error/result helpers and ergonomic pattern-matching combinators for terminal `Accepted`/`Rejected`/`Failed` outcomes. `Unknown` remains run status and suspension, by design.
4. Concrete scheduler implementation for the selected partial-order contract: independent `fan` branches are equivalent modulo swaps that preserve causality; exact event order is not promised.
5. Per-operation finite dispatch/retry/poll/reconcile limits and timeouts. The API policy is decided; domain-specific values and a durable timeout mechanism remain to specify.
6. Content/build identity and migration policy for plans, callbacks, codecs, validators, adapter libraries, and tool binaries. The model uses injective identities; a hash implementation requires canonical encoding and collision-resistance assumptions.
7. The single-writer JSON store is the first refinement target. Its supported OS/filesystem profile, ignored sync-error handling, and all-cut simulation remain unproved and must be resolved in implementation work.
8. Exact cache/artifact garbage collection and recovery behavior after storage loss; the public outcome is `Unavailable/Corrupt`, never silent re-execution.
9. A concrete DB case that justifies scoped capability library work and its recoverable snapshot protocol. This is intentionally deferred; whole-operation adapters cover the initial examples.

These are implementation-spec questions, not reasons to weaken the chosen type-level design. The core direction is selected; open questions concern exact F* encoding, storage/runtime refinement, and concrete host contracts.

## 15. Final review resolution

- **Proof review:** P2 now quantifies traces generated by resume and binds completions to exact plan/input/occurrence/code identities. P3 maps JSON cut classes to old/new/uncertain outcomes, distinguishes committed local events from unjournaled backend effects, and gates artifact consumption. P4 adds durable timeout actions and stale-worker fencing. P5 chooses per-call accounting and separates actual charge from effect disposition. Remaining issues are implementation obligations: concrete filesystem refinement, truthful adapter evidence, timeout machinery, and journal uniqueness/concurrency proofs.
- **F* API review:** added indexed accepted-result and operation-context codecs so extraction cannot erase the only proof of accepted output. `Unknown` is run/attempt status, not a memoized typed result. Dependent-pair syntax remains a semantic sketch pending typecheck; `Verified` applies to any output family.
- **API/adversarial review:** analyzer parse success requires an accepted raw result plus `Parses`; unverified findings require `HasSuccessfulParse`. `OperationContext` binds generated run/plan/occurrence/attempt/request and pinned implementation/config identities. `ReportProvenance` binds source, tool, config, operation key, report bytes, and output manifest. The host adapter must still attest or refine that the external analyzer actually read the materialized source and generated the returned bytes.
- **Resource review:** artifact references remain private until a completion-gated resolver exposes them. The existing single-writer JSON snapshot store is the first host-refinement target; its ignored directory-sync errors and per-write lock do not yet establish the target guarantee.

No independent review found a reason to reject the selected architecture. No F* signatures were compiled and no end-to-end proof or runtime property is claimed as established by this research phase.
