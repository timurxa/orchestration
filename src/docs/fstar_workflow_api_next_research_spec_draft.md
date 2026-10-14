# F* workflow API redesign: research and implementation specification

**Status:** Research/implementation specification draft. This revision defines the objective, semantics to settle, proof obligations, and acceptance suite. It makes no code changes; the resolved specification is intended to guide implementation.

## 1. Objective

Design a **minimal typed API for describing workflows as work nodes**. Authors should be able to reason about dataflow, correctness, effects, recovery, and resource budgets compositionally in ordinary F*. The API should make it natural to retain and project values, combine independent work, express input-relative guarantees, and invoke fallible external work.

The kernel should expose as few concepts as possible. Ordinary F* libraries may provide ergonomic combinators and domain-specific adapters. No API abstraction may hide an unmodeled effect, a result claim without a proof contract, or an unresolved recovery case.

Proof complexity is not a design burden or a reason to weaken a guarantee. Assume agentic proof-oriented programming can handle long, intricate proofs; this research should ask whether the API and runtime model make the desired statement expressible and provable in F*, with honest assumptions at host and adapter boundaries. Do not reject a useful correctness theorem because its proof may be difficult. Design the proof interface so that agents can state, decompose, and discharge those proofs.

The target claims include that durably completed work is not run again, restoration preserves observable behavior, and adapters satisfy explicit safety and progress contracts. Tests support these claims; tests alone do not establish them. The key limit is whether a claim is actually true under the modeled assumptions, not how much proof work it takes.

## 2. Current prototype and observed friction

The prototype has `Workflow<I,O>`, `then_flow`, `fork`, `lift`, `external`, and `so`. Its `fork` applies two workflows to the same input and returns an ordered pair. The dataflow is expressible, but `fork` is an awkward surface for retaining input, and the API lacks the Nim-style `it` identity/projector.

The Nim pattern

```nim
fan(it(State), make_approaches >>> lift(seq[here])[solve_approach])
```

returns both the original `State` and the attempts. Later work can project either value from that pair. The redesigned API must make this pattern direct and typed.

The current `external` declares a durable operation. It does not include a real process, network, or model driver; the OCaml runner uses dummy adapters. The prototype has `BlobBytes`/`BlobTree` representations and reducer artifact records, but no complete workflow path that materializes input files, runs a process, collects output files, and durably connects them to workflow results.

## 3. Semantic vocabulary

Use these terms consistently:

- **Workflow input type** `I` and **output family** `O : I -> Type0`. A nondependent workflow is the special case where `O` is constant.
- **Postcondition** `P : (x:I) -> O(x) -> Type0`. `P x y` states what is established about result `y` for input `x`.
- **Work node**: a typed workflow operation with stable identity, input/output schema, and execution semantics. A node may be local and total or may request external work.
- **Occurrence** `k`: one node instance in one run, identified by run identity and stable workflow path/slot. An attempt is identified separately.
- **Durable completion**: a validated result, artifact references, and terminal status committed as one recoverable transaction. A process merely returning in memory is not durable completion.
- **Adapter interpretation**: the capability-specific meaning of a typed external request/result, including any materialization, service call, collection, validation, and reconciliation.
- **Trace observation** `Obs`: final typed result and proof status; ordered externally visible operations; artifact bytes and provenance; locally accounted budget; and failures/unknown outcomes. Internal scheduler steps and restart markers may be abstracted as stuttering. Liveness is a separate property, not a finite-trace observation.

A candidate contract for a verified local node is:

```text
run : (x:I) -> Tot (y:O(x) & P(x,y))
```

An external response starts as raw data. A validator must establish the same contract before the workflow exposes a verified result:

```text
validate : (x:I) -> Raw -> Tot (option (y:O(x) & P(x,y)))
```

If no validator can establish a semantic property, expose a distinct unverified result with only the guarantees actually checked. Decoding or parsing alone must not imply semantic correctness. These signatures are semantic notation; the research must settle well-founded, typechecking F* encodings and their extraction boundary.

