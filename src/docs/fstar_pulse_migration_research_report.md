# F*/Pulse orchestration reimplementation: research synthesis

**Research status:** The kernel research pass and local prototypes are complete. Evidence supports a provisional architecture, while concrete implementation decisions remain open around durable callback identity, external-operation recovery, and a canonical stateful Pulse/OCaml build path. The indexed-plan probe typechecked and extracted code, but did not produce a runnable executable.

**Scope:** Reimplement the orchestration API in this repository. The workflow description must remain separate from execution, support ordinary user logic, keep the scheduler free while model operations are pending, resume from durable state, and expose a provider-neutral interface. Reimplement the orchestration-side Codex client; do not reimplement the Codex Rust app-server.

## Recommendation

Use a typed workflow plan as the durable contract, with a pure F*/Pulse transition function interpreting plan state and durable events into explicit commands. Allow an ergonomic higher-order F*/Pulse authoring layer, provided it lowers into a versioned, serializable plan before effects are dispatched. Persist dynamic expansion decisions before running children. Store code identity and encoded captures for code that must be replayed; do not treat a native closure as a durable identity.

This combines the strongest findings across the indexed/free-plan, dataflow, and event-state-machine work. It preserves ordinary typed computation while giving persistence and proof obligations a finite object to reason about. A direct effect-handler or higher-order API can remain an authoring front end when its continuation can be eliminated or reified into that plan. A plain workflow callback that performs arbitrary I/O during plan construction would make inertness, replay, and crash recovery difficult to prove.

Use Pulse for imperative stateful runtime code, with F* types and pure functions for typed workflow descriptions and helper computations where appropriate. The F* feature probe confirms that higher-order functions and a Pulse stateful sample can be verified and extracted. The local canonical stateful OCaml support-module build remains unresolved: the indexed-plan and Pulse outputs were generated, but compilation/linking stopped at missing F* runtime modules, so the execution target remains provisional.

This is an architecture direction, not a claim that the system is already proved correct. The combined authoring, lowering, checkpoint, and resume path has not yet been implemented or verified. The prototype below resolves basic type expressibility, but not durable closure encoding, changed-binary resume, or execution of extracted stateful code.

The project priority is to design a correct system and make proof obligations meaningful and tied to actual guarantees. Implementation difficulty is a secondary constraint for this experiment in agentic proof-oriented programming; it should not be used to weaken a needed correctness property.

## What the existing API does

The current API exposes typed flows with input and output types. Compile-time Nim machinery inspects and lowers the authoring syntax into runtime flow nodes. The important distinction is between constructing a workflow and dispatching an external model request:

- Composition, fanout, projection, lifted mapping, dynamic callbacks, and model declarations lower to graph-like runtime nodes. See [the compile-time lowering code](../api/vecherinka_comptime.nim), especially lower_flow_expr, lower_fanout, lower_it, lower_lift, lower_so, lower_model_call, and make_vecherinka.
- A model declaration does not itself call the model. Runtime dispatch occurs later through suspend_model and dispatch_model_requests in [the runtime](../api/vecherinka_runtime.nim).
- The workflow is not a fully static durable plan today. Runtime Flow values can contain executable callbacks. Raw expressions are evaluated while flows are rebuilt, and so callbacks run inline to construct dynamic expansions. Resume rebuilds those expansions from saved input and budget data.
- Model requests can be pending while the runtime handles other work, but the public solve and resume calls wait synchronously for the overall workflow result. Inline so and custom transport callbacks can block the coordinator. The scheduler therefore needs a durable poll/event interface even if a synchronous convenience wrapper is retained.
- SQLite stores artifacts, dependency relationships, operation attempts, workflow expansions, and checkpoints. Resume reloads saved state. A submitted external attempt with no persisted result becomes Unknown and may be resubmitted. Local correlation IDs do not establish remote idempotency.
- The source proof ledger identified a concrete budget contract mismatch: admission enforces the global remaining limit but treats per-pool capacity as soft, while checkpoint validation rejects a negative pool remainder or spend above recalculated capacity. With total budget 10, two equal pools, and a 9.66 charge in one pool, global admission succeeds but a later checkpoint of the budget snapshot is rejected. This is a source-derived path, not a reproduced workflow failure. The arithmetic uses float64, so an exact real-number invariant also needs a bounded/fixed-point representation or a justified consistency relation.
- The current workflow identity relies on normalized source representation, positional flow keys, and artifact type keys; runtime metadata adds prompt templates and model-pool data. Helper-code identity and build/runtime environment are not fully represented. The text normalizer can also rewrite generated-looking numeric suffixes inside string literals. Resume compatibility needs a new explicit versioning contract.

