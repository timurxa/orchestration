# API provenance recheck

**Scope:** Follow-up review of the final `OperationContext`, `ReportProvenance`, parser, and unverified-result shapes in `design_comparison_and_decision.md` §§6–7 and §10. No source changes, build, typecheck, or tests were run.

## Result

No further design defect found in the reviewed provenance path:

- The evaluator constructs `OperationContext` from the run, pinned plan, occurrence, attempt, request, and operation/config/resource identities. The author-defined operation cannot choose that context.
- `Operation.validate` receives the expected context. Its output predicate depends on that context, and the accepted `OpOutcome` carries the context with the refinement-bearing value.
- Analyzer `ReportProvenance` binds source-tree, resource/tool, config, exact operation key, report bytes, and output manifest digests. `AdapterReportShape` checks those fields against both source and context before the report can be accepted.
- `Parsed` requires an accepted raw result and a `Parses` relation over its report bytes. `Unverified` requires `HasSuccessfulParse`, so neither constructor can turn rejected/failed analyzer output into parsed findings.
- Resume compares the encoded context/result with the exact completion key; parser/checker evidence is reconstructed by pinned validators rather than deserialized as erased proof data.

## Remaining trust boundary

The shape relation proves consistency of fields and bytes only under the digest implementation/canonical encoding assumptions. It does not prove a real analyzer read the materialized source and produced the returned bytes. That requires a proved adapter/host refinement or a trusted tool attestation. `Sound(source, findings)` still requires the separate F* checker or certificate-verifier proof.

The signatures remain semantic F* notation and were not compiled. This recheck confirms the design relation, not an implementation theorem.