## 4. Dataflow API research

Work-node composition remains the design basis. Compare these plausible ways to improve retention and projection:

For dependent signatures below, let `A,B : I -> Type0`; constant families are the ordinary, nondependent case.

### A. Identity plus same-input fan

```text
it   : Workflow<I, fun _ -> I>
fan  : Workflow<I,A> -> Workflow<I,B>
    -> Workflow<I, fun x -> (A(x) & B(x))>
keep : Workflow<I,A> -> Workflow<I, fun x -> (I & A(x))> // derived as fan it
```

Here `Workflow<I,O>` means `O:I->Type0`; `fun _ -> I` is the constant output family for the ordinary identity value. `it` computes `x` on input `x`; `keep p` returns `(x,p(x))`, with the law `fst(run(keep p,x)) = x`. This directly expresses the Nim pattern: `keep attempts` or `fan it attempts`. Determine whether `it` is a built-in typed node or derived from a stable identity `CodeRef`; account for the codec and identity requirements at durable boundaries.

`fan` specifies same-input pairing and ordered pair results. State separately whether the scheduler may execute ready branches concurrently. Pairing and scheduling must not be conflated by the name or proof.

### B. Product/context combinators

For these candidate signatures, `A`, `B`, and `C` are ordinary types; this is shorthand for constant output families.

Investigate a small library of typed product operations, for example:

```text
first  : Workflow<A,B> -> Workflow<(A & C),(B & C)>
second : Workflow<A,B> -> Workflow<(C & A),(C & B)>
```

Compare these with explicit `it`, `fan`, and ordinary F* projection functions. Prefer typed F* functions over an untyped path language unless path syntax shows a material usability benefit.

For every candidate, establish endpoint typing, pair order, preservation of untouched values, and behavior when one branch is pending or fails. State which values need codecs and stable identities at each suspension point.

## 5. Dependent results and composition

Dependence is on **input values**, not merely on input types. The API must make the result type or its guarantee depend on the particular input. Compare and define both of these encodings:

1. **Dependent output family:** `O : I -> Type0`; each input `x:I` has result type `O(x)`.
2. **Fixed carrier plus dependent contract:** `B:Type0`, `P:(x:I)->B->Type0`; the returned value has fixed type `B`, while its guarantee depends on `x`.

The first directly expresses refinements such as `O(x) = { n:nat | prime n /\ n > x }`. The second can express the same claim as `P x n`. The spec must assess usability, inference, codecs, and composition rather than assume these encodings are equivalent in cost.

For dependent composition, define the families explicitly: `M:I->Type0`, `P:(x:I)->M(x)->Type0`, `N:(x:I)->(m:M(x))->P(x,m)->Type0`, and `Q:(x:I)->(m:M(x))->(p:P(x,m))->N(x,m,p)->Type0`. Stage one returns `m:M(x)` with proof `p:P(x,m)`; stage two accepts `x`, `m`, and optionally uses `p`, returning `y:N(x,m,p)` with proof `Q(x,m,p,y)`. A proof-preserving composition may return:

```text
x:I -> Tot (Σ m:M(x). Σ p:P(x,m). Σ y:N(x,m,p). Q(x,m,p,y))
```

If the public output hides `m`, define the resulting family and retained evidence, for example `Σ m:M(x). N(x,m)`, or prove an output-only postcondition. For fixed-carrier contracts, stage two may instead return `y:C` with `Q(x,m,p,y)`; composition must retain `m,p` as ghost witnesses or establish `R(x,y) = exists m,p. P(x,m) /\ Q(x,m,p,y)`. Specify whether a later node consumes a value, a value/evidence pair, or a checked encoding that reconstructs evidence.

Connect this rule to the work-node API, rather than treating stage two as a runtime-selected closure. One candidate is a context-passing combinator. Define `VerifiedFlow(I,M,P) = Workflow<I, fun x -> Σ m:M(x). P(x,m)>`, and define the fixed context type `Ctx = Σ x:I. Σ m:M(x). P(x,m)`. Stage two is a statically declared workflow over that context:

```text
g : Workflow<Ctx, fun c ->
      Σ y:N(root(c), mid(c), evidence(c)).
        Q(root(c), mid(c), evidence(c), y)>

then_keep : VerifiedFlow(I,M,P)
         -> Workflow<Ctx, fun c ->
              Σ y:N(root(c), mid(c), evidence(c)).
                Q(root(c), mid(c), evidence(c), y)>
         -> Workflow<I, fun x ->
              Σ m:M(x). Σ p:P(x,m). Σ y:N(x,m,p). Q(x,m,p,y)>
```

Its execution law is `f(x)=(m,p); g(pack(x,m,p))=(y,q); then_keep(f,g)(x)=(m,p,y,q)`. The research must determine whether to expose `then_keep`, derive it from `keep`/product operations plus a typed context-packing map, or use another static composition combinator. In all cases, prove the context indices/equality and evidence are preserved; the second stage receives original input and intermediate evidence without an untyped cast or hidden capture.

Required laws and proof boundaries:

- F* typechecking proves each local node meets its stated result family and contract.
- Composition, pairing, projection, lifting, and routing preserve endpoint types and compose proofs for every reachable input.
- Ghost proofs need not be serialized. Restored values must regain evidence from a proved decoder/checker or from a named, explicit trust assumption.
- An indexed codec has `encode : x:I -> O(x) -> Bytes` and `decode : x:I -> Bytes -> option (y:O(x) & P(x,y))`. Prove round-trip and decoder soundness for every `x`; round-trip alone says nothing about arbitrary external bytes.
- Durable operation requests and captures also need versioned codec round-trip/soundness laws; no native closure or implicit process-local capture may be needed to rebuild an operation.
- Define how dependent output schemas remain stable and addressable across runs and code versions.
- Prove extraction/runtime refinement or state assumptions; source-level F* proofs do not alone prove extracted OCaml behavior.

## 6. External operations and adapter interpretations

### 6.1 Typed declaration, binding, and protocol

An adapter is a capability-specific interpreter of typed operations and live resources, not an escape hatch or merely a decoder from one in-memory value to another. Its job may include acquiring a resource, enabling effectful work through it, collecting durable outputs, and recovering/reacquiring after interruption. For example, a CLI adapter can turn a typed source-file tree into a temporary workspace and process handle; a network adapter can establish a connection/session and issue requests; a database adapter can open a transaction or cursor over external state. These are operational capabilities with effects and lifetimes, not ordinary values that the workflow can assume are pure or permanently present.

Separate the pure operation declaration from the driver binding. In this notation `I` is the complete durable request context, including any operation capture and call input. If the API exposes capture `C` and input `I` separately, both need stable codecs and validation must be indexed by `(c,x)`; neither may be hidden in a closure. A candidate declaration is:

```text
Operation<I, Raw, O, P> = {
  operation_id, operation_version, request_schema, response_schema,
  encode_request : I -> Bytes,
  decode_request : Bytes -> option I,
  decode_response : Bytes -> option Raw,
  validate : x:I -> Raw -> option (y:O(x) & P(x,y)),
  encode_result : x:I -> y:O(x) -> Bytes,
  decode_result : x:I -> Bytes -> option (y:O(x) & P(x,y)),
  maximum_charge
}
```

Request codecs must round-trip and decode soundly, so recovery can reconstruct the exact typed request used by validation. `decode_result` must reconstruct the dependent value and proof (by checking encoded evidence where needed); a named trust assumption is required if it cannot. Distinguish raw backend response bytes from canonical validated-result bytes. Durable success stores the latter plus its artifact manifest and provenance; recovery decodes and re-establishes the contract before use. Invalid/failure diagnostics may store a response digest or bytes under a declared retention policy.