The source inventory is provisional and still has coverage gaps around low-level Flow construction, init_work_plan, invocation handling, actual it examples, and several error paths. The full inventory and source citations are in the [API semantics report](/Users/alex/areas/temp/fstar-pulse-research/api_semantics_inventory.md), [resume compatibility report](/Users/alex/areas/temp/fstar-pulse-research/resume_compatibility.md), and [crash recovery report](/Users/alex/areas/temp/fstar-pulse-research/crash_recovery_correctness.md).

## F*/Pulse authoring and metaprogramming

### Meta-F* is not required for a first design

Ordinary typed F* definitions can construct workflow values, and an interpreter can consume them. The feasibility evidence supports higher-order function arguments and results, captured closures, Pulse higher-order functions, recursion, and a stateful Pulse example. That makes an F* library DSL plausible without adding Meta-F* or a compiler extension.

A source-level declaration can look like a typed plan value, while arbitrary user helpers remain ordinary F*/Pulse functions:

~~~text
val plan : Plan<Input, Output>
val normalize : Input -> Tot<Normalized>
val choose_route : Normalized -> Budget -> Tot<RouteDecision>
val step : DurableState -> Event -> Tot<(DurableState * list<Command>)>
~~~

This is a design sketch, not checked F* syntax. The feature probe checks language constructs, not a complete workflow API.

### Higher-order authoring and durable representation

Higher-order functions can express useful user code and shape-preserving traversal. A proposed indexed Traverse over Id, Seq, Option, and nested shapes changes the element type while preserving container structure; for example, Seq<Option<A>> maps to Seq<Option<B>>. It generalizes the current lift behavior. This proposal remains pseudocode, not a compiled Pulse encoding.

Closures are useful during authoring but are not stable serialized values. A durable workflow needs one of these explicit boundaries:

1. Evaluate a pure builder once, store its resolved plan and route decision, and resume from the stored data.
2. Store a stable CodeRef, version, and encoded captures, then re-run a proven-pure builder under the matching implementation.
3. Restrict callbacks crossing a checkpoint to registered operations with declared codecs and effect contracts.

If a pure calculation is proven observationally lossless, it can be recomputed even when that wastes CPU. The equivalence relation must cover artifacts, errors, budget consumption, scheduling order where observable, external commands, and conversation history—not only the returned value. Code version, captures, environment, and codec behavior must match.

For dynamic expansion, persist the exact decision and canonical child plan before any child operation starts. The current so replay path checks a flow-key set and sometimes a graph signature; the signature omits raw node values, and older rows may be absent. The current determinism convention is not a proof of purity.

### Arbitrary code and effects

The F*/Pulse subset can express arbitrary computation within its verified language and effect model. A correct durable workflow should classify user code by behavior:

- Pure total functions transform typed values and can be recomputed under a validated identity.
- Pulse computations may use local mutable state within one scheduled transition or interpreter operation, subject to the Pulse ownership and extraction boundary.
- External I/O, model calls, process execution, filesystem mutation, and other irreversible operations are explicit workflow commands with durable identities and outcomes.

This lets a user write substantial ordinary code in F*/Pulse while making external effects visible to the runtime and proof model. An unrestricted callback that performs hidden I/O cannot safely be treated as a pure replayable workflow description.

## Formalisms considered

The reports compare or explore indexed/free plans, algebraic effects and handlers, applicative/selective/arrow composition, typed DAG/dataflow, event-sourced state machines, higher-order indexed traversal, session types, and saga compensation. Each solves a different part of the problem.

