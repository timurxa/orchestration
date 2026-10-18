# S2-12 adversarial representation and counterexample audit

**Scope:** Read-only audit of normative §§2–8 and theorem guide. No F* or
normative spec edits. S2-12 acceptance requires module/interface plan, journal
and event representation constraints, proof order, alternatives, owners, and
strong counterexamples ([work DAG, S2-12](../../schema_era_2026-10-14/state/work_dag.md#L98)).

## Verdict

**PASS on semantic contract; PACKET GATE remains.** Spec fixes externally
observable semantics and theorem boundaries. Remaining choices are mostly
representations; each needs an owner, preserved laws, and acceptance proof in
S2-12. Do not silently settle source encodings in this audit. One selection
seam deserves explicit packet treatment: `JournalCodecIdentity` is a stable
replay-context input, but event bytes do not carry it. State how recovery
selects matching journal codec across deployments/restarts.

Theorem guide correctly distinguishes P0 identity, P1/P2 typing and resolution,
P7 effect history, P9 optional resource identity, P13 concrete refinement,
P15 schedule safety, and P16 recovered semantic correctness
([theorem guide](../../schema_era_2026-10-14/key_correctness_theorems.md#L154)).

## Decisions already fixed

| Area | Fixed semantics | Packet decision rule / owner |
|---|---|---|
| Pinned manifest and codecs | Manifest is exact bidirectional projection of package tables; IDs unique/coherent; signatures derive from package codecs; same manifest reloads. Canonical codec laws and root linkage fixed. | **Manifest/identity owner:** choose byte representation and table types only. Keep sorted tagged entries, every semantic version/link, reject duplicate IDs; digest equality needs collision premise. Bind runtime loader/extraction to exact packages. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L138), [S2-02](S2-02-pinned-manifest.md#L13) |
| Graph and resolver | Finite topological node sequence, unique keys, exact pinned work; root/output/constant/pair/projection wiring; one fixed input carrier, dependent output family; edge typing universal over every legal environment. Builder/decode share registry-pinned schema resolver. Completeness exactly for `SchemaSupported`, not arbitrary `Type0`. | **Graph/resolver owner:** choose dependent context encoding and graph builder representation; prove resolver sound/complete and typed transport. Never add an unchecked equality oracle or per-edge serialized proof. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L751), [edge rule](../../schema_era_2026-10-14/implementation_spec.md#L844), [S2-01 alternatives](S2-01-graph-resolution.md#L195) |
| Schema language | AST and calculus fixed: locally nameless `Sigma`, capture-avoiding substitution, pinned `Family`/`IndexCall`, total terminating normalizer, sound derivations; unknown equality rejects. | **Schema owner:** encode AST/checker and prove substitution, normalization, soundness, and completeness for declared calculus. Extension requires new pinned law and theorem scope. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L794) |
| Graph bytes and keys | Node list order is canonical syntax; topo reorders may be isomorphic but are not byte-identical. Keys need decidable equality/canonical encoding; paths define occurrences. | **Graph codec owner:** pick key/byte layout preserving exact list order and stable paths. Do not canonicalize modulo graph isomorphism. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L899), [open choices](../../schema_era_2026-10-14/implementation_spec.md#L2956) |
| Generator and allocations | Generator is total/pure for exact input, run metric, and allocation. Commit exact graph/plan before children; never regenerate after commit. Nested generators get positive fuel; ledger plans and charge metric fixed. | **Generator/P8 owner:** choose plan encoding and prove fit, lift, splice, and progress-rank laws; no dynamic reallocation of free remainder. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L540), [P4/P5](../../schema_era_2026-10-14/implementation_spec.md#L2251), [P12](../../schema_era_2026-10-14/implementation_spec.md#L2679) |
| Events/replay | Five event forms only: `RunStarted`, `GraphCommitted`, `NodeCompleted`, `CallIntent`, `CallOutcome`. Omitted identities/inputs/sequence are derived. Journal list index is sequence. Structural `EventGuard`/`StateWF` is separate from ghost `AuthorizedEvent`/`SemWF`; one serial append requires both. Replay is deterministic and has no external I/O. | **Journal/event owner:** choose framing and record encoding; retain minimal fields, exact derived-value rules, and auth boundary. Raw store write stays private to authorized coordinator. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1500), [append/auth](../../schema_era_2026-10-14/implementation_spec.md#L1591), [event rules](../../schema_era_2026-10-14/implementation_spec.md#L1742) |
| Crash and concurrency | One coordinator/run or shared fencing; local/generator claims bind exact identity/input/allocation and non-reused epoch attempt; candidates invisible until append. Append serial; stale head requires complete reauthorization. Restart fences old appends and rejects old callbacks before scheduling. | **Runtime/controller owner:** choose epochs, worker cancellation/fencing, queue and journal barrier mechanism. Prove P15 for all schedules; fair service only for P14. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1985), [P13](../../schema_era_2026-10-14/implementation_spec.md#L2686) |
| Adapter effects | `K=(operation identity, full occurrence)`, `Q=(canonical request, committed resume data)`, one immutable terminal receipt per key. Same-key overlap/retry must join/reconcile one effect; distinct keys may be nondeterministic and complete out of order. Blind at-least-once is insufficient. | **Adapter/package owner:** choose durable dedupe/status or operation-specific idempotence/reconciliation. Prove physical trace refines P7 or exclude operation. Liveness separate. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L371), [receipt law](../../schema_era_2026-10-14/implementation_spec.md#L411) |
| Resources (optional P9) | Typed refs have exact projection. If physical identity claimed: full immutable version durable before append, same logical typed object after restart, no overwrite/delete/reuse; replay does no store I/O. Handle pointer identity not required. | **Resource-store owner:** choose file/tree/snapshot/reopen representation. Prove `same_logical_resource` preserves admitted observations. Omit P9 for opaque refs; make no physical durability claim. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1371), [P9 target](../../schema_era_2026-10-14/key_correctness_theorems.md#L170) |

### Event and journal constraints packet must preserve

- No repeated `sequence_number`, codec/work identity, input, or child occurrence
  fields when derivable from order, replay state, graph, and manifest. No
  volatile handle or proof term in journal. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1647)
- Event codec and journal framing each need roundtrip and accepted-byte
  canonicality. Reject ambiguous fields, alternate lengths, trailing bytes,
  unknown tags, and malformed nested values. Canonical syntax does not imply
  authorized provenance. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1721)
- `CallOutcome` stores canonical typed output plus correlated evidence, charge,
  artifacts; receipt witness retains raw-reply/validator relation off-journal.
  `NodeCompleted` and `CallOutcome` artifacts equal exact resource projection.
- `CallIntent` commits before any effect. No `GenerationPrepared` because pure
  generator can recompute precommit; no `Failure` event because expected
  failure is a typed result; no terminal event because root result derives
  terminality. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1793)