A binding supplies a stable `adapter_id` and version, immutable encoded configuration/fingerprint, and bounded protocol calls such as `prepare`, `start(key, request)`, `poll(token)`, and `reconcile(key, request_digest)`. A resource-capable protocol may further expose typed, scoped `acquire`, `use`, `collect`, `release`, and `recover` actions. The handle is abstract and live: an F* file handle, socket, session, transaction, or process handle must not be serialized as durable data. Instead, persist a logical resource description and protocol token, then reacquire or reconcile the resource on resume. The research must decide whether a resource-using node runs custom F* code against a scoped abstract capability or delegates its whole interaction to the adapter; it must support non-pure node behavior either way and specify effects, scope/lifetime, failure, and recovery. Persist stable operation/schema/adapter identities, configuration identity, canonical request bytes/digest, and durable protocol token; derive the idempotency key from the run/occurrence/attempt identity and immutable request identity. Never serialize native closures or process-local handles. After restore, resolve the pinned binding or report it unavailable.

External nodes are explicitly fallible. A candidate public result is a sum such as `Verified(y:O(x) & P(x,y)) | Rejected(diagnostic) | Failed(error) | Unknown(recovery_info)`. Malformed response bytes, validator rejection, process failure, and unresolved execution must not be coerced into `Verified`; the spec must define which diagnostics/raw data are durable and exposed.

Model protocol outcomes explicitly: `NotApplied`, `Accepted(token)`, `Pending(token)`, terminal success/failure, `Unknown`, and optionally `Cancelled`. The workflow persists a deadline or finite retry/poll budget before dispatch; define the clock/expiry assumption if wall time is used. Every adapter call must return or be interrupted by a watchdog within a stated bound; at expiry, reconciliation either establishes a terminal outcome or commits `Unknown`. `Unknown` is a durable quiescent checkpoint: automatic polling/dispatch for that attempt has stopped, its outcome/effect is unresolved, and its budget reservation remains held. Policy may request explicit reconciliation, cancellation, or escalation, but not a fresh dispatch while the outcome is unresolved. A new attempt is allowed only after authenticated `NotApplied` evidence settles the old attempt and releases its reservation, or through same-key idempotent redelivery that reconciles the original attempt and reuses its reservation without double charge. Reconciliation may append evidence and refine `Unknown` to a terminal outcome; it must not overwrite or erase prior history. Terminal success/failure/cancellation is absorbing. Do not require a remote backend to eventually respond in order to prove local progress. Under assumptions that the scheduler, watchdog, and store continue to make progress, every accepted attempt eventually reaches either a durable terminal outcome or durable quiescent `Unknown`. Claim eventual remote success only with an additional backend eventual-response assumption. Scheduler fairness for independent ready nodes is a separate theorem.

Adapter proof/assumption obligations:

- **Correlation and safety:** accepted statuses/results match the exact run, occurrence, attempt, operation and adapter versions, immutable configuration, and request digest. Stale/conflicting replies cannot overwrite terminal state.
- **Validation:** raw output is checked before downstream use. Semantic claims require a proved F* checker/certificate verifier or a named explicit trust assumption.
- **Effect recovery:** after a lost reply, retry cannot silently duplicate an effect. The adapter must deduplicate by a durable key, reconcile the prior outcome, prove definite non-application, or return `Unknown`. A local operation ID alone does not prove exactly-once execution.
- **Progress:** each call is bounded; unresolved work has a durable next step and cannot disappear or block unrelated ready work. Eventual completion is conditional as above, not unconditional.
- **Budget:** reserve the declared maximum before dispatch. Keep pending/unknown reservations. The budget theorem assumes the adapter/backend respects that maximum; `spent` is a kernel-accounted ledger guarantee, not proof of a remote provider's actual cost unless trusted, authenticated charge evidence is part of the contract. If reported charge exceeds reservation, persist an adapter/budget violation and stop normal success settlement; do not silently clamp it or claim the adapter contract held. Refund only with authenticated definite-nonapplication evidence.
- **Construction purity:** building a workflow, operation declaration, or binding causes no external effect.