| Formalism | Useful role | Main limitation for this API |
|---|---|---|
| Indexed/free typed plan | Typed composition, fanout, explicit nodes, durable schema, exhaustive interpreter | Higher-order code and dynamic branches need explicit code identities, data codecs, or persisted decisions |
| Algebraic effects and handlers | Natural user-facing syntax for model calls and other operations; handlers can target a test interpreter or runtime | A handler that executes immediately breaks inert description semantics; suspended continuations are closures unless reified or lowered |
| Applicative / arrows | Fixed composition and parallel structure with clear input/output types | Result-dependent open-ended graph creation requires bind-like power; finite Selective choice does not replace arbitrary dynamic expansion |
| Typed DAG / dataflow | Dependencies, pure parallel work, joins, and recomputation from known artifacts | Does not by itself specify pending external calls, budgets, retries, Unknown outcomes, or crash recovery |
| Event-sourced state machine | Durable transitions, operation attempts, budgets, expansion decisions, cancellation, resume | Lower-level authoring model; needs a typed plan or combinator layer for usability |
| Session types / typestate | Local Codex protocol order and identifier correlation | Cannot prove the remote server accepted, persisted, or deduplicated an operation |
| Saga / compensation | Explicit inverse operations for effects with a real compensator | Compensation is not rollback; it cannot undo model history, charges, or an ambiguous external operation |

The most promising split is a typed plan for authoring and static structure, a dataflow/DAG for pure dependencies, and an event-state-machine interpreter for durable effects and recovery. Effect handlers may be a convenient authoring notation if they compile to that representation. The construct matrix compares this mapping against current API constructs; its recommendations remain design hypotheses rather than a completed API implementation.

The detailed comparisons are in [free plan versus effect handlers](/Users/alex/areas/temp/fstar-pulse-research/free_plan_vs_effects.md), [arrows versus monadic workflows](/Users/alex/areas/temp/fstar-pulse-research/arrows_vs_monadic_workflows.md), [dataflow versus event sourcing](/Users/alex/areas/temp/fstar-pulse-research/dataflow_vs_event_sourced_workflow.md), [higher-order plan boundaries](/Users/alex/areas/temp/fstar-pulse-research/higher_order_plan_boundary.md), and [dynamic expansion](/Users/alex/areas/temp/fstar-pulse-research/workflow_formalism_comparison.md).

## Runtime and durable operation model

A candidate core separates typed workflow description from execution:

1. A typed plan declares pure transformations, dependencies, model operations, generated-code stages, and route choices.
2. Lowering assigns stable node and operation identities and encodes all data needed by the runtime.
3. A pure transition function consumes one durable event and returns updated state plus commands. Commands are submitted by adapters; responses return as new events.
4. The scheduler persists operation intent before submission and records submitted, output-received, committed, failed, cancelled, or Unknown transitions.
5. The runtime commits artifact, lineage, cursor, and checkpoint changes atomically where they belong to one local transition.
6. A pending model call does not block the scheduler. The caller can poll, await, or use a synchronous wrapper without changing the scheduler semantics.

An operation identity must remain separate from an attempt identity and from backend-specific JSON-RPC, thread, turn, and tool-call IDs. A stable local ID is needed for audit and correlation; only an adapter contract can establish backend idempotency or reconciliation.

The durable request sequence should be explicit: persist Prepared with the operation ID, request digest, node occurrence, fan slot, budget admission, and continuation/cursor; persist Submitted before calling the adapter; receive a pending handle or response; validate and materialize the result; then commit the artifact, lineage, completed attempt, slot result, and advanced checkpoint together. If acceptance may have happened but the local commit did not, restore Unknown. Keep committed sibling results available while an unresolved sibling remains Unknown. Resume may reconcile or reattach through an adapter capability; an automatic retry requires a recorded at-least-once policy when the adapter cannot prove non-acceptance. The [construct matrix](/Users/alex/areas/temp/fstar-pulse-research/formalism_construct_map.md) treats this as a shared protocol across every formalism.

An Unknown outcome is required whenever submission or result delivery may have crossed a process boundary. A received interrupt response does not establish terminal turn completion. A process that exited before output capture and commit also has an uncertain durable result. Retrying an Unknown external operation is safe only with authoritative reconciliation, receiver-side idempotency, definite non-acceptance, or an explicit at-least-once policy.

For generated code, represent compilation and execution as explicit typed stages. A C source artifact can carry its requested interface and validation requirements; a Build node records source digest, compiler/toolchain identity, flags, and environment; a Run node records executable digest, sandbox policy, inputs, captured output, exit status, timeout, and truncation. Types can prevent a downstream node from consuming an artifact before the required validations. Compilation and type checking do not prove the generated executable safe. Process execution requires a runner contract and its own Unknown/recovery semantics.

The existing API provides Blob and BlobTree data and model output validation but does not expose a durable process effect node. The [artifact/process report](/Users/alex/areas/temp/fstar-pulse-research/typed_artifact_process_boundary.md) and [generated-code report](/Users/alex/areas/temp/fstar-pulse-research/typed_artifacts_generated_code.md) describe the proposed boundary and its unresolved output-capture crash case.

