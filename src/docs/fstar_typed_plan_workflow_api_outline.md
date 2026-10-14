# F* typed-plan workflow API

**Status:** Typechecked and tested prototype; incomplete against the proof and continuation requirements. This is a type-indexed combinator API with an in-memory closure evaluator, persisted manifest, and event-sourced reducer—not a defunctionalized typed plan AST. See the [implementation and evidence report](fstar_typed_plan_workflow_api_report.md) for alternatives, artifact decisions, proof ledger, test results, assumptions, and blockers.

The selected kernel uses ordinary F* `Tot` code and typed workflow endpoints:

```text
pure       : CodeRef<C,I,O> -> Workflow<I,O>
then_flow  : Workflow<I,M> -> Workflow<M,O> -> Workflow<I,O>
fork       : Workflow<I,A> -> Workflow<I,B> -> Workflow<I,(A,B)>
lift       : Shape<S> -> Workflow<A,B> -> Workflow<Carrier<S,A>,Carrier<S,B>>
external   : OpSpec<C,I,O> -> Workflow<I,O>
so         : RouteCode<C,I,O> -> Workflow<I,O>
```

`Lift` traverses one workflow over a value shape. `Fork` combines two workflows on the same input and preserves output order. `Lift` alone cannot replace an arbitrary two-branch fan with distinct branch workflows.

The durable model stores a versioned run header and full reducer event journal, then reconstructs projections and scheduler actions by replay. Replay consistency is relative to the supplied header; no external digest authenticates its root input, initial budget, build ID, or manifest. The extracted runner writes atomic, inspectable JSON snapshots and uses scripted immediate and deferred adapters through a deterministic in-memory event queue. This does not establish the all-cut continuation theorem: queued replies are not persisted, code identity and storage/parser refinement remain assumptions, extracted-runtime simulation is absent, and several reducer/artifact proofs remain explicit blockers.

Run the F* to OCaml checks and restart scenarios with [`src/fstar/v0/run_tests.sh`](../fstar/v0/run_tests.sh). The script checks the F* release string but does not verify toolchain commits or all dependency versions. The [problem specification](fstar_pulse_workflow_api_problem_spec.md) defines completion criteria; this prototype does not claim those criteria are met yet.
