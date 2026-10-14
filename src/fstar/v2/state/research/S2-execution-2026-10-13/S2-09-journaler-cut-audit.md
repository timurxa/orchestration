# S2-09 P10 journaler and cut audit

Read-only audit of the serial journaler, physical-byte recovery, and P10
contract in `implementation_spec.md`. No F* source or tests were changed.

## Result

Pass after one formal precision improvement: make the physical bytes returned
at load explicit and prove they decode to the same logical journal projection.
That change is now part of the spec.

## Checked properties

- Compare-and-append is against the exact expected prefix. Success appends one
  authorized event; stale head preserves the bytes exactly and invalidates the
  old authorization.
- The physical load value is `load_bytes`. `load_store` is only its decoded
  projection under `load_bytes_decode`, so it is not a second source of truth.
  Journal codec canonicality proves re-encoding the decoded journal yields
  the exact loaded bytes.
- At each crash/recovery load barrier, all prior append requests have a final
  committed or aborted disposition, and none can commit after the load.
  Loaded bytes decode to the exact prefix of events whose commit points passed
  by that barrier.
- Prefixes are monotone across ordered cuts. A committed event remains at the
  same position in every later prefix. Recovery replays exactly the loaded
  prefix.
- An append racing with process exit may commit before the recovery-load
  barrier and then must appear; otherwise it is aborted and cannot appear
  later. Thus the cut is the post-exit load barrier, not the earlier instant
  of process termination.

The contract excludes disk/device loss, corruption, rollback, and external
mutation. P13 must prove the concrete write, flush, load, and fencing behavior
refines these laws. The journaler accepts no parallel writes; one serialized
append is sufficient for the ghost-state and prefix proof.

## Reviewer provenance

- `/root/s208_charge_ledger` checked compare-and-append, durability, prefix
  monotonicity, and P16 composition. Its byte-level recommendation was
  integrated; its follow-up passed the resulting `load_bytes` relation.
- `/root/s208_combined_audit` attacked append/exit/ack windows, late old
  requests, stale permits, root-start races, generator/local commit windows,
  external retry windows, and concurrent independent completion. No trace
  attack remained after the integrated edits.
