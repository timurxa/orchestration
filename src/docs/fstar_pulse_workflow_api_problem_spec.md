# F* workflow API: problem specification for a design-search workflow

**Status:** This document is the problem input for the specialized Nim research workflow. That workflow is tasked with investigating, designing, and producing implementation/proof evidence for the target API. This document states the problem; it is not itself an API design.

## Assignment and scope

The search workflow must investigate, design, implement, and prove a minimal, expressive workflow API written in ordinary F*. The API should play the role of the dynamic workflow API in [`src/api`](../api), while making durable execution and backend substitution straightforward. The target implementation uses F* source and the normal F* extraction path, with OCaml as the preferred executable target. Small FFI kernels are acceptable only where unavoidable and must be isolated with explicit contracts. Do not use Pulse or KaRaMeL.

This language restriction applies to the API and its runtime, not to the specialized research workflow: that search remains the existing Nim/Vecherinka workflow and may use model-backed processors to develop and compare proposals. The API being designed does not need an LLM client, provider protocol, conversation/thread lifecycle, token accounting, or other LLM model-state management. Model-like or other nonlocal work may appear only as generic typed operations behind replaceable adapters, as needed to exercise workflow semantics.

“Minimal” applies to the API's primitive kernel. A library may add ergonomic combinators and richer functionality. “Maximally expressive” means workflow authors use ordinary F* everywhere, including inside dynamic `so` blocks: the same language, types, functions, and effect rules apply inside and outside. Do not introduce a reduced callback language or an interpreter for general user F* code. A runtime may interpret the API's own workflow operations, but it must not interpret a second language in place of executing the user's F*.

The search must compare materially different API mechanisms against the same required cases, choose only when evidence warrants it, and support every claimed property with a proof under explicit, reasonable assumptions. Existing research reports are evidence and historical context; this specification controls wherever they describe a Pulse or provider-specific target.

## Required workflow behavior

The API must support typed composition and higher-order local computation; same-input parallel branches with stable ordered results; shape-preserving traversal over empty, present, absent, and nested values; and dynamic routing/expansion through `so`. A `so` block can inspect typed runtime data and an explicit immutable budget/resource snapshot, then directly return a value or choose and execute a child computation. Child computations use ordinary F*, and may nest, branch, traverse, and recurse. Show bounded recursive examples and prove the relevant termination/resource bounds.

Workflow construction must not itself perform nonlocal effects. Define how external operations are represented and executed through generic replaceable adapters, including admission, charging, pending, failed, cancelled (if supported), and unknown outcomes. Pending work must not prevent independent ready work from progressing. Leave provider-specific request protocols and model-session state out of scope.

Keep the primitive API small and show which conveniences—composition, fan/join, projections, traversal, typed external operations, and Blob-like values—can live in an ordinary F* library. Demonstrate that library abstractions preserve the kernel's types, proofs, and resume guarantees. Do not prescribe a fixed menu of candidate approaches or directions.

Use the [Vecherinka DSL guide](vecherinka_dsl_guide.md), [budget contract](vecherinka_budgeting_spec.md), and examples including [parallel research](../examples/vecherinka_parallel_research.nim), [formalization](../examples/vecherinka_formalizer.nim), and [bounded routing](../examples/vecherinka_problem_kernel.nim) to identify observable behavior. Preserve useful semantics without copying Nim syntax or requiring LLM-specific behavior.

## Durable state and continuation

The complete logical runtime state needed to continue a run must survive process termination in a durable, inspectable store. SQLite is one suitable choice; the design may use another durable backend if its guarantees are stated. This includes workflow position/control state, captured values or their durable reconstruction inputs, dynamic `so` choices and child computations, pending/completed generic operations, branch slots, scheduler queues, resource snapshots, stable code/schema versions, artifacts, and any required materialization or I/O state. A final-artifact-only checkpoint or top-level cursor is insufficient.