## Codex and backend-neutral LLM interface

The workflow API should describe model operations independently of Codex. A candidate typed operation carries instruction or prompt identity, input and output schemas, optional typed context/history, requested capabilities, and a stable logical operation ID. An adapter declares capabilities for structured output, tools, cancellation, history, idempotency, and reconciliation. JEV-like state-to-decision exchanges can be represented by typed input/context and typed decision output; long-running conversation history may be a separate artifact or backend session record.

The orchestration-side Codex client remains in scope. Reimplement protocol framing, request construction, response validation, event reduction, process lifecycle, and operation reconciliation. Keep the Codex Rust app-server as an external component.

Codex's optional clientUserMessageId is useful for correlating a submitted user message to an item when the item is present in queried history. The reviewed v0.160.1 contract does not establish that this value deduplicates operations or proves acceptance after a history miss. The current wrapper launches the app-server through PATH, does not expose typed thread/read or thread/resume support, and correlates JSON-RPC replies through in-memory request IDs. Restoring transcript history does not restore an in-flight request. Treat backend continuity as a declared capability.

See the [backend-neutral interface report](/Users/alex/areas/temp/fstar-pulse-research/backend_neutral_llm_interface.md), [session type report](/Users/alex/areas/temp/fstar-pulse-research/session_types_for_codex_client.md), [Codex client lifecycle report](/Users/alex/areas/temp/fstar-pulse-research/codex_client_lifecycle.md), [message-ID recovery report](/Users/alex/areas/temp/fstar-pulse-research/codex_message_id_recovery.md), and [protocol source report](/Users/alex/areas/temp/fstar-pulse-research/codex_protocol_primary_sources.md).

## Proof obligations and trust boundaries

Machine-checked F* proofs can establish properties of the modeled plan and transition function: type-safe composition, legal state transitions, stable identity relationships, correct local budget updates, checkpoint validation, artifact lineage, and that the reducer emits commands only in valid states. Pulse can help express and verify mutable implementation steps under its ownership/effect discipline.

The proof claim must account for extraction and runtime assumptions. The feature probe shows that refinements and ghost permission data do not appear in extracted OCaml in the same form as source proof terms. A proof of the F* model does not alone establish that the OCaml runtime, SQLite driver, filesystem, operating system, Codex app-server, model service, compiler, or generated executable behaves correctly. Liveness depends on scheduling fairness, process availability, provider response, and termination of user code.

Local SQLite transactions can make a local state transition atomic under the configured storage assumptions. They cannot atomically commit with a remote provider. A message accepted remotely before local result commit can be repeated after resume. Use Unknown and explicit adapter guarantees; do not claim exactly-once external effects without an external protocol guarantee.

The detailed proof ledger prioritizes typed plan/slot validity, codec and artifact lineage checks, dispatch intent ordering, protocol status and late-event handling, process output capture, SQLite crash consistency, changed-binary expansion compatibility, and scheduler liveness. Suggested evidence ranges from F* proof of reducer invariants, to runtime validation of decoded checkpoints, to protocol tests and crash injection. It identified two specific current-code hazards: the budget admission/checkpoint mismatch above, and a terminal Codex status of unknown being mapped to completed. The latter is a source finding; the stale-status and lost-reply cases still need tests. No end-to-end crash or power-loss fault-injection campaign has run. See the [proof/failure ledger](/Users/alex/areas/temp/fstar-pulse-research/proof_fault_model_ledger.md).

The research separates machine proof, runtime validation, fault injection, and external assumptions. The [proof/failure ledger](/Users/alex/areas/temp/fstar-pulse-research/proof_fault_model_ledger.md) ranks the obligations and gives counterexamples. Existing evidence also appears in [proof architecture and extraction](/Users/alex/areas/temp/fstar-pulse-research/proof_architecture_and_extraction.md), [crash recovery](/Users/alex/areas/temp/fstar-pulse-research/crash_recovery_correctness.md), and [saga compensation](/Users/alex/areas/temp/fstar-pulse-research/saga_compensation_for_workflows.md). No whole-system proof or fault-injection campaign has been completed.

