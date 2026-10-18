# S2-12 — module architecture and caller API audit

**Scope:** implementation readiness review of `implementation_spec.md`,
`key_correctness_theorems.md`, and historical `src/*.fst`; proposed module
layers and caller-facing signatures. Read-only audit except this report. No F*
source edits or verifier run.

## Verdict

**Acyclic module order is normative; concrete module split and public signatures
still need an implementation packet.** Spec fixes workflow meaning sufficiently
to avoid inventing execution semantics. It intentionally leaves source-level
representations open (§8, lines 2929–2977), especially manifest/schema
resolution and dynamic heterogeneous graphs. S2-12 can close that by selecting
representations below and mapping each to existing clauses. Do not treat current
`.fst` as implementation of P0–P16.

The normative dependency seam is especially useful: Kernel owns first-order
identity/work/wire/schema syntax; ManifestCore is first-order; Resolver consumes
ManifestCore plus graph syntax; Bundle composes resolver with executable tables;
Runner consumes complete bundle (`implementation_spec.md` lines 242–252). Keep
this order to avoid Resolver/Bundle import cycle.

## Recommended minimal layering

| Layer | Module responsibility | Theorem ownership |
|---|---|---|
| 1. `Identity` / `Kernel` | Identity records, indexed codec and `Work` signatures, first-order `Wire`/`GraphDesc`, schema expression syntax, budgets and occurrence IDs. No runtime state. | Foundations for P0–P8. |
| 2. `ManifestCore` | Canonical tagged manifest rows, schema/rule AST and identities, root entry metadata; no closures or typed resolver result. Validate uniqueness and links. | P0 manifest projection/coherence. |
| 3. `Schema` / `Resolver` | Denote supported schema syntax; normalize/decide equality; resolve first-order graph against manifest into typed graph and `WireTyping` derivations. Reject unsupported or unproved edges. | P1 builder/resolver soundness and bounded completeness; P2 decode/resolve roundtrip. |
| 4. `PinnedBundle` / `Registry` | Join ManifestCore to existentially packed code, generators, operations, codecs, validators, graph codecs, resource contracts, root entrypoints. Prove exact membership and identity coherence. | P0 executable identity and restart-stable reload. |
| 5. `TypedGraph` / `GraphCodec` | Typed port telescope, typed wiring, graph builder, finite-DAG witness, canonical first-order graph codec. Generator output uses same resolver/builder. | P1/P2 and graph parts of P4/P5. |
| 6. `Budget` / `Ledger` | Occurrence-keyed charge/fuel state, allocation validation, plan lifting, reservation/settlement functions. Keep charge metric identity fixed by run. | P8; generator admission lemmas used by P4/P12. |
| 7. `JournalCodec` / `Events` / `Replay` | Exact event vocabulary, canonical bytes, event guards, deterministic replay, structural `StateWF`, terminal absorption. No worker or store I/O. | P3; codecs contribute P0/P2. |
| 8. `Provenance` / `Authorize` | Ghost witnesses and constructors for `RunStarted`, local completion, generated graph, adapter outcome; `AuthorizedEvent` indexed by exact replay state and event. Separate `SemWF` history from byte-level `StateWF`. | P4/P6/P7 authorization; induction premise for P15/P16. |
| 9. `ServiceContracts` | Proof-bearing records for serial journaler, local/generator executor, adapter, artifact store, loader/code extraction, and fairness. Keep P9 optional. | P7/P9/P10 assumptions and P13 refinement inputs. |
| 10. `Frontier` / `Controller` | Pure abstract transition system: durable replay prefix plus volatile claims/candidates/in-flight keys/append slot; claim, return, authorize, append, stale, crash/load steps. One coordinator per run. | P11/P15; ranks feed P12. |
| 11. `Progress` / `Recovery` | Fairness/rank termination theorem and recovered semantic graph composition. | P12/P14/P16. |
| 12. `ConcreteRuntime` / `Refinement` | Host controller, worker pool, journal adapter, codec/extraction and optional store representation relation; prove forward simulation and progress refinement. | P13, then instantiate concrete P14/P16. |

Separate syntax from typed resolution: existing `Graph.fst` currently imports
`Identity` and embeds registry membership in typed witnesses. Preserve its useful
typed port telescope, but move first-order syntax and manifest schema AST low
enough that Resolver does not import `PinnedBundle`. Bundle can then expose
typed constructors without creating a cycle.

## Caller-facing type/signature inventory

Names below are recommended API shapes, not extra semantics. Pseudotypes use
`Tot` for total pure functions and proof arguments for the laws callers must
supply. Host effects stay behind explicit service records.

