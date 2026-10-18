# A00 simplification audit

**Scope:** current v2 source plus normative spec. Read-only source review; no F* declarations changed. Source claims below describe the checked-in files, not discharged P0–P16 results.

## Findings

### 1. Separate manifest syntax, resolver, and executable bundle

- **Measured:** current import graph is acyclic: `Kernel` is lowest; `GraphCodec`, `Identity`, and `Journal` import it; `Graph` imports `Kernel` and `Identity`; examples import those layers. `Identity.pinned_registry_bundle` currently contains a registry identity and two independent tables (`Identity.fst:288-292`). It explicitly says the manifest/content binding is not proved (`Identity.fst:284-287`). `Graph` consumes that bundle for typing, and also owns typed wiring, builder APIs, allocation checks, and generator admission (`Graph.fst:304-381, 417-525, 799-895`). The builder type/accessor and constructor API are `assume`s; four P1 laws remain `admit()` (`Graph.fst:418-424, 523-525, 908-956`).
- **Spec fact:** P0 requires the manifest to be an exact projection of actual packages and each executable identity to resolve to one coherent full package; P1/P2 are bounded by that manifest’s `SchemaSupported` language (`implementation_spec.md:2668-2670`).
- **Inference:** putting the resolver result inside the bundle while making resolver consume the bundle creates a likely cycle. Current source has no resolver yet, so this is a future risk, not a current import cycle.
- **Recommendation:** follow the smallest acyclic split: first-order `ManifestCore` depends on `Kernel`; `GraphResolve` consumes only kernel syntax plus manifest; `Bundle` then joins resolved schemas to executable tables; `GraphInterpretation` composes decode and resolve. Keep allocation and generator admission below graph construction. This matches the packet’s explicit dependency rules (`implementation_packet.md:242-252, 271-280`) and leaves P0/P1/P2 contracts unchanged. Avoid a broader split into one file per helper.
- **Alternative / hardest objection:** retain one `Graph` and `Identity` module, prove same behavior in place. This saves interface churn, but a resolver that imports `Identity.pinned_registry_bundle` cannot also be a component used to define that bundle. Splitting too early can also force awkward F* universe/existential interfaces; test those interfaces with a small package before moving the whole source.

### 2. Derive registry views; avoid editable duplicate package lists

- **Measured:** `code_ref`, `op_ref`, and `generator_ref` embed codecs in each executable package (`Kernel.fst:110-124, 167-175`). Separately, `pinned_registry_bundle` stores a global codec registry (`Identity.fst:185-207, 288-292`). Constant-wire typing looks up codec membership in that table (`Graph.fst:313-327`). The chain example repeats the same `nat_codec` and `nat_indexed_codec` values in a separate registry literal (`GenerationExample.fst:25-45, 59-74`).
- **Inference:** two caller-editable representations of codec availability can drift. Current source proves per-table uniqueness and lookup key equality, but shows no law that the table is exactly the codecs projected from work/root/graph packages.
- **Recommendation:** make package tables authoritative and derive lookup/index views from them, or make each table entry reference one canonical codec package with a membership proof. Keep standalone registered codecs for constants. Add P0 exact projection/coherence before relying on resolution. Spec already requires work signatures be derived from the package’s exact codecs and forbids a second editable signature (`implementation_spec.md:199-210, 221-224`).
- **Alternative / hardest objection:** preserve separate codec table for fast lookup. That is fine if it is a derived view with a proved exact projection; a cached view alone is not extra semantic state. Removing the table entirely may make constant codecs and root-entry codecs awkward to resolve.

### 3. Treat `DurableWorkRef` fields as a checked redundant encoding, not authority

- **Measured:** `durable_work_ref` stores work identity, input codec identity, and output identity (`Kernel.fst:57-61`); `durable_ref_of_work` derives all three from a `Work` package (`Identity.fst:50-69`); equality checks all fields (`Identity.fst:71-77`). `GraphDesc` persists this reference (`Kernel.fst:76-86`).
- **Spec fact:** complete work-identity coherence is required; full `DurableWorkRef` uniqueness is also required but explicitly does not replace it (`implementation_spec.md:199-206, 221-224`).
- **Recommendation:** keep the current encoding until P0 proves both directions: every serialized ref resolves to exactly one package, and every ref field equals the fields derived from that package. Consider dropping repeated codec fields only after proving package identity alone selects the complete signature and testing canonical graph decode against malformed/mismatched refs. Do not use ref uniqueness as a substitute for identity coherence.
- **Alternative / hardest objection:** make graph syntax store only `WorkIdentity`, then derive codec links on resolution. This removes repeated bytes and mismatch states, but only preserves theorem strength if package identity is injective over complete signature/schema/configuration and all codecs; otherwise a reused identity silently changes graph meaning. The normative spec imposes that stronger law, so this simplification is feasible in principle, not already established by current source.

### 4. Keep local allocation and occurrence allocation as separate scopes

- **Measured:** generated graphs carry a plan keyed by graph-local node key (`Kernel.fst:146-160`); journal plans are keyed by full occurrence (`Journal.fst:18-37, 47-60`). `Graph` validates local key alignment, then budget/fuel totals (`Graph.fst:804-875`).
- **Inference:** these look like duplicated allocation state, but represent different identities before and after a generated graph is committed. Generator cannot know its eventual occurrence path.
- **Recommendation:** retain both scopes; centralize exact local-plan validation and one deterministic local-key-to-occurrence lifting theorem at commit. P4 requires exact lifting and P8 exact plan projections, so collapsing scopes would move complexity rather than remove it (`implementation_spec.md:2672, 2676`).
- **Alternative / hardest objection:** use occurrence keys inside generator output. This makes plans globally addressable, but leaks runtime parent path into pure deterministic generation and weakens reproducibility unless path is an explicit generator input.

## Proof-strength boundary

The current source is a partial starting point, not a P0–P16 proof: the spec says so directly (`implementation_spec.md` opening status); current `Journal` contains event/action data and `abstract_state = { state_history }`, with replay/apply left to later work (`Journal.fst:82-113`). The example and chain prove one fixed family; they are not generic graph completeness or recovery (`GenerationExample.fst:85-155`; `ChainProof.fst:66-115`; `implementation_spec.md:2668-2684`). Any source split or derived-view change must retain the table’s P0–P16 contracts, especially P1 universal edge typing/completeness, P4 commit-before-use, P10 every-cut durability, P15 all-schedule safety, and P16 provenance through recovery.

## Highest-value proof experiment

Build a tiny acyclic `Kernel -> ManifestCore -> Schema -> GraphResolve` slice. Prove a root-wired local node resolves and a universally mismatched dependent edge is rejected from manifest schemas, without an edge-local proof payload or runtime output. Separately, test P0 exact package projection in `Bundle`, including a deliberately duplicated `CodeIdentity` with a different codec link; reject that bundle. If exercising constant-wire codec resolution, add `GraphInterpretation` after `GraphCodec` and `Bundle`, where the packet places that composition. This preserves the acyclic boundary and does not claim generic P0/P1 completion.