| Claim | Machine-checkable target | Evidence and assumptions beyond the proof |
|---|---|---|
| Plan edges, fan slots, join arity, and legal reducer transitions | Indexed constructors and invariant preservation over each event | Validate decoded IDs, schemas, versions, and slot references at runtime |
| Budget conservation and admission | Pure arithmetic transition with a deliberate soft-pool or hard-pool policy | Current float64 state needs a bounded/fixed-point contract; the source has a checkpoint mismatch for negative soft-pool remainder |
| Artifact lineage and checkpoint consistency | Abstract codec/lineage invariants and version-compatible restore relation | Runtime codec validation, digest assumptions, SQLite transaction behavior, VFS and storage durability |
| At-most-once local result commitment | Persisted intent, attempt/cursor state, and atomic local batch invariant | Kill-at-boundary tests; SQLite cannot make remote provider execution atomic with local state |
| Exactly-once or eventual completion of external work | Cannot be derived from the local reducer alone | Adapter idempotency/reconciliation guarantee for safety; provider availability and fair scheduling for liveness |
| Safe process execution of generated code | Type-stage rules and command/result state machine | Compiler, sandbox, OS, process supervisor, generated executable, and output capture remain trusted/validated boundaries |

## F*/Pulse and extraction evidence

The local probe ran on macOS 26.5.2 arm64 with F* 2026.08.09 commit 6881155405467afa5deac27ef54dacccaf53a84b and OCaml 5.3.0. Six samples passed F* verification and extraction: higher-order arguments/returns/captured closures, a Pulse higher-order function, pure recursion, mutable capture, a pts_to stateful effect, and ghost/refinement erasure. Pure and higher-order outputs compiled against the installed Prims interface.

Stateful support remains unresolved. A handwritten installed Pulse reference helper failed compilation with OCaml 5.3 at alloc 0 versus an alloc () value signature. A separate generated Box module expected ref/free names from a different source-extracted API, so that pairing was mismatched. The failure is local evidence and does not establish a release-wide defect. A scratch compatibility shim allowed compilation, but there was no link/run against the canonical unmodified support closure. The later exact-version closure pass compiled the source-consistent Reference/Box modules until PCMReference imported Pulse_Lib_Core_Refs; the installed package has Pulse.Lib.Core.Refs.fsti under /Users/alex/.local/fstar/lib/fstar/pulse/common, but the matching extracted .ml and generation/build route were not found. Link/run were not reached. The reviewed upstream ocaml-smoke CI target did not establish a Pulse client pipeline or supported OCaml version range. See the [closure report](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_source_dependency_closure_retry1.md) and [Core_Refs source-path report](/Users/alex/areas/temp/fstar-pulse-research/pulse_core_refs_source_path.md).

The direct Pulse-to-Rust probe passed F* verification and extension-AST generation for higher-order/stateful samples. It could not run the Rust extractor because the matching pulse2rust program/source checkout was not available. Cargo and rustc exist locally but were not on ambient PATH. This is incomplete alternative-backend evidence; it does not justify changing the current OCaml hypothesis. No performance benchmark was run.

No KaRaMeL/C target is part of the proposal. Direct Pulse-to-Rust was treated as an optional alternative; the missing extractor prevented a backend comparison.