```text
type Work (A:Type) (B:A -> Type)
  = Local(CodeRef A B)
  | External(OpRef A B)
  | Generate(GeneratorRef A B)

type PinnedBundle = {
  manifest: CanonicalManifest;
  resolve_work: DurableWorkRef -> option (packaged Work);
  resolve_codec: CodecIdentity -> option (packaged Codec);
  resolve_root: RootIdentity -> option (packaged RootEntry);
  exact_projection: ManifestProjectionLaw;
  unique_identities: RegistryUniquenessLaw
}

val graph_empty : bundle:PinnedBundle -> input:A -> x:A
  -> Tot (TypedBuilder bundle A x)
val graph_add : builder:TypedBuilder bundle A x
  -> work:Work I O -> member:WorkMember bundle work
  -> input:Wiring bundle A x ports (fun _ -> I)
  -> Tot (result:option (TypedBuilder bundle A x * PortRef ...))
val graph_finish : builder:TypedBuilder bundle A x
  -> output:Wiring bundle A x ports (fun _ -> O x)
  -> Tot (GraphDesc A O x * TypedGraphWitness ...)

val resolve_graph : manifest:ManifestCore -> x:A -> GraphDesc A O x
  -> Tot (result:option (ResolvedTypedGraph manifest A O x))
val encode/decode_graph : GraphCodec -> x:A -> GraphDesc A O x
  -> Tot CanonicalBytes / option GraphDesc

type RootEntry (A:Type) (O:A -> Type) = {
  start:A -> RunBudget -> Tot (RootStart A O);
  root_law: forall x budget. SchemaSupported (start x budget).graph
            /\ AllocationPlanWF ...
}
val create_run : bundle:PinnedBundle -> root:RootEntry -> run:RunIdentity
  -> input:A -> budget:RunBudget -> Tot (StartRequest ...)

type JournalService = {
  load:RunIdentity -> Tot (LoadedPrefix * LoadCutWitness);
  append:expected:Journal -> event:AuthorizedEvent expected
    -> Tot (Committed event | Stale current_prefix | Rejected);
  recovery_barrier:RunIdentity -> Tot (FencedPrefix * CutLawWitness)
}
type LocalService = {
  launch:AttemptToken -> Claim -> Tot (WorkerHandle Claim);
  poll:WorkerHandle Claim -> Tot (option (WorkerReturn Claim));
  worker_law: WorkerReturn Claim -> PinnedResultWitness Claim
}
type AdapterService = {
  submit_or_resume:CommittedIntent -> Tot AdapterSubmission;
  poll:inflight_keys:list CallKey -> Tot (list (CallKey * bytes));
  validate:PendingIntent -> (CallKey * bytes) -> Tot (ValidatedReceipt ...);
  adapter_law: P7EffectAndCorrelationLaw ...
}

type Controller = { prefix:Journal; volatile:Volatile }
val enabled_frontier : PinnedBundle -> ReplayState -> list Action
val controller_step : Services -> Controller -> Tot (option Controller)
val run/resume : Services -> RunIdentity -> Tot (RootOutput | Failure)
```

`launch` may retain several distinct claims concurrently up to configured
capacity; `poll` outcomes carry their original claim token and can arrive in
any order. `AdapterService.poll` may return several distinct keyed responses;
controller correlates each to its durable intent, then performs one journal
append at a time. These signatures are conceptual service transitions, not a
claim that F* `Tot` itself supplies threads, fairness, or network I/O.

Implementation packet should spell out omitted indices (`ports`, `O`, exact
occurrence/allocation) using the normative clauses, not adopt the pseudotype
ellipsis as final API. `JournalService.append` is intentionally serial and
proof-carrying: a raw event append signature would erase the P15 authorization
boundary. `AdapterService` is keyed and can have multiple outstanding keys;
controller consumes outcomes and journals them serially. Do not put parallel
journal writes in `JournalService`.

`GeneratorRef` caller contract must stay exact:

```text
generate_graph : x:A -> ChargeMetricIdentity -> GenerationAllocation
  -> Tot (GraphDesc A O x * GraphAllocationPlan)
```

plus universal `GeneratorMember` proof that result is supported and allocation
plan valid for every input/metric/parent allocation. Controller only executes
generator after input and allocation are reconstructed from committed replay;
`GraphCommitted` commits exact graph bytes and lifted plan before children
enter frontier. This directly serves P4/P5, dynamic DAG correctness and
committed-graph reuse (`implementation_spec.md` lines 670–723, 2251 onward).

