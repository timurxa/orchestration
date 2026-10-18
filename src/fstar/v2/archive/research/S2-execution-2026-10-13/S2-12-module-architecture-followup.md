# S2-12 module architecture follow-up

**Verdict: FAIL on import acyclicity as written; other requested checks PASS.**
Read-only review of `implementation_packet.md` §§2–3 and relevant normative
signatures/theorem clauses. No source or packet edits; no F* run.

## Findings

1. **Import cycle: `GraphBuilder` ↔ `Generation`.** Packet assigns
   `GeneratorMember` to `WorkflowV2.Generation` and says `Generation` imports
   `GraphBuilder` (§3 table, lines 233–235). But normative `WorkMember` for a
   `GenerateWork` includes `GeneratorMember` (implementation spec lines
   688–705); packet `add_node` requires `WorkMember` (packet lines 141–150).
   Therefore graph builder must consume the generator admission witness while
   Generation module needs the builder for typed splice: direct or interface
   cycle. **Fix:** split generator admission contract/witness from graph-splice
   theorem. Put `GeneratorMember` in an acyclic admission/interface module that
   depends on Bundle, Schema/Resolver, and allocation predicates but not
   GraphBuilder; have GraphBuilder consume it; let Generation/splice consume
   GraphBuilder. Keep `WorkMember` semantics unchanged.

2. **Possible scheduler-contract cycle needs one explicit rule.**
   `Services` owns scheduler records (line 240), while `Controller` imports
   Services (line 242). Define scheduler service law without importing
   Controller-owned `Action`/frontier types, or move those types to a lower
   `ControllerCore`/Frontier module. Likewise, keep the P7 receipt/effect
   predicate in a lower service-contract layer so Provenance may consume it
   without Services importing Provenance. Current import row says “abstract
   types” but does not establish these edges are acyclic.

## Requested checks that pass

- **P5/P8 ownership exact:** Recovery owns exact graph-commit reconstruction
  plus P5/P16 (line 243); BudgetProof owns conservation and once-only
  settlement P8 (line 238), with rationale at lines 256–259. Proof-order table
  independently gives P5 = P2/P4/P10 and P8 = P3/P4/P7 (lines 328–331).
- **Artifact cycle avoided:** opaque packed artifact-reference syntax sits in
  Kernel; Journal consumes payload syntax; optional Artifacts proof imports
  Journal and adds store laws (lines 227, 236, 239, 249–257). No Journal import
  of Artifacts stated. P9 remains optional as normative spec requires.
- **P15 scope explicit:** exactly one active commit coordinator per run; concrete
  P13 must prove ownership. Multiple coordinators require shared
  claim/epoch-fencing contract and extended theorem (lines 210–215, 242, 245).
- **Core signatures match normative contract:** `Work` has local/external/
  generator variants; `GraphDesc` stores topological first-order nodes and
  output wire; `GeneratorRef` carries identity, input codec, graph codec, and
  total pure `generate_graph(x, metric, allocation)` returning descriptor plus
  child plan indexed by exact input/allocation (packet lines 71–131;
  implementation spec lines 527–535, 642–660). No signature mismatch found.

## Strongest objection

`WorkMember`/`GeneratorMember` ownership crosses graph construction and
generator admission. Until split, table’s claimed layering cannot compile
without a cycle or weakening normative rule that generator membership carries
universal admission proof. Scheduler import is secondary but should be
specified before implementation.