### 6.2 Both authoring forms are required

These are two packaging forms of the same authoring model, not different APIs or trust levels. They should be as similar as practical: both use the same operation declaration, typed resource interface, codecs, driver contract, proof obligations, and recovery semantics. Inline authoring is a local instance of the same interface; library authoring packages that instance for reuse. Placement and reuse differ; meaning and guarantees do not.

1. **Inline:** an application declares the operation and binds its driver/configuration beside the workflow.
2. **Library:** a reusable package exports an operation constructor/version and driver binding (for example, JEV); an application imports and configures it without rewriting protocol logic.

Closures are not durable identifiers. A run records stable identities and encoded request/capture/configuration, and resume must resolve a compatible pinned implementation or fail visibly as unavailable. The acceptance suite should show that the same operation can be authored inline or imported from a library with equivalent types, effects, proofs, resource behavior, recovery, and budget contracts. Manifest equality is required only when their stable identities and effective configuration are equal.

## 7. Resources, blobs, and file interpretation

`BlobBytes` and `BlobTree` are **not primitives required in the workflow kernel**. They are domain types that particular adapters know how to interpret. A `BlobTree` can mean “relative file paths and bytes” to a CLI adapter; it need not mean the same thing to a network, database, model, or JEV adapter.

The workflow is not limited to pure transformations over raw values kept in memory. A typed file-tree request may be materialized as files that a process reads and writes. A typed network request may acquire a connection and session whose state changes across calls. A database operation may interact with a transaction, cursor, or durable remote state. Workflow nodes may need to perform effectful steps through such resources, and outputs may be newly collected files or externally maintained state rather than a simple returned byte string.

Research a general typed adapter/resource boundary that lets workflow code request and use these capabilities while preserving as much proof as possible. It must support file materialization now and leave room for network requests, model contexts, database state, and other live capabilities. Do not force every capability into a universal blob or untyped resource container. Distinguish durable logical descriptions/results from temporary paths, file descriptors, process IDs, sockets, sessions, transactions, and other reacquirable/live handles. Define separate acquisition/use, input materialization, output collection, release, and recovery contracts where applicable; a type accepted as input must not silently imply how a resource is created, used, gathered, or committed. State which effects a node may perform and what survives a crash.

The static-analysis case should be representable as:

```text
source files -> typed external analyzer operation -> raw report/artifacts
             -> F* parse/check node -> parsed or verified findings
```

The CLI adapter interprets the input file-tree type by safely materializing it in an isolated workspace, acquiring a process/workspace capability, invoking a pinned tool/configuration, collecting report bytes and declared output files, and persisting collected outputs before committing references. F* code may parse the report or perform further typed work; a verified checker or certificate establishes semantic soundness when available. A report without such evidence remains parsed-but-unverified. The same shape should generalize to a network adapter that acquires a session, performs a typed request, and returns a result plus any durable state needed to resume safely.

Formalize both materialization and collection as contracts such as:

```text
ValidTree(t) /\ Materialize(root,t)=Ok(paths)
  ==> confined(paths,root) /\ Read(paths)=t

Collect(root, output_contract)=Ok(t)
  ==> ValidTree(t)
      /\ dom(t) contains only allowed declared paths
      /\ for every p in dom(t), t[p] = bytes read from confined regular file p
```

The output contract distinguishes required and optional paths: missing required paths fail collection. Reject traversal, symlinks escaping the workspace, undeclared outputs, and path collisions. Collection preserves exact bytes for every returned path; state whether metadata such as permissions/timestamps is intentionally excluded. Identify which parts are F* theorems and which rely on OS/filesystem assumptions. On restore, rematerialize from durable bytes/content references or mark unavailable; never treat a saved temporary path as durable content. If blobs live outside the journal, persist bytes before references and use an atomic manifest/commit protocol that tolerates orphan staging files and repairs interrupted commits. A durable completion must not refer to missing bytes.

## 8. Durable execution and proof obligations

