# V2-01/V2-02 simplification decision record

Date: 2026-10-12. This record is the current design decision for the reopened
V2-01/V2-02 declaration pass. Earlier research reports remain as provenance;
where they recommend captures or size bounds, this decision supersedes them.

## Goal

Keep the first workflow API and its durable state to one source of truth per
fact. Runtime-created graphs must be general finite typed DAGs and use exactly
the same work, journal, adapter, allocation, and recovery rules as root graphs.
The generator chooses a graph; the graph's typed output supplies the
generator occurrence's eventual result.

## Decisions and alternatives

### Work references and registry

- **Chosen:** derive one first-order `durable_work_ref` from each exact `Work`.
  Do not carry a separately supplied typed `work_ref` and `work_package`.
- **Why:** a paired type duplicates identity and permits the executable term
  and durable name to disagree unless an additional refinement is carried.
  Derivation removes that constructor-level mismatch.
- **Kept:** `global_work_registry` inside one `pinned_registry_bundle`. It is
  the heterogeneous resolver required after decoding a graph label. Removing
  it would leave a durable identity string with no semantics to resolve.
  This is distinct from a per-work registry wrapper, which is removed.
- **Still open:** the current `typed_graph_witness` carries the bundle but has
  no field proving that every `Work` and codec used by the witness resolves
  from that bundle, nor that the returned existential has the exact dependent
  types. The current `pinned_registry_bundle` also carries an identity with no
  proof tying it to the bundle contents. The F* checker passing does not
  discharge these P0/P1/P2 obligations.

### Captures and operation nondeterminism

- **Chosen:** remove capture values/codecs from local, external, and generator
  work, and from durable references. Per-run settings are part of the typed
  input. Fixed implementation configuration belongs to the pinned code,
  operation, or generator identity.
- **Alternative considered:** retain captures for local/generator work because
  they may parameterize pure functions. Rejected for the minimal API: it is a
  second input channel with its own codec and canonicality burden. If a setting
  varies per run, include it in the input; if fixed, pin it with the identity.
- **External behavior:** no output function is assumed. `validate_reply` only
  checks bytes actually returned by the adapter against `o x`. Different calls
  with the same input may return different accepted outputs. Recovery reuses a
  committed `CallOutcome`, or resumes the pending logical call under the same
  occurrence key. P7 still needs a formal adapter transition/refinement
  contract, including effect correlation and liveness.

### Dynamic graph result

- **Chosen:** `generate_graph x allocation` returns `GraphDesc i o x`; the
  `GenerateWork` constructor remains indexed by `o`. Once committed, the child
  graph's output wire supplies `o x`.
- **Alternative considered:** treat a generator as ordinary work returning a
  graph value. Rejected because that confuses the control result (topology)
  with the workflow result and would type the node output as `GraphDesc`.
- **Recovery:** before `GraphCommitted`, a pure total generator can be
  recomputed from the same committed input and allocation. After commit,
  recovery uses the exact graph bytes and never regenerates topology. No
  `GenerationPrepared` event is needed.

### Graph bounds and resource allocation

- **Chosen:** no node-count, depth, or encoded-size bounds in the graph API or
  builder completeness theorem. Graph expressibility covers every finite
  typed DAG. Execution has separate occurrence-keyed expansion-fuel and
  charge ledgers, committed once in the root/child allocation plan.
- **Alternative considered:** carry independent graph size caps and a generic
  `GenerationBounds` record. Rejected because these are deployment admission
  policies, duplicate resource authority, and a second completeness theorem
  would not strengthen DAG expressibility. Fuel/charge remain because P8 and
  P12 depend on them.
- **Single-source fields:** every plan entry is keyed by the node occurrence;
  a `CallIntent` does not store maximum charge again. Replay derives it from
  pinned operation identity and its allocation. `GraphCommitted` derives the
  parent from its generator occurrence. `CallKey` is the occurrence itself.
  Event identity is `(run, sequence)`, so the journal does not also store an
  arbitrary event ID.

### Proof helpers and API surface

- Removed constructor wrappers `local`, `external`, and `generate`; the three
  `Work` constructors are the primitive surface.
- Removed `is_typed_dag`, a direct alias of `dag_wf`, and the trivial
  `graph_sound` lemma that only restated that alias. Descriptor soundness is a
  direct projection by the definition of `graph_wf`.
- Removed one-use option-presence helpers and the earlier unused graph
  uniqueness/topology helpers. Kept `same_nat_set`, `nat_list_unique`, and
  used typed-wire/work-input helpers because they state real graph invariants
  or are reused in proofs.
- Renamed the current erased relation to `wire_label_isomorphic`. The target
  typed `graph_isomorphic` must preserve dependent environments and resolved
  work signatures. The current helper does not satisfy that target.

### Journal facts

- `RunStarted` records the root input codec identity; otherwise a loader has
  no schema with which to decode root input bytes.
- `NodeCompleted` records only occurrence, output bytes, and artifacts. The
  graph supplies work/input/output codec identity.
- `CallIntent` records only its occurrence key and adapter resume data.
  Operation, input, request, and charge reservation derive from replay state.
- `CallOutcome` records the call key, actual validated output bytes, evidence,
  actual charge, and artifacts. It does not predict or recompute an external
  reply.
- `GraphCommitted` records generator occurrence, child graph bytes, and
  allocation plan. Parent graph, generator identity/input, and graph codec
  derive from the generator occurrence and prior committed state.

## Provenance

- `/root/proof_ledger` independently identified the missing registry-membership
  witness and the spec's omission of indexed constants; both are now explicit
  in the spec and tracked as open proof work.
- `/root/api_report` identified duplicated work wrappers, unused graph
  predicates, and the difference between graph expressibility and bounded
  admission. Its suggestion to retain size caps was not adopted because the
  current task prioritizes a single allocation ledger and unbounded finite-DAG
  expressibility.
- `/root/v2_adversarial` found no pure/deterministic external-result
  assumption in `validate_reply`, but recommended keeping some captures and
  treating generator output as ordinary graph output. The latter was resolved
  in favor of the typed `GraphDesc` control-result split; captures were removed
  consistently after the user's direction to remove them generally.
- Implementation verification after the edits:
  `opam exec -- make -C src/fstar/v2 verify` passed for Kernel, Identity,
  Graph, and Journal with `--cache_off` and warning 285 fatal. This is
  declaration/typechecking evidence only; the explicit admissions and
  resolution/typed-isomorphism gaps remain.

## Still to research/prove

1. Define the graph decoding/resolution witness that ties every durable
   `Work`/codec reference to the exact unique result in the pinned bundle.
2. Define typed graph isomorphism and transport of dependent port environments,
   dependent outputs, indexed constants, and occurrence identity.
3. Give `GraphCodec` typed decode soundness in composition with `dag_wf` and
   exact registry resolution; descriptor-byte roundtrip alone is insufficient.
4. Formalize P7's adapter transition relation: same-intent recovery,
   nondeterministic valid outcomes, effect/evidence/charge correlation, and
   eventual outcome under explicit liveness assumptions.
5. Connect root workflow identity, root input codec, and graph codec to one
   pinned entrypoint; prove host reload selects that exact bundle.
6. Prove every-cut journal canonicity/durability and artifact publication in
   the concrete store/adapter refinements.
