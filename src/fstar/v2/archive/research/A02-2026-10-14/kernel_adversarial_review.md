# A02 adversarial kernel review

Read-only audit of `task_brief.md`, active A02 row in `state/work_dag.md`,
`implementation_spec.md`, overview, current `Kernel.fst`, and relevant A01
boundary decisions. No source edited.

## Findings

### Blocker: charge metric omitted at three signature boundaries

- Current `run_budget` has only fuel and charge (`Kernel.fst:162-165`).
- `op_ref` has maximum charge but no metric (`117-124`).
- `generator_ref.generate_graph` takes input and allocation, but no metric
  (`167-175`).
- Normative spec puts metric in `RunBudget`, pins it in `OpRef`, requires
  generator input `(x, metric, allocation)`, and says all charge values use
  the run's one metric (`implementation_spec.md:289-311, 328-330, 654-660`).
  Active DAG explicitly requires metric consistency (`work_dag.md:194`).

Without this, equal naturals can silently mix units; generators cannot vary
their graph/plan by the committed metric, or prove admission for that metric.
Add one metric identity to budget, operation contract, and generator call;
thread same identity through admission and allocation validity. Overview's
short generator summary says input/allocation only, so reconcile that prose
with normative spec and DAG. Metric must be an explicit argument because it
can affect output.

### Blocker: required A02 vocabulary absent from current Kernel

Current file defines no schema-expression syntax/identity, artifact type/store
identities or opaque typed artifact refs, or charge metric identity. Yet active
A02 requires schema syntax/identities, artifact-reference syntax, and metric
(`work_dag.md:194`); spec defines them (`implementation_spec.md:298-303`)
and excludes host handles/I/O from Kernel (§3). Add first-order schema tags
and opaque typed refs only; keep `ResourceHandle`, store interpretation, and
host I/O outside Kernel. Do not treat refs as byte blobs.

### Exact package lookup must be an explicit API seam

`Work` is correctly `noeq`, so its callback records cannot be compared
structurally (`Kernel.fst:110,117,167,177`). `durable_work_ref` is first-order
identity only (`57-61`); current Kernel provides no pinned lookup or membership
witness. A01 and A02 require builder to consume exact returned package plus
membership evidence, avoiding duplicate closures/function extensionality
(`work_dag.md:194,196`; `A01 module_boundary_design.md`). Preserve `noeq`.
Define lookup later at Bundle boundary as `(exact package, membership proof)`;
generator package must carry its universal law beside that same `GeneratorRef`
before Bundle, as A01 decided. Never prove callback equality or accept a
caller-supplied closure with a matching label.

### External byte/validator boundary is mostly sound; preserve it

`validate_reply : input -> bytes -> Tot (option (output input))` has right
shape (`Kernel.fst:117-124`): arbitrary reply bytes gain typed meaning only
through validator at exact input; output family preserves dependent index.
Keep adapter/remote effect outside this pure record. Do not model remote
operation as `input -> output`, infer determinism from `Tot`, or let validator
acceptance narrow static graph edges. Spec explicitly allows distinct calls
with same request to yield different accepted results and journals accepted
canonical output (`implementation_spec.md:280-343`).

One missing link: current `OpRef` does not expose charge metric, so validator
shape alone does not satisfy full operation binding. Pinned `OperationIdentity`
must resolve exact validator, codecs, schemas, adapter/config, and metric per
spec (`289-311`); identity equality alone must not substitute for package
membership.

### First-order graph syntax is on track; typing remains deferred

`wire` and `graph_desc` contain only keys, identities, bytes, and syntax
(`Kernel.fst:68-87`); no closures, output values, or proof terms. This fits
spec. But `output` is phantom in `graph_desc` fields, and `graph_output_wire`
has no encoded typing witness. This is acceptable only because resolver later
proves `SchemaSupported` at exact root input and exact dependent ports. Keep
GraphCodec roundtrip/canonical laws syntactic; never claim they establish
typed graph validity (`implementation_spec.md:1212-1230`).

`ConstantWire(codec_id, bytes)` is first-order. Resolver must distinguish
plain `Codec a` from input-indexed `IndexedCodec i A` by unique pinned codec
entry and decode indexed values at exact root input `x`, as spec requires
(`implementation_spec.md:1334-1339`). Registry must prohibit one identity from
denoting conflicting carriers, families, or codec forms.

## Positive signature checks

- `codec` and `indexed_codec` carry roundtrip plus accepted-byte canonicality
  laws (`Kernel.fst:90-108`), matching spec (`implementation_spec.md:110-127`).
- `code_ref.run`, validator, and generator outputs preserve `output x`; no
  extra postcondition field needed (`Kernel.fst:99-124,156-186`).
- `noeq` on executable records is right direction: use durable identities and
  exact table membership, never function extensional equality.
- Generator callback is total and returns graph syntax plus child plan. Add
  metric argument per normative signature; universal all-input/all-metric/
  all-allocation admission belongs in later `GeneratorPackage`, not callback
  identity or sample output (`implementation_spec.md:654-689`).

## Reconciliation checklist

1. Add/propagate `ChargeMetricIdentity`; ensure budget, `OpRef`, generator
   call, and universal generator admission all agree on one run metric.
2. Add kernel schema-expression identities/syntax and opaque typed artifact
   reference syntax; leave executable schema semantics/resource handles to
   later modules.
3. State exact package lookup contract at Bundle seam: package value and
   membership proof returned together; no closure comparison.
4. Keep graph syntax/codec claims first-order and syntactic; resolve constants
   against exact pinned plain/indexed codec package at exact input.
5. Keep external effect nondeterministic and outside kernel callback; only
   validator is total/pure and its typed result is indexed by exact request.