Treat the statements below as properties the design must make expressible and provable, not as a limit on acceptable proof effort. Agentic proof-oriented programming is expected to handle proof construction, including complicated induction, refinement, and model-to-runtime arguments. Do not simplify the system's guarantees because a proof is long. For each claim, settle its exact theorem, required assumptions, and boundary between proved code and trusted host behavior; proof complexity is not a tradeoff criterion.

Let `W` be a pinned workflow plan, `x` its immutable root input, `S` abstract durable state, `D` its committed encoding, `J` adapter history, and `Obs` the observations defined above. The model-to-runtime theorem quantifies over every well-typed `W`, input `x`, reachable valid state, finite execution trace, and crash cut—not only examples. Define the state needed to resume: persist control choices/expansions or prove they reconstruct deterministically from `x`, `W`, pinned schemas/code, and the journal. Process-local handles must be reacquired or become explicitly unavailable.

### 8.1 Completed work is not rerun

For every occurrence `k`, prove:

```text
Valid(S) /\ DurableSuccess(S,k,w)
  ==> Resume(S) never invokes k's local body or external effect again
      and consumes only the validated decode of w.
```

During restore, pure scheduler/control evaluation may be replayed to reconstruct readiness; that is distinct from re-invoking the completed node body/effect. Consumers read the stored, validated result. If a pure local output is not durably recorded, replay may recompute it and the no-rerun theorem does not apply to that node. A successful external process whose result was not durably committed is not yet complete: recovery reconciles or returns `Unknown`, never assumes success or blindly claims exactly-once behavior. Terminal failure/cancellation remains terminal; duplicate events cannot settle budget twice.

Define the linearization point for completion: validated output plus durable artifact references and terminal status become visible together. If the store cannot atomically commit all bytes/references/status, specify a staged, idempotent protocol and prove recovery for every intermediate state, including orphan bytes and missing references.

### 8.2 Recovery at every cut

Prove a resumption theorem for every cut around local evaluation, intent/event commit, dispatch, backend acceptance, external response, result validation, artifact collection/persistence, result commit, and downstream consumption. When adapter reconciliation/idempotency is established, require observational equivalence:

```text
Reachable(W,x,S0,trace) /\ CrashAt(cut)
/\ StorageContract /\ CodeCompatibility /\ AdapterContract
  ==> Obs(Resume(Recover(last_committed(cut)), same_future_backend_outcomes))
      ~= Obs(Uninterrupted(trace, same_future_backend_outcomes))
```

Define `~=` precisely: preserve completed values/contracts, ordered external effects, artifact bytes/provenance, locally accounted budget, and failure/unknown status; ignore internal stuttering and restart markers. Include process exit before result commit, lost reply, and blob write/result-commit ordering. Without adapter idempotency/reconciliation, state a weaker safety theorem: resume does not invent success or issue an unsafe duplicate, and may expose `Unknown`; do not claim effect-trace equivalence.

Prove progress separately. Under weak scheduler fairness, a continuously enabled ready node is eventually scheduled. Under bounded adapter calls, fair polling, and durable-store progress, each accepted operation eventually reaches a durable terminal outcome (`Succeeded`, `Failed`, `Cancelled`) or durable quiescent `Unknown` by its persisted expiry. `Unknown` may later be refined only through appended reconciliation evidence; automatic execution remains stopped. Progress does not assert remote success; that requires an explicit backend liveness assumption. If these assumptions fail, document the resulting stalled/unavailable state rather than claiming unconditional liveness.

### 8.3 State and budget invariants

Prove replay determinism and reducer preservation for operation identity/attempts, terminal monotonicity, accepted output validation, artifact lineage/materialization status, and budget accounting. Terminal success/failure/cancellation is absorbing; `Unknown` is quiescent and may only be refined by appended reconciliation evidence. At minimum:

```text
valid(S.budget)
/\ S.budget.reserved = sum(reservations of in-flight or Unknown attempts)
/\ S.budget.spent + S.budget.reserved <= S.budget.limit
```