Do not assume native F* closures or process memory can be serialized. Specify how the system records stable function/code identities and encoded captures, persists resolved expansions, or safely replays computation from durable inputs and effect results. Any state reconstructed after restart must have enough durable identity, inputs, environment, and event history to justify that reconstruction. Distinguish durable data from process-local handles, temporary paths, and other capabilities; define how those are recreated, reacquired, or marked unavailable.

Specify atomic persistence boundaries and recovery at every point around state writes and generic external effects. Prove a continuation theorem for every execution cut: after termination, restoration from the last valid durable state is observationally equivalent to uninterrupted execution from that state, preserving values, ordered effects, artifacts, budgets, failures, and progress. Cover the actual F* implementation or a proved refinement of it, not only an abstract model. State assumptions about storage durability/atomicity, code and codec compatibility, terminating local computations, scheduling fairness, and adapter behavior. Do not infer exactly-once external effects from local IDs. Tests and traces support but do not replace the proof.

## Artifacts and I/O state

Evaluate whether “artifact” should be generalized and whether types should carry detail such as codec, provenance, validation, materialization, or I/O state. Compare raw typed values and explicit Blob/BlobTree bytes with values prepared for generic external work, materialized files, durable references, and live handles. Give concrete use cases and assess ergonomics, proof value, and whether each representation survives termination. Decide whether an abstraction belongs in the small kernel, an F* library, or nowhere; do not require generalization without demonstrated value.

## Proof obligations

Inventory useful system guarantees and prove each claimed property under explicit, reasonable assumptions. At minimum, address typed composition and extraction boundaries; inert construction; ordinary-F* `so` branching and continuation; ordered joins and progress with pending operations; resource accounting; artifact codecs/provenance/materialization; durable state transitions; and termination/resume equivalence. Include the implementation-to-semantics relationship. Assumptions must not presuppose the property being proved. If a useful guarantee cannot be proved or implemented, report the blocker and mark the result incomplete rather than silently dropping the guarantee.

## Deterministic debug runner

Implement the same F* API and run actual extracted workflow code without a live service. Use scripted local adapters and a deterministic event queue to exercise immediate and pending outcomes, reordered/duplicate/late events, failure, and unknown outcomes. Exercise direct and identity routes; children with zero or multiple operations; nested and bounded recursive expansions; and resource-boundary routes. Show that independent ready work progresses while effects are pending, joins remain ordered, and snapshot/restore after an expansion choice and during pending work preserves the proved continuation and resource snapshot. Repeated runs with identical durable inputs, code identity, and event script must produce identical outputs and inspectable traces.

Run unchanged workflow code through at least two materially different fake adapters to demonstrate backend substitution. Inject nondeterministic inputs such as time or randomness through explicit, recorded generic effects. The runner must build and execute via the pinned ordinary F* extraction/runtime path, preferably F* to OCaml; typechecking alone is not implementation evidence. It must not require Pulse, KaRaMeL, an LLM service, Codex, JEV, or network access.

## Expected result and completion criteria

The search workflow should return a compact design report and inspectable evidence: API/library source, deterministic runner, representative executable examples, continuation/resume proof, other property proofs, assumptions, and unresolved blockers. Compare candidate API mechanisms using the same cases. A custom workflow-operation interpreter may be considered, but it cannot replace execution of ordinary F* callbacks.

The target is complete only when it:

1. Produces a small primitive API and ergonomic F* library, with evidence that `so` and non-`so` code use the same ordinary F* language.
2. Implements and runs every required workflow case in the deterministic runner, including dynamic/nested expansion, asynchronous scheduling, and adapter substitution.
3. Stores all logical execution state durably in an inspectable backend and resumes after process termination.
4. Proves the continuation theorem and every other useful claimed property under clear, reasonable assumptions, including implementation-to-semantics refinement.
5. Evaluates artifact/type abstraction through concrete uses and durable representations, and records any unproved or infeasible part as an explicit blocker.

The migration proposal and research synthesis below are pre-pivot F*/Pulse research. Use their source-grounded findings about the existing API, typed workflow structure, artifacts, persistence, and recovery as evidence. Treat Pulse extraction/runtime recommendations, Pulse-specific proof obligations, and provider-client/model-state work as historical and out of scope for this F* only search.
