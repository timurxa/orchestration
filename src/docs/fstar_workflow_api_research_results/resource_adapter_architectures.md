# Resource adapter architectures for F* workflows

**Scope.** Compare typed boundaries for effectful operations over files/workspaces/processes, network sessions, and database transactions/cursors. Focus: resource lifecycle across crashes, unknown outcomes, artifacts, budget, proof boundary, inline/library symmetry. No implementation or tests performed.

## Findings and labels

- **Observed:** `WorkflowCore.workflow.evaluate` is pure `Tot` and returns `evaluation` containing value/actions/failure/blocking (`src/fstar/v0/WorkflowCore.fst:423-461`). `external` encodes capture and input, creates a durable `Prepared` intent, reserves maximum charge, then asks scheduler to dispatch or reconcile (`:945-1020`). It has no acquire/use/collect or live handle API.
- **Observed:** status model includes `Prepared`, `Pending`, `Unknown`, `Succeeded wire charge`, `Failed`, `Cancelled`, `NotApplied` (`:318-325`). `recover_after_process_loss` changes in-flight statuses to unknown (`:829-839`); accepted transitions retain reservations for pending/unknown (`:718-762`).
- **Observed:** artifact model includes `BlobTree`, `MaterializedFile`, and `LiveCapability`, yet `valid_artifact` rejects `MaterializedFile` and `LiveCapability` as durable artifact contents (`:361-379`, `:654-668`). Thus tags do not implement resource lifecycle.
- **Observed:** examples exercise arithmetic workflows and fake external statuses (`WorkflowExamples.fst:14-41,51-113`). OCaml runner selects scripted `Immediate`, `Deferred_reverse`, `Scripted_faults` responses, not real OS/network/DB adapters (`Runner.ml:141-151,216-285`).
- **Observed:** `BlobTree` validation already encodes scalar validity, byte bounds, and prefix collision rejection (`WorkflowCore.fst:74-188`). It does not prove host filesystem confinement, symlink behavior, file identity, or crash-atomic artifact persistence.
- **Derived:** current kernel's external node is a durable command boundary, not yet a typed resource boundary. Need resource lifecycle as a protocol whose durable state consists of logical descriptions, tokens, outcomes, and artifact references; host handles stay ephemeral.
- **External basis:** F* supports user-defined indexed effects and effect abstractions with specifications/proof rules; effects cover state, I/O, concurrency, and other behaviors. This makes a scoped capability interface plausible, but does not itself establish extracted OCaml/OS semantics. [F* effects tutorial](https://fstar-lang.org/tutorial/book/part4/part4.html), [indexed-effects paper](https://fstar-lang.org/papers/indexedeffects/indexedeffects.pdf). Pulse/Steel demonstrate effectful, dependently typed programs with separation logic and protocol-indexed resources; these are design precedents, not proof that this workflow runtime gets those guarantees for free. [SteelCore paper](https://arxiv.org/abs/2111.15149).

## Three mechanisms

Notation is semantic sketch, not compile-tested F*. `Desc`, `Token`, `Evidence`, and `Artifact` are adapter-specific types with versioned codecs. A resource handle is opaque, non-serializable, and only in scope during callback.

### A. Adapter owns whole operation

Workflow describes immutable request; adapter acquires resources, performs all actions, collects artifacts, validates transport envelope, and returns bytes/status.

```text
Op<I, O, P> = {
  id, version, request_codec, result_codec, maximum_charge,
  validate : x:I -> Raw -> option (y:O(x) & P(x,y))
}
Driver<Op> = {
  start : Key -> Encoded(I) -> IO (Accepted Token | NotApplied Evidence | Unknown),
  reconcile : Key -> Digest -> Token option -> IO Outcome,
  cancel : Key -> Token -> IO Outcome
}
```

`start` is whole protocol: materialize/acquire/use/collect/release; the exact substeps may be adapter-internal but must be reflected in its contract and provenance. Good fit for CLI analyzer and existing `external`/JEV-style provider. Easy durable boundary, weakest F* visibility into resource use.

### B. Scoped abstract capability for F* node

F* node owns algorithm; adapter provides scoped operations. The rank-2 shape prevents handle escape in typed client API; resource-specific effect indices encode state transitions. Host still enforces actual scope.

```text
with_resource : Desc<R> ->
  (forall h. Capability<R,h,Opened> -> Eff<Cap(R,h), a, post>) ->
  Eff<Host, a, post'>

Capability<R,h,s>  // opaque, cannot encode/decode
read/write : Capability<Workspace,h,s> -> ... -> Eff<Cap,...>
send/recv  : Capability<Session,h,s> -> ... -> Eff<Cap,...>
query/next/commit : Capability<Txn,h,s> -> ... -> Eff<Cap,...>
```

`post` should relate operation trace and final resource state. To cross a crash boundary, node emits durable checkpoints/events; restore reacquires from `Desc` plus token and resumes only at proved checkpoint. Handles cannot be retained in closures or workflow values. This offers strongest local reasoning, but node effects must be restricted to adapter-mediated calls; arbitrary `IO` breaks trace accounting and replay proof.

### C. Hybrid protocol (candidate)

Workflow supplies statically declared typed operation plus a small effect program over a resource-specific interface; adapter owns acquisition, raw transport and resource implementation; kernel journals each externally visible effect step and durable checkpoints. Reusable library exports the same operation descriptor, effect program constructor, codecs, and driver contract as inline authoring.

```text
ResourceOp<I, R, O, P> = {
  operation: Op<I,O,P>, resource_schema, config_codec,
  program : (x:I) -> CapProgram<R, x, O(x), P(x)>,
  collect : Session<R> -> OutputContract -> Eff (Collected & Provenance),
  recover : LogicalDesc -> Token option -> Journal -> IO Recovery
}

CapProgram<R,x,Y,P> = typed sequence of
  Acquire Desc | Materialize Input | Invoke Request | Read/Write/Query |
  Collect Contract | Release | Checkpoint | Return Y
```

Program's operation vocabulary is closed and typed per resource family, not universal `Blob` or erased `Resource`. Program builder is pure and serializable by stable operation IDs + typed input; driver binding resolves IDs at runtime. For code needing arbitrary F* computation between effects, compile typed F* node to protocol calls, but persist call boundary and input/output schemas. The driver never receives native F* closures.

**Derived:** hybrid preserves F* proofs about local parsing/routing and protocol sequencing while adapting host-specific acquisition. It allows library code to own a reusable protocol without forcing entire business algorithm into host-language adapter. It has more kernel/protocol machinery than A, less raw capability expressiveness than B.

## Worked forms

### Static analysis over files

Shared shape:

```text
SourceTree -- AnalyzerOp --> RawReport + collected output tree
RawReport -- parse_report --> ParsedFindings
ParsedFindings -- checker(certificate) --> VerifiedFindings
```

`AnalyzerOp` has versioned `BlobTree` request codec, tool image/binary digest, argv/config identity, max budget, required `report.json`, optional declared `sarif.json`/output paths, and result manifest codec. Adapter materializes only validated relative paths into isolated workspace; starts pinned analyzer; captures stdout/stderr under retention cap; collects only declared regular files; hashes bytes; persists bytes before artifact references; commits validated result, artifact manifest, terminal status atomically. `parse_report` is pure typed F*; parser proves syntax/shape only. Checker verifies analyzer proof/certificate or recomputes property. Without certificate/checker, output remains `ParsedFindings`, not semantically verified.

- **A:** one adapter `analyze(tree,config)` does entire lifecycle; easiest for command tools. F* validates report and proves subsequent checker.
- **B:** F* node uses `Workspace h`; can select files/run stages/read report with fine proof contracts. OS process and files still trusted at foreign-function boundary; crash needs checkpoint mapping for every external process step.
- **C:** workflow declares `Materialize`, `Run(tool,args)`, `Collect(contract)` steps; F* pure checker follows. Driver implements workspace/process actions; journal shows durable progression, no serialized path/FD/PID.

Contracts: `ValidTree(t) / Materialize(root,t)=Ok(paths) => confined(paths,root) /\ Read(paths)=t`. For collection, every returned path is allowed, required paths exist, bytes equal exact read bytes, no symlink escape or path collision. These are **host/adapter assumptions or refinement theorems**, not consequences of F* path-list validity. Specify metadata exclusion (suggest exclude permissions/timestamps; record executable bit only if input contract needs it).

### Network session

Example: submit idempotent `PUT /jobs/{key}` then poll/read result. `SessionDesc` contains endpoint identity, TLS policy/config version, secret reference identity (not secret bytes in manifest), and protocol version. Adapter `acquire` returns opaque socket/session plus renewable logical token. Calls carry `(run, occurrence, attempt, operation_version, request_digest, key)`; response authenticity binds same tuple. Persist `Accepted(token)` before waiting. Crash after send-before-reply requires `reconcile(key,digest)` or same-key redelivery; if server cannot prove prior result or no effect, return durable `Unknown`, hold reservation, forbid fresh key/attempt. A transient TCP success is not proof of remote application. Artifacts include canonical response, server receipt, and any downloaded bytes with provenance.

### Database transaction/cursor

Example: query snapshot, stream rows, write derived rows, commit. `DbDesc` pins DB identity, schema epoch, isolation level, query hash, parameter digest, cursor strategy. Scoped capability can represent `Txn<Open>` then `Txn<Committed>`/`Aborted`; cursor token represents snapshot and position. If DB supports durable snapshot/cursor and idempotency key, journal cursor checkpoints and resume same snapshot. Otherwise cannot promise same rows after reconnect; either collect/materialize complete row artifact before declaring operation complete or mark resume unavailable/unknown. Commit reply lost is classic unknown outcome: reconcile transaction ID/commit record; never issue second non-idempotent transaction on assumption of rollback. For atomic DB plus workflow journal, absent distributed transaction, use outbox/inbox/idempotency protocol or weaken cross-system atomicity to `Unknown` reconciliation.

## Lifecycle and trace laws

Let `K=(run,occurrence,attempt,operation_version,config_fingerprint,request_digest)`. `J` journal, `R` ephemeral resources, `A` durable artifacts. `Obs` includes result/proof status, ordered external effects, exact artifact bytes/provenance, budget, failure/unknown. Scheduler and restore stuttering may be ignored; liveness separate.

1. **No handle persistence:** `encode(J)` contains no socket, FD, PID, transaction object, temp path treated as content, or closure. It may contain logical `Desc`, adapter token, object IDs, hashes, durable references.
2. **Scope:** every use is dominated by successful acquire; every normal exit releases or records why cleanup is pending. Resource failure does not erase prior effect evidence. Crash may skip release; restore reacquires/cleans or reports unavailable.
3. **Correlation:** every accepted event equals K and exact request digest; stale/conflicting messages cannot rewrite terminal state.
4. **No blind retry:** repeat `start(K)` means deduplicated redelivery of same attempt, never a new effect. New attempt only after authenticated `NotApplied` releases reservation or explicit policy accepts unresolved risk (then no exactly-once theorem).
5. **Unknown is absorbing for dispatch:** unknown is durable quiescent checkpoint, retains reservation, stops automatic dispatch/poll at deadline; reconciliation may append evidence/refine unknown. It cannot become a new attempt without definite-nonapplication evidence.
6. **Terminal:** success/failure/cancel is absorbing; duplicate event cannot settle budget twice. Durable success linearizes only after validated result + artifact bytes/references + terminal status visible atomically (or recoverable staged protocol).
7. **Recovery equivalence:** for every cut and same future backend outcomes, if storage, code compatibility, adapter contract hold, `Obs(Resume(Recover(last_commit(cut)))) ~= Obs(Uninterrupted)`. If remote effect outcome unresolved, equivalence includes same `Unknown`/effect evidence, not fabricated success.
8. **Progress:** bounded calls/watchdogs + fair local scheduler ensure accepted attempt reaches terminal or durable unknown; no assumption of remote eventual success. Independent ready work remains schedulable despite one unknown.
9. **Budget:** reserve max before first dispatch; keep reservation through pending/unknown; settle exactly once from authenticated charge `<= max`, or flag contract breach. Kernel proves ledger bound only. Actual remote spend bound assumes truthful/complete billing evidence and adapter honoring max. Release only with authenticated no-effect evidence.
10. **Artifact integrity:** bytes durable before references. Recovery repairs orphan staging bytes; no completion references missing/corrupt bytes. `Collect` output must satisfy declared required/optional path contract, exact-byte provenance, confinement.
11. **Proof boundary:** F* proves typed local code, protocol-state transitions, validator soundness, and composition under abstract adapter contract. Host extraction/refinement, filesystem confinement, tool behavior, remote deduplication/receipt authenticity, DB isolation, storage fsync/atomicity, and budget reports remain explicit assumptions unless independently verified. F* source proof alone cannot prove these.
12. **Construction purity:** descriptor/program/config construction emits no effects. Inline and library forms instantiate same interface; packaging changes module location only. Equivalence: equal stable IDs/versions, codecs, config bytes, code digest, protocol assumptions imply same traces and guarantees. Closure identity is forbidden.

## Comparison matrix

| Criterion | A: whole operation adapter | B: scoped capability in node | C: hybrid typed effect protocol |
|---|---|---|---|
| Resource acquisition/use | Entirely adapter internal | F* code calls scoped ops | Driver acquires; typed program requests actions |
| F* proof visibility | Request/result validator only | Highest, per-step pre/post and invariants | Protocol order + local code visible; OS action internals abstract |
| Crash recovery | Coarse token/reconcile; adapter must recover all substeps | Fine checkpoint possible; difficult if arbitrary effects | Journaled steps/checkpoints + adapter reacquisition |
| Unknown outcomes | Natural whole-op status | Must model per effect call and propagated uncertainty | Explicit per-call and operation status |
| Artifact collection | Adapter owns; simple manifest | Node can reason over typed collected values | Typed `Collect` contract and staged manifest |
| Budget | One max per op, coarse usage | Per call possible; accounting burden | Per op or per declared action, ledgered |
| Reusable library | Natural driver package | Capability interface library; implementation F* | Operation + program + binding package, inline same instance |
| Kernel size | Small | Effect/runtime/resource machinery large | Medium; typed protocol interpreter needed |
| Main failure mode | Opaque adapter hides semantics | Raw IO escapes, handles/lifetimes/cuts explode | Protocol becomes bloated or too low-level |
| Best use | Existing external provider/JEV, atomic service call | Purely local stateful algorithm over modeled resource | General workflow with reusable effectful tool/database/network nodes |

## Recommendation (decision candidate, not settled)

Adopt **C as the general resource interface**, retain **A as a derived single-step adapter** when operation can honestly be atomic from workflow perspective, and permit **B only behind a closed typed capability effect** whose host calls are journaled and whose handle cannot escape. This is a hybrid of formulations, not three different trust tiers: all use same `ResourceOp` declaration, codec, driver contract, validator, key, budget, trace laws, and packaging form. Inline is local module implementing `ResourceOp`; library exports same value/interface. Adapter may interpret full typed program or individual typed calls, with semantic meaning unchanged.

Keep kernel minimal: durable operation identity/input/status/artifact references/budget plus scheduler actions. Resource-specific `Workspace`, `Session`, `Txn`, cursor operations live in typed libraries, not a universal untyped handle. Kernel need not understand BlobTree beyond codec/manifest integrity.

## Strongest objection

Hybrid adds protocol semantics and hidden host boundary without fully eliminating adapter trust. Its closed effect language could become a second workflow DSL: too low-level for ergonomic F* and too expressive to verify uniformly. Per-step journaling does not make a multi-system effect atomic; DB commit/network send can happen before journal acknowledgement, forcing unknown outcomes anyway. If most operations are naturally one service call, A has smaller surface and same honest `Unknown` guarantees. Counterargument is reuse/compositional local proof: static analysis, network exchange, and cursor processing need shared typed sequencing/artifact contracts. **Resolution remains empirical/design question:** specify only three or four generic lifecycle actions (`Acquire`, `Use`, `Collect`, `Release`) and allow typed resource-specific `Use` programs; compare against whole-operation packaging on examples before freezing kernel.

## Assumptions and unresolved questions

**Assumptions:** durable store provides atomic event append or recoverable idempotent staged commit; adapter IDs/config are pinned; key collision resistance or injective identity is adequate; remote adapter can report evidence with authenticated correlation; watchdog can bound local adapter calls; output storage preserves content addressed by digest.

**Unresolved:**

1. Is logical resource description sufficient for reacquisition, or must API support explicit adapter `recover` with capability-specific state proof?
2. Can resource program be serializable typed AST, or should stable code ID + version resolve implementation and journal only inputs/outputs? Which permits code upgrade proof?
3. Do we journal every call or only externally visible effect/checkpoint? Define trace equivalence for speculative reads and idempotent polls.
4. Is transaction/cursor progress represented by durable remote token, exported checkpoint artifact, or single adapter operation? What if DB lacks repeatable snapshot?
5. What exact artifact store contract covers bytes, manifests, hashes, corruption, and atomicity with SQLite journal?
6. Are budgets operation-wide max, per protocol action, or both? How authenticate delayed/revised billing?
7. How expose cleanup failure after primary result is durable without changing terminal success semantics?
8. How pin secret/config identity without storing secret or making resume unusable after secret rotation?
9. Which F* effect/Pulse/Steel subset supports extracted OCaml runner and proof refinement; what foreign-call axioms are unavoidable?

## Provenance and source locations

### Repository observations

- `src/docs/fstar_workflow_api_next_research_spec_draft.md:6-17`: proof complexity not a reason to weaken; requirements include durable completion, restoration, adapter contracts.
- `...draft.md:55-98`: pure operation declaration, binding, status protocol, unknown/budget, adapter obligations.
- `...draft.md:100-115`: inline/library are same interface and semantics.
- `...draft.md:117-146`: live resources, BlobTree adapter interpretation, materialization/collection contracts.
- `src/fstar/v0/WorkflowCore.fst:318-379`: statuses, operation records, artifact tags.
- `...WorkflowCore.fst:423-499`: pure workflow evaluator, `then_flow`, `fork`.
- `...WorkflowCore.fst:654-668`: current artifact validation and explicit rejection of materialized/live capability records.
- `...WorkflowCore.fst:718-762,829-839,945-1020`: reducer transition/budget handling, process-loss recovery, external intent.
- `src/fstar/v0/WorkflowExamples.fst:14-41,51-113`: total pure local code and simulated external operations.
- `src/fstar/v0/Runner.ml:141-151,216-285`: fake adapter outcomes and runner lifecycle.

### Primary external references

- F* official tutorial, “Computational Effects”: user-defined effects model state/I/O/concurrency and encapsulate semantics/reasoning: https://fstar-lang.org/tutorial/book/part4/part4.html
- F* official tutorial, “A First Model of Computational Effects”: monadic bind and effectful composition model state transitions; effect abstraction separates semantic model from efficient implementation: https://fstar-lang.org/tutorial/book/part2/part2_par.html
- Ahman et al., “Programming and Proving with Indexed Effects”: indexed effects/Dijkstra monads for stateful specifications and effectful program proof: https://fstar-lang.org/papers/indexedeffects/indexedeffects.pdf
- Swamy et al., “SteelCore: An Extensible Concurrent Separation Logic for Effectful Dependently Typed Programs”: protocol-indexed resources and verified effectful code precedent: https://arxiv.org/abs/2111.15149

## Proposed next investigation

Construct one compact typed protocol model for `Workspace`, `HTTPSession`, and `DbTxn` with identical `ResourceOp` surface; formally enumerate crash cuts around acquire, effect, collect, result commit. Compare (i) one whole adapter operation, (ii) typed lifecycle AST, and (iii) arbitrary F* scoped effect calls for expressibility, number of trust assumptions, and no-rerun/recovery theorem. Audit actual extraction path plus filesystem/artifact atomicity. Then have non-author review specifically attack unknown-after-send, cursor snapshot, and artifact-before-reference cases. Do not implement until comparison finds smallest truthful interface.