- `JournalCodecIdentity`/format remains fixed across restart, but is not a
  `RunStarted` field. Packet must say how the host pins/selects it (for example,
  immutable store metadata or deployment/run context); never guess decoder
  from malformed bytes. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1653)
- Crash load returns latest complete committed prefix; old appends settled or
  fenced before load, never commit later. Disk loss, corruption, rollback, and
  external mutation remain out of P10 contract. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L2301)

## Open choices and ownership

Normative §8 leaves source encodings for dependent port contexts, existential
signatures, graph codec, `WorkMember`, concrete manifest, schema AST/checker,
root linkage, graph builder/table shape, node-key bytes, concrete stores and
adapters, and combinators open ([Spec §8](../../schema_era_2026-10-14/implementation_spec.md#L2929)).
S2-12 should assign owners by proof boundary, not let each implementation
module invent cross-module semantics:

1. **Kernel/type layer:** `Bytes`, typed signatures, identity domains, schema
   syntax, wire/event constructors. Owns no host loading or I/O.
2. **Manifest/registry layer:** canonical manifest bytes, actual package table
   projection, uniqueness/coherence, root entry and codec membership.
3. **Graph/resolver layer:** dependent port encoding, builder, graph codec,
   schema derivation and completeness boundary.
4. **Journal/replay layer:** exact event records, canonical framing, pure apply
   and replay, ledgers; coordinator authorization stays separate.
5. **Controller/runtime layer:** volatile claims, callback epochs, serial
   append authorization, crash barrier, scheduler/fairness refinement.
6. **Adapter package author:** per-operation `EffectSafe`, receipt truth and
   metric normalization. Unsafe remote semantics means operation inadmissible.
7. **Resource package author (only P9):** ref projection, immutable versions,
   publication and restart denotation.
8. **Human architecture gate:** resolve any proposal that changes observable
   semantics, expressibility, P0–P16 scope, trust boundary, or optional-P9
   claim. Representation preserving existing laws belongs to named owner.

### Alternatives retained or rejected

- Typed-constructor AST may author graphs, but must call common resolver; it
  cannot itself recover erased proof after serialization.
- Selected base is manifest-pinned schema/type-expression checker. Meta-F*
  can author/verify schemas, not serve as general extracted runtime reifier.
  Per-Work rules only as pinned, proved extensions. Arbitrary `Type0` equality,
  arbitrary resolver callback, and unchecked SMT success rejected.
  [S2-01](S2-01-graph-resolution.md#L195)
- Exact canonical manifest is abstract identity. Digest is an index unless
  host proves collision resistance. Mutable identity beside resolver tables,
  silent duplicate collapse, serialized closures/proofs, and per-node registry
  truth rejected. [S2-02](S2-02-pinned-manifest.md#L52)
- Adapter may use durable key dedupe/status or operation-specific
  idempotence/reconciliation; exactly-once transport is not promised. Blind
  redelivery without effect safety rejected. [S2-07](S2-07-adapter-contract.md#L68)
- P9 allows a fresh process handle, not changed logical resource. Immutable
  files/trees/snapshots fit; mutable DB/session needs pinned snapshot or durable
  reopen relation. [P9 audit](S2-08-artifact-contract-audit.md#L24)

## Strongest counterexamples

1. **Canonical but unauthorized completion:** pinned `f(x)=0`; append canonical,
   well-typed `NodeCompleted(1)` after checking only expected head and replay
   `apply`. P3/P10 all hold, semantic provenance false. Only current-head
   `AuthorizedEvent` plus private append path stops it. P10 does not prove
   provenance. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L1845), [P3/P16 guide](../../schema_era_2026-10-14/key_correctness_theorems.md#L157)
2. **Sampled-output edge proof:** external output declares `Σ n. vector n`,
   observed reply has `n=3`, consumer expects `vector 3`; accept edge using that
   reply. Another legal output has `n≠3`; universal P1/P2 typing fails.
   [Spec](../../schema_era_2026-10-14/implementation_spec.md#L854)
3. **Resolver identity/equation drift:** schema ID reused for changed denotation
   or unproved normalizer equation; resolver accepts ill-typed graph or changes
   after restart. Violates P0/P1/P2; reject identity collision/drift, never use
   unchecked solver outcome. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L815)
4. **Manifest/codec substitution:** old journal names identity `I`; restart
   loads new implementation or codec under same label; bytes remain canonical
   under new codec but mean different value/result. P0/P2/P6/P16 fail. P13 must
   bind extracted runtime to exact manifest package/version. [Spec](../../schema_era_2026-10-14/implementation_spec.md#L154), [P13](../../schema_era_2026-10-14/implementation_spec.md#L2808)
5. **Noncanonical or misframed journal:** trailing bytes, duplicate lengths,
   alternate event encodings, or truncation treated as committed prefix. Breaks
   P3/P10; codec canonicality and store atomic-prefix laws are separate.
6. **Stale/concurrent controller:** two coordinators claim same run or a
   pre-restart append commits after new coordinator loads old prefix; stale
   candidate then authorizes against wrong state. Breaks P10/P15/P13. Shared
   fencing or sole coordinator plus settle-before-load required.
7. **Adapter lost reply:** remote effect occurs, reply lost, adapter-local
   dedupe disappears on restart, retry executes again or returns new receipt.
   Violates P7 despite stable workflow intent. If no remote durable status or
   operation-specific reconciliation, exclude operation.
8. **Run-key alias:** two journals allocate same `RunIdentity`; same
   operation/key path aliases unrelated logical calls. Per-journal CAS cannot
   prevent. P13 allocator must guarantee namespace-wide uniqueness.
9. **P9 false backing:** ref omitted from projection, object partial at commit,
   overwritten/deleted/reused, or resolves to different contents after
   restart. P9/P16 resource extension false. Without P9, never claim durable
   physical backing.
10. **Fairness overclaim:** finite adapter capacity remains occupied forever,
    or scheduler starves continuously enabled action. Safety may hold, P14
    termination does not. Keep fairness/service premises explicit.

## Acceptance checklist / pass-fail

- **Semantic decisions:** PASS. §§2–8 fix work forms, type discipline,
  manifest meaning, event semantics, replay, authorization, ledger rules,
  recovery, optional P9, and conditional liveness.
- **Representation readiness:** OPEN by design. Each open item needs owner,
  module boundary, decision rule, theorem dependencies, and counterexample
  coverage. In particular resolve journal-codec selection across restart and
  state whether deployment limits reject a run before `RunStarted`; do not add
  graph-size/depth caps to API semantics silently.
- **Strongest objection:** an implementation can satisfy byte canonicity,
  structural replay, and durable prefixes while storing a canonical but wrong
  local result. If packet conflates `EventGuard` with `AuthorizedEvent`, or
  treats P10/P16 as establishing provenance without P15 witnesses, reject
  packet.
- **Overall S2-12 gate:** FAIL until packet makes open representation owners
  and the two above decision seams reviewable; PASS once it does and every
  theorem contract remains unchanged. No theorem/source proof is claimed here.