## P0–P16 ownership and abstract/concrete boundary

- P0–P2: layers 1–5; schema completeness is explicitly only for
  `SchemaSupported`, never arbitrary erased `Type0` (`implementation_spec.md`
  lines 2668–2670; `key_correctness_theorems.md` lines 94–98).
- P3–P5: layers 5–8; P3 replay must not claim semantic origin; P4 commits exact
  generated result and P5 reuses committed bytes/occurrence lift.
- P6–P9: layers 7–9; local result provenance; stable keyed effects; ledger
  conservation; optional publish-before-reference resource identity.
- P10: `JournalService` plus physical journal refinement; load returns exact
  latest complete committed prefix; old appends fenced before restart load.
- P11/P12/P14: frontier, strict append rank, then conditional liveness. Fair
  worker/result/append/adapter/store progress and finite crashes are explicit
  premises, not P15 safety.
- P15: pure controller transition induction over every finite allowed schedule;
  unique claims, exact bindings, current-head reauthorization, committed-only
  visibility, crash cuts and no rerun after commit.
- P13: implementation-specific simulation from concrete state to P15
  controller plus component refinements; never premise hiding abstract
  authorization. It includes non-reused attempt epoch, journal fencing, exact
  pinned host implementation and key-namespace uniqueness.
- P16: compose P15 authorized trace with P10 durable cut and P0–P8 provenance;
  P9 extends only when physical object identity is claimed.

This order follows the theorem table, not old `Journal.action` execution order
(`implementation_spec.md` lines 2666–2684; `key_correctness_theorems.md` lines
100–177). Keep abstract `Controller` pure and parametric in proof-bearing
services. Put P13 in a downstream module so no circular import from controller
back into concrete host modules.

## Historical source evidence and readiness

- `WorkflowV2.Kernel.fst` already has indexed codecs and dependent `Work`:
  `code_ref.run : x -> Tot (output x)`, generator result indexed by exact input
  and parent allocation (lines 90–185). This is a sound substrate for
  dependent output values and dynamic generation.
- `WorkflowV2.Graph.fst` has a dependent port telescope, typed wire witnesses,
  `TypedNodesSnoc`, and finite typed-DAG witness (lines 158–194, 304–381,
  600–623, 766–797). It is a useful encoding experiment, not the complete
  manifest-schema resolver or P1 completeness proof.
- `WorkflowV2.GraphCodec.fst` encodes first-order syntax and proves graph
  decode/canonical properties (top-level `enc_graph` / `decode_graph` and
  `graph_decode_encoding`, `graph_decode_canonical`). It does not establish
  typed resolution; P2 must compose it with Resolver.
- `WorkflowV2.Identity.fst` has existentially packed work/codecs and exact
  identity membership over small registries (lines 84–174, 185 onward). It
  lacks the complete tagged manifest, schema/rule/resource/root tables and
  cross-table coherence required by P0.
- `WorkflowV2.Journal.fst` has event data and simple actions, then explicitly
  says V2-04 will define replay and that vocabulary grants no authority
  (lines 83–113). No controller, volatile claims, append contract, replay,
  adapter or P13 implementation is present in these source files.
- `GenerationExample.fst` and `ChainProof.fst` prove one nat chain/generator
  example; they do not prove arbitrary schema-supported dynamic graph
  resolution, interleavings, persistence, or worker scheduling.

## Strongest concern / implementation readiness

**Strongest concern:** API looks compact until existential resolution crosses
the durable boundary. The implementation must recover exact dependent indices
from identity plus schema proof after decoding first-order graph bytes; an
ordinary lookup by `DurableWorkRef` or codec name does not produce those
indices. A later implementation agent must not invent a proof payload on each
edge, trust runtime outputs to justify edges, or silently narrow completeness.
Use canonical manifest schema AST, total normalization/equality, and
registry-indexed resolver result; reject outside `SchemaSupported`.

**Can implementer avoid inventing semantics?** Yes, for workflow semantics:
P0–P16 and S2-06 controller steps define results, order, concurrency, restart,
and liveness boundary. Not yet without representation choices. S2-12 packet
must choose (1) schema AST/normalizer and equality proof encoding; (2)
heterogeneous graph builder and resolver witness shape; (3) canonical manifest
and root-entry relation; (4) event/replay/state and service-record signatures;
(5) map/set/attempt epoch representations and scheduler interface; (6) concrete
store/host simulation target. These are listed as open in `implementation_spec.md`
§8. Give each an owner and acceptance theorem; choices may not change stated
semantics.

No source or normative document edited; no F* verification claimed.