One Pulse behavior remains version-sensitive in the reviewed primary sources: the live loops tutorial describes stt as allowing divergence, while F* v2026.07.24 release notes describe terminating stt plus a separate stt_div. Pin the chosen release and verify the actual effect signatures before using termination claims in workflow liveness proofs ([Pulse loops](https://fstar-lang.org/tutorial/book/pulse/pulse_loops.html), [F* v2026.07.24 release](https://github.com/FStarLang/FStar/releases/tag/v2026.07.24)).

Relevant reports: [feature probe](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_feature_probe.md), [runtime compatibility](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_runtime_compatibility.md), [official OCaml path](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_official_runtime_path.md), [direct Rust probe](/Users/alex/areas/temp/fstar-pulse-research/pulse_direct_rust_probe.md), and [local scratch audit](/private/tmp/pulse-probe-audit-20261008/REPORT.md).

## Indexed-plan prototype result

The kernel completed a small F* prototype without Meta-F*. An input/output-indexed `plan` typechecked identity, pure mapping, typed model-operation data, sequential composition, ordered fanout, and dynamic expansion. F* rejected an intentionally mismatched composition (`plan nat nat` followed by `plan string string`). A separate pure `State × Event -> State × Commands` reducer verified that model commands can be returned before results arrive and that left-then-right and right-then-left completion both produce the declared `(left, right)` result order. A Pulse mutation example also discharged its verification conditions. The exact code and commands are in the [indexed-plan prototype report](/Users/alex/areas/temp/fstar-pulse-research/indexed_plan_prototype_retry.md).

This establishes that useful typed plan constructors and a small reducer can be expressed and checked with ordinary F*, without Meta-F*. It does not prove the whole plan-construction path is effect-free: in this probe, model construction is inert by its pure data representation and inspected function body, not by a trace theorem over an effectful adapter. Higher-order `Pure` and `Expand` functions typecheck and extract, but captured native closures do not provide durable code identity. The probe sketches a `CodeRef` plus explicit capture as data, but implements no codec, registry, version migration, or changed-binary resume test.

The extracted OCaml erased the plan indices to `Obj.t` and inserted `Obj.magic`; runtime checks or a different representation would therefore be needed at the persistence/extraction boundary. The generated Plan module could not compile in the installed switch because `Prims.cmi` was unavailable; compiling bundled `Prims.ml` stopped at missing Zarith (`Z`). Pulse verification and OCaml generation succeeded, but its generated stateful module also could not compile/link against the available support closure. Two prototype artifacts stopped at different stages: one compiled Plan/Semantics modules but failed linking on Zarith, while another stopped compiling at `Prims`. Neither made a runnable executable. This is local toolchain evidence, not a claim that the F* release is generally unusable. No performance comparison was run.

## Decision ledger

The provisional architecture gives enough direction for further isolated prototypes. It does not justify a full production rewrite yet.

The architecture decisions supported by current evidence are:

- Keep model declarations inert and represent external work as explicit operations interpreted later.
- Use a typed plan as the persisted workflow contract; give every persisted node, callback reference, expansion decision, and operation a stable versioned identity.
- Let ordinary F*/Pulse functions express user computation, but route durable effects through typed commands.
- Persist dynamic expansion before children start; make restart use the saved decision and plan.
- Use a pure state transition core and a separate nonblocking adapter/scheduler boundary.
- Represent uncertain external results explicitly; use idempotency/reconciliation declarations rather than assuming exactly-once behavior.
- Treat generated process execution as a first-class durable effect with pinned provenance and captured result metadata.

The remaining high-value decisions are concrete:

1. Compile and link a stateful Pulse client against a canonical source-extracted support closure, without a handwritten compatibility shim.
2. Finish the construct-by-construct comparison of every current API operator and run or compile the same workflow examples in the leading plan/handler encodings.
3. Prove or refute observationally lossless callback replay over artifacts, errors, budgets, scheduling, commands, and history.
4. Specify changed-binary resume with stable code references, encoded captures, schema migrations, and persisted dynamic plans.
5. Define adapter capability contracts for operation identity, history lookup, cancellation, reconciliation, Unknown, and retry.
6. Model or prototype the blocked-callback and process-output crash cuts, then fault-inject the chosen persistence boundaries.
7. Complete source inventory gaps and check the suspected budget/checkpoint and terminal-status edge cases.

The result to preserve is an experiment in proof-oriented programming: write down correctness properties first, make proof obligations useful, and choose implementation mechanisms that discharge those properties without weakening the intended guarantees.

## Research artifact index

The proposal tracker is [fstar_pulse_migration_proposal.md](fstar_pulse_migration_proposal.md). Kernel reports and SQLite run states are stored under /Users/alex/areas/temp/fstar-pulse-research. This index groups the detailed branch reports:

- API/runtime: [API inventory](/Users/alex/areas/temp/fstar-pulse-research/api_semantics_inventory.md), [static authoring](/Users/alex/areas/temp/fstar-pulse-research/static_fstar_pulse_authoring.md), [resume compatibility](/Users/alex/areas/temp/fstar-pulse-research/resume_compatibility.md), [static plan resume](/Users/alex/areas/temp/fstar-pulse-research/static_plan_resume.md).
- Formalisms: [full construct matrix](/Users/alex/areas/temp/fstar-pulse-research/formalism_construct_map.md), [free plan/effects](/Users/alex/areas/temp/fstar-pulse-research/free_plan_vs_effects.md), [arrows/monadic composition](/Users/alex/areas/temp/fstar-pulse-research/arrows_vs_monadic_workflows.md), [dataflow/event sourcing](/Users/alex/areas/temp/fstar-pulse-research/dataflow_vs_event_sourced_workflow.md), [higher-order boundary](/Users/alex/areas/temp/fstar-pulse-research/higher_order_plan_boundary.md), [dynamic expansion](/Users/alex/areas/temp/fstar-pulse-research/workflow_formalism_comparison.md).
- Faults and effects: [detailed proof/failure ledger](/Users/alex/areas/temp/fstar-pulse-research/proof_fault_model_ledger.md), [crash recovery](/Users/alex/areas/temp/fstar-pulse-research/crash_recovery_correctness.md), [typed process boundary](/Users/alex/areas/temp/fstar-pulse-research/typed_artifact_process_boundary.md), [generated code](/Users/alex/areas/temp/fstar-pulse-research/typed_artifacts_generated_code.md), [saga compensation](/Users/alex/areas/temp/fstar-pulse-research/saga_compensation_for_workflows.md).
- LLM backends: [backend-neutral operations](/Users/alex/areas/temp/fstar-pulse-research/backend_neutral_llm_interface.md), [session types](/Users/alex/areas/temp/fstar-pulse-research/session_types_for_codex_client.md), [Codex lifecycle](/Users/alex/areas/temp/fstar-pulse-research/codex_client_lifecycle.md), [Codex message recovery](/Users/alex/areas/temp/fstar-pulse-research/codex_message_id_recovery.md), [generality boundary](/Users/alex/areas/temp/fstar-pulse-research/generality_boundaries.md).
- F*/Pulse toolchain and prototypes: [OCaml feature probe](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_feature_probe.md), [indexed-plan prototype](/Users/alex/areas/temp/fstar-pulse-research/indexed_plan_prototype_retry.md), [runtime compatibility](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_runtime_compatibility.md), [stateful dependency closure](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_source_dependency_closure_retry1.md), [Core_Refs source path](/Users/alex/areas/temp/fstar-pulse-research/pulse_core_refs_source_path.md), [official build path](/Users/alex/areas/temp/fstar-pulse-research/pulse_ocaml_official_runtime_path.md), [Rust extraction probe](/Users/alex/areas/temp/fstar-pulse-research/pulse_direct_rust_probe.md).

## Problem-kernel workflow: usability and issues

The required problem kernel proved usable as the primary research engine. It accepts problem and intention Blob paths, an output Markdown path, and a SQLite path; run state survives a process bound and can be resumed. Absolute paths and one database per question made runs straightforward to manage. After the prompt restrictions were removed, workers used local source inspection, shell/code execution, and web sources.

The initial prompt restrictions were a real research barrier: agents were told not to browse, execute commands, inspect broadly, or create scratch files. Those restrictions were removed from both the custom and default prompts, the executable was rebuilt, and corrected runs produced web-search and local-source evidence. Broad prompts still sometimes yielded a narrow answer; targeted follow-ups were needed. Reports labeled locally checked or provisional were reviewed against their actual source evidence and blockers.

Six of seven broad runs reached the initial 20-minute bound before writing final reports. Their SQLite state was retained, and they completed after resuming with a 40-minute bound. Two immediate resume calls were rejected because the 30-second execution-owner lease had not expired. After that lease elapsed, resuming from the same database succeeded.

No live kernel workflow was manually cancelled. Timed runs were resumed from their saved databases; the terminal dynamic-tool-thread failure ended independently and was retried in a fresh database because the kernel refuses to resume terminal failures.

A separate execution ended with “no agent for dynamic tool thread” and marked its database terminal failed. The resume command correctly refused to resume a terminal failure, so the same question was retried in a fresh database and completed with a missing-module compile blocker. An older stale-running message-ID database was successfully recovered by resuming it. The direct Rust probe finished with a clear toolchain blocker rather than a kernel failure. The first indexed-plan attempt requested a scratch path outside the worker's writable area; it produced no code, and a retry from a disposable worktree with a relative scratch path completed the probe.

At the final snapshot, the research directory contains 45 SQLite files: 44 initialized workflow databases and one empty retry database. They record 55 started executions, all ended; 42 databases have `finished` status and two are terminally `failed`. Three additional CLI invocations were rejected before starting: two immediate resumes during the 30-second owner lease and one attempt to resume a terminal failed run. No kernel execution is active. These counts include retries and multiple executions against one database, not unique research questions. The kernel did not fail persistently, so the user's abort condition was not met. This usability record is the final section of this report.
