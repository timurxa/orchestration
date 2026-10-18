# S2-05 encoding and replay audit

Scope: `implementation_spec.md` §§4.1, 4.4, P0/P2/P3/P10, plus S2-05 row in `state/work_dag.md`. Read-only audit of claims; no normative/source edits.

## Finding

**Target:** model one logical event sequence `J` as the only state authority, `S = replay(J)`. Prove event bytes, complete journal bytes, replay, and append fencing as separate layers.

**Established:** design text states these goals and abstract laws. Current evidence ledger says P3 has event/action/state declarations only, with no `apply`, `replay`, transition/WF, terminal, or journal-codec theorem. P10 has no journal codec, serial append/load implementation, storage model, crash-cut proof, or persistence refinement. P0 codec laws and P2 graph syntax results do not establish an event or journal codec. Therefore all equations below are **targets**, not discharged results.

## Encoding layers and laws

Keep three relations distinct:

1. **Indexed payload codecs (P0/P2):** for a selected exact identity/index `i`, `decode_i(encode_i(x)) = Some x`; accepted payload bytes are canonical: `decode_i(b) = Some x ==> b = encode_i(x)`. Resolver identity and codec membership must be the exact pinned manifest entries. This covers graph/value codecs only when their exact index and identity are proved.
2. **Event codec (missing explicit interface):** define total `encE : Event -> Bytes` and `decE : Bytes -> result Event Error`. Target laws:
   `decE(encE(e)) = Ok(e)`;
   `decE(b) = Ok(e) ==> encE(e) = b`.
   Also require event-constructor tags to be disjoint, field framing injective, version/domain separation fixed, and every embedded payload decoded canonically under its event-derived pinned codec/index. A canonical graph/value payload does not make its enclosing event canonical.
3. **Journal codec:** define one canonical framing, e.g. version + canonical event count + length-delimited canonical event byte strings. Target laws:
   `decJ(encJ(J)) = Ok(J)`;
   `decJ(b) = Ok(J) ==> encJ(J) = b`.
   Decoder must reject trailing bytes, nonminimal lengths/naturals, alternate tags/orderings, malformed nested payloads, and noncanonical event encodings. A deterministic event codec alone does not provide unique list framing; a unique journal byte string is stronger than “one event sequence has one replay.”

If event count/order is already fully framed by a proved canonical list codec, reuse it explicitly. Do not silently identify these laws. “Each accepted byte string decodes uniquely” should mean a partial decoder with at most one result; canonicality adds exact re-encoding. It cannot mean every byte string is accepted.

## Event-specific codec obligations

All events need a stable envelope: format/version, constructor tag, run identity, contiguous sequence number, and unambiguous field framing. §4.1 calls run/sequence part of event identity but minimal family descriptions do not say whether these are physically in each record or in an envelope. Pick one representation; encode it exactly once and prove decoder reconstructs same values. Numbers, options, sums, maps, and lists need canonical encodings; map order cannot depend on hash iteration.

- `RunStarted`: exact registry and root-entrypoint identities; root input under exact indexed input codec; graph bytes under entrypoint-selected graph codec and P2 resolver; budget naturals; allocation plan with canonical finite-support map/list representation. Codec must not let event choose a different graph codec than entrypoint/manifest. Semantic authorization still proves input, graph, plan are exact `start(input,budget)` result.
- `GraphCommitted`: generator occurrence key; child graph bytes under parent-resolved graph codec, canonical decode plus exact P2 resolver; graph-local allocation plan in canonical representation. Replay derives parent/generator/input and lifted occurrences. Encoding cannot smuggle duplicate occurrence IDs or alternate plan ordering. Bytes being canonical and graph well-typed do **not** prove equality to generator return; that is append provenance.
- `NodeCompleted`: node occurrence; output bytes decoded/re-encoded with exact input-indexed output codec at reconstructed input; artifact references under declared typed reference codec/schema. Codec must not infer index from untrusted bytes. Canonical well-typed output is weaker than equality to pinned `CodeRef.run`.
- `CallIntent`: stable adapter occurrence/key; resume data encoded by a pinned, versioned adapter resume codec (or explicitly opaque canonical bytes with exact identity). Operation and input derive from replay state; request bytes derive canonically from indexed request codec. Reservation derives from identity/allocation. Need distinguish durable resume data from volatile handles; no sockets/processes/closures serialized. Intent canonicality does not prove safe retry semantics.
- `CallOutcome`: output bytes via exact indexed operation output codec; evidence encoding/schema and correlation key must be canonical and bound to same intent; settlement natural and artifact refs canonical. Canonical output typing does not prove reply correlation, validator acceptance, charge bound, or physical artifact backing.

Any event schema change needs format/version change or a compatibility proof. P0’s pinned application manifest identity does not by itself specify journal format identity or event codec identity; bind journal format/codec version into run header/store contract.

## Replay, WF, and provenance

**Target:** with immutable pinned identities and pure total `apply`, replay is a deterministic fold:

`R([]) = Ok(S0)`

`R(J ++ [e]) = match R(J) with Ok(S) -> apply(S,e) | Error x -> Error x`.

For every accepted `J`, each prefix transition succeeds, `WF(J,R(J))`, and terminal state admits no next event. `replay` determinism is a function/fold property; it says nothing by itself about physical bytes, append authority, or whether a local result was genuinely computed.

Keep predicates separate:

`WF(J,S) := (R(J)=Ok(S)) and structural/typed/ledger transition invariants`.

`Auth(T) := each event in append history T has event-specific provenance proof against exact immediately preceding replayed head`.

`SemWF(T,J,S) := J prefix-of T and S=R(J) and WF(J,S) and Auth(T restricted to J)`.

Graph generation equality, local function equality, and external reply correlation belong to `Auth`/`SemWF`; replay checks canonical bytes and structural validity without rerunning code/effects. This matches §4.1’s distinction, but expected-head API as written accepts only `Event`; proof/capability transport to journaler is not represented in its type.

## Expected-head append target

Let current stored sequence be `J`, `n = |J|`, `R(J)=Ok(S)`. Authorized append target requires a witness `AuthEvent(S,e)` plus `apply(S,e)=Ok(S')`. Atomic result:

`append(n,e,w) = Appended` iff linearization sees exactly head `n`, same `J`, `R(J)=Ok(S)`, witness is for `(S,e)`, and transition succeeds; then stored logical journal is exactly `J ++ [e]`.

Otherwise return `Rejected` and stored journal remains byte-for-byte/logically unchanged. If a process-local authorization was computed at old `J`, stale head forces reload, replay, reconstruct, and reauthorize. Merely replacing expected number is unsound: event derivation may depend on predecessor outputs, allocation, pending intent, or terminality.

**Critical type gap (target):** `append_store : ... -> expected_head:nat -> Event -> ...` and prose “legal `apply` transition” capture structural legality, not event-specific semantic provenance. Either journaler takes a proof/capability produced by serial coordinator, or the append boundary is explicitly an abstract verified coordinator operation whose contract includes current-head authorization. A concrete CAS store cannot independently verify ghost proof; P13 must prove only verified coordinator can reach its write primitive.

## Journaler premises needed for P10

P10 needs all, at the byte/store boundary:

- linearizable single-writer compare-and-append on exact sequence/head (shared fencing if multiple controllers); stale/invalid request leaves old bytes unchanged;
- atomic-prefix visibility across every process cut: load exposes complete committed prefix, never partial event/tail; append commit point defines inclusion;
- monotone durability: committed bytes remain in same position at every later restart; ack implies commit; commit-before-ack may recover new prefix;
- append-path integrity: only current-head serial coordinator writes, old prefix immutable, contiguous sequence numbers; no external mutation/rollback/ABA;
- exact canonical encode/decode and successful `decode_journal(stored_bytes)=Ok(J)` plus `encode_journal(J)=stored_bytes`; storage load returns that `J` exactly, not merely some replay-equivalent journal;
- pinned manifest and journal-format/codec identities resolve identically after restart; graph/value/event codecs preserve their laws and indices;
- explicit failure semantics for an unreadable/corrupt store: outside crash-only theorem per current §4.4, never silently truncate or normalize and claim exact recovery.

These are contracts/refinement obligations, not facts derivable from deterministic replay. §4.4 lists much of prefix/durability/integrity but “canonical encoding” conflates event and journal byte laws, and the abstract `load_store : StoreModel -> Journal` hides stored bytes. P10 must connect physical bytes -> canonical decoded `J` -> replayed state.

## Strongest counterexample

Take valid pinned code `f(x)=0`, input `x`, and a nonterminal replay state where node is ready. Encode `NodeCompleted(node, encode_indexed(1))` canonically; output `1` is well-typed/canonical, event shape and transition can satisfy structural `WF`. If append checks only current expected head and `apply` legality, it appends this event. Replay deterministically returns completed node output `1`, while `f(x)=0`. Every byte/replay/canonicality fact can hold; P6 provenance and `SemWF` fail. Thus canonical bytes + deterministic replay + expected head do not entail semantic correctness. Analogous `GraphCommitted` counterexample uses a different but well-typed/allocation-valid child graph than generator returned. The repair is event-specific authorization witness bound to current replayed head, enforced by sole serial coordinator; P10 preserves that authorized append history, P13 refines it.

Separate byte counterexample: two physical encodings of same logical event list (e.g. overlong varint length versus minimal length, or concatenated events with ambiguous/no length framing) decode to same `J`. Replay is identical, but byte canonicality fails. Conversely canonical event encodings without canonical list framing permit multiple journal encodings. Require strict reject + exact re-encode laws at both layers.

## Minimal repair and boundary

**Target minimal spec patch:** introduce `EventCodec` and `JournalCodec` contracts and exact equations above; choose a canonical envelope/framing and state where run/sequence/version live; require event decoder to route embedded bytes through exact pinned indexed codecs; make append’s contract take an authorization witness/capability or name verified-coordinator operation; define physical load law as bytes decode/re-encode exactly to returned logical prefix. State P3 proves logical fold/WF/terminal; P0/P2 supply embedded identity/indexed graph/value laws; P10 assumes and composes store/journaler byte laws, monotonicity, prefix atomicity, and protocol integrity; P13 proves concrete implementation refines them.

**Remaining boundary:** no crash-only theorem can guarantee survival of media loss, corruption, external edits, rollback, identity-to-binary mismatch, or unsafe adapter effect behavior excluded by contracts. Canonical event and journal bytes prove representation uniqueness and replay stability; they do not prove local/generator provenance, adapter semantics, artifact durability, store truthfulness, or platform durability. Those remain P6/P7/P9/P10/P13 premises/theorems as applicable.
