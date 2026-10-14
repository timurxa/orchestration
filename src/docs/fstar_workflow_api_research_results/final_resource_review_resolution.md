# Final resource review: delta

**Scope:** Audit `design_comparison_and_decision.md` §§6–8 and §10 for resource lifecycle, artifact visibility, JSON-store cuts, report provenance, and inline/library adapter equivalence. No implementation or tests.

## Finding

**One remaining design defect: analyzer report provenance is not explicit in the typed result.** The request binds source-tree digest and pinned tool/config (`§7`, lines 227–242), and result correlation binds the operation key (`§6`, lines 180–188). But representative `AdapterReportShape raw` (`§10`, lines 437–445, 462–463) establishes shape only; no result witness/manifest field binds the exact report and collected-output digests to source digest, tool/config identity, and this occurrence/key. A stale or misassociated, well-shaped report could therefore enter `ParsedFindings` unless that binding remains an implicit adapter assumption.

**Delta:** Add a provenance record to `Raw` or the accepted operation evidence, e.g. `ReportProvenance(source_digest, tool_build_digest, config_digest, operation_key, report_digest, output_manifest_digest)`. Validate its correlation and content digests before `Accepted`; persist it with completion and artifact provenance. State explicitly that F* checks the tuple/digest relation only. Evidence that the analyzer actually read the materialized source and generated those bytes remains an adapter/host-refinement assumption (or trusted attestation), and does not prove findings true. `Sound(source, findings)` still requires the separate checker/certificate proof already specified.

## Reviewed areas: no additional defect found

- **Resource lifecycle/artifacts:** §7 keeps handles and temporary paths out of workflow artifacts; materialization and collection define confinement, exact bytes, allowlists, required outputs, and OS/adapter boundary. Staged bytes precede private manifests; completion gates visibility. §8 P6 covers retention/readback and unavailable/corrupt behavior. Sound.
- **Private manifest/commit visibility:** §8 state model distinguishes private `ManifestStaged`, `CompletionCommitted`, and completion-gated `ManifestVisible`; resolver must verify matching completion even after physical index publication. Cross-store and crash-cut obligations explicit. Sound as target contract, not implementation evidence.
- **JSON-store cut mapping:** §8 P3 enumerates temp/write/flush/file sync/rename/directory sync and maps old/new/uncertain states. It explicitly says directory-sync errors cannot count as durable commit, notes current ignored `EINVAL`/`EBADF`, requires single runner per run, and treats SQLite as separate refinement. Adequate target mapping; current runner does not yet satisfy the stated guarantee.
- **Inline/library contract:** §6 requires same operation/driver types and proof obligations, pins implementation, and makes behavioral equivalence a relation rather than string-ID equality. §10 JEV case reuses that interface. Sound; equivalence remains proved/assumed, as appropriate.
- **Unknown/recovery:** §6–8 preserve possibly-applied effects as `Unknown`, require key-bound reconciliation/deduplication, and distinguish prefix safety from stronger backend-bisimulation equivalence. No false exactly-once claim found.

**Evidence:** `design_comparison_and_decision.md:153–201,203–254,258–280,315–385,432–474`.
