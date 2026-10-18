# S2-12 module architecture follow-up 2

**Verdict: PASS on import cycles; CONDITIONAL on exact P4 dependency boundary.**
Read-only review of updated `implementation_packet.md` §§2–5. No F* run.

## Checks

- **Generator cycle resolved:** `GeneratorAdmission` now owns
  `GeneratorMember`/`WorkMember`, imports Bundle + GraphResolve + Allocation,
  and must not import GraphBuilder or Generation. GraphBuilder consumes it;
  Generation consumes GraphBuilder. Acyclic (`implementation_packet.md`
  lines 234–237, 254–259).
- **P2 owner/composition clear:** GraphInterpretation owns P2 by composing
  syntax codec, resolver, and bundle; none import it (lines 231–233).
- **P5/P8 owners clear:** GraphRecovery owns P5 exact committed graph/plan
  reuse; BudgetProof owns P8 conservation/settlement. Their stated inputs
  match P5 = P2/P4/P10 and P8 = P3/P4/P7 (lines 242, 247, 337–338).
- **Services acyclic:** scheduler uses generic claim tokens, no Controller
  action/frontier dependency; Services owns P7/P10 service inputs and excludes
  Provenance; Provenance consumes Services (lines 239–242, 260–263).
- **Artifact cycle avoided:** packed-ref syntax stays in Kernel, Journal does
  not import Artifacts, optional P9 theorem imports Journal/store contract
  (lines 227, 238–243, 265–267).
- **P15 scope explicit:** ControllerModel has one active coordinator; P13 must
  refine that scope; multi-coordinator case requires shared fencing and theorem
  extension (lines 244, 246, 250).
- **Signatures match:** packet `Work`, `GraphDesc`, and `GeneratorRef` fields
  match normative signatures, including generator input codec + graph codec
  and `generate_graph(x, charge_metric, allocation)` returning a result
  indexed by exact `x`/allocation (packet lines 71–131; spec lines 527–535,
  642–660).

## Remaining exact-dependency concern

`GraphCommitProof` owns full P4 and imports ControllerModel (lines 245–246).
ControllerModel imports BudgetProof and Provenance; BudgetProof depends on P7
receipt law (lines 242, 244). Normative P4 depends only on P1–P3
(`implementation_spec.md` line 2672), while P5 depends on P2/P4/P10 (line
2673). This may be harmless if P4 proof uses a narrow projection of those
modules and does not require P7/P8 service premises. Packet should state that
projection or split the commit-visibility lemma below full ControllerModel;
otherwise theorem dependencies silently exceed normative P4/P5. This is sole
open concern; module imports themselves are acyclic.

No other missing P2/P4/P5/P8 theorem owner found.