Admission must reserve against the latest serialized state. Success settles actual charge only when it is within reservation. Define failure/cancellation settlement and require evidence for refunds. Route/resource decisions on resume use their persisted snapshot, not a recomputed mutable budget.

### 8.4 Adapter and host refinement

Prove that extracted adapter commands cannot bypass intent commit, response correlation, result validation, result encoding/decoding, or budget checks. State assumptions for atomic durable storage, pinned code/codec compatibility, adapter authenticity/availability, filesystem/process behavior, watchdogs, and fairness. Tests at selected crash cuts support but do not replace all-cut proofs.

## 9. Representative acceptance suite

Each case must run unchanged F* workflow code through extracted code and state which claims are proved, assumed, or tested.

| Case | Required behavior |
|---|---|
| Basic typed composition | Total local tasks, identity/projection, sequential composition, endpoint checks, and deterministic outputs. |
| Retain and project input | Reproduce `fan(it(State), attempts)`; use original state and attempts downstream; preserve ordered pair and nested projection behavior. |
| Dependent contracts | Standalone refinement and input-relative postcondition; compose two proof-bearing nodes through `then_keep` or its equivalent, passing original input/intermediate proof; encode/decode and re-establish evidence. Include rejection of invalid external result. |
| Real CLI static analysis | Local deterministic analyzer executable reads materialized nested files, emits report and output files; verify paths/content, parse result, distinguish verified/unverified findings, handle malformed output/nonzero exit. |
| Simple API operation | Deterministic in-process scripted transport; typed request/response, success, error/timeout, idempotency key, lost reply, and reconciliation. No network required. A loopback server is optional boundary coverage. |
| Deterministic event queue | Immediate/pending, reorder, duplicate/late, failure/cancel/unknown, deadline expiry; pending branch does not block independent ready work; ordered join and charge invariants hold. |
| Crash-cut matrix | Restart before dispatch, after intent, after adapter acceptance, after process exit/response but before result commit, after result commit but before consumption, and around artifact commit. Assert durable completed nodes never re-run. |
| Inline and library adapter | Bind an operation both ways; show the same laws and deterministic observations for equal identities/configuration. Also exercise a reusable JEV-like package with a scripted backend. |
| Blob output/rematerialization | Collect files as typed durable values, persist/reload, rematerialize, and return them; test traversal, collisions, interrupted writes, and unavailable references. |
| Budget boundaries | Competing admissions, exact limit, overcharge rejection, pending/unknown reservation, NotApplied-gated or same-key retry, terminal settlement, duplicate events, and evidence-backed refund. |

The deterministic queue is a model adapter and not evidence of OS process semantics. The CLI case exercises a real local boundary; it does not prove filesystem behavior without the corresponding refinement contract. Scripted transport exercises protocol logic, not a remote service.

## 10. Research deliverables and open decisions

The final research/implementation spec must:

1. Select and define the minimal work-node API and library surface for identity, fan-out, projection, and product retention.
2. Select output-family, postcondition, or combined dependent-contract representation and state exact composition signatures/laws.
3. Define the typed adapter interpreter, both required authoring forms, failure/unknown/reconcile behavior, budget interface, and progress assumptions.
4. Define which resource types live in libraries and their materialization/reacquisition contracts; do not make Blob types kernel primitives by default.
5. State formal semantics, theorem statements, explicit assumptions, counterexamples where guarantees are impossible, and the proof plan for model-to-extracted-runtime correspondence. Judge theorem feasibility and assumption quality, not proof length or complexity.
6. Give a staged implementation and proof plan. Implementation and execution of the acceptance suite follow resolution of these choices; they are outside this document revision.

Relevant historical evidence: [current problem specification](fstar_pulse_workflow_api_problem_spec.md), [typed-plan outline](fstar_typed_plan_workflow_api_outline.md), and [implementation report](fstar_typed_plan_workflow_api_report.md). The current prototype remains evidence for selected mechanisms, not proof that this successor API meets the obligations above.
