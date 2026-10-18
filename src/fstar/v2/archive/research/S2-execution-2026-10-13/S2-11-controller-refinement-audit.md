# S2-11 controller and worker-pool refinement audit

**Result: PASS after formalization fixes.** This review checked P13 against
P15's abstract controller and P14's conditional liveness clauses.

The abstract controller already provides exact attempt IDs, single-coordinator
ownership, per-occurrence claims, reconstructed-input/allocation binding,
proof-bearing candidate returns, stale-head reauthorization, serial commit,
and crash revocation. P13 now requires the concrete pool to atomically enforce
these claims, bind callbacks to the exact non-reused attempt epoch, and reject
canceled or old callbacks. Candidates remain invisible until an authorized
event linearizes. A shared multi-coordinator implementation needs a shared
claim/write fence; a process-local mutex is insufficient.

The audit identified three notation gaps in the initial P13 draft; all are
closed:

- `Controller` stores the journal prefix and volatile fields; its logical
  state is `replay(ctx, latest_committed_prefix)`. P13 now states this
  projection rather than referring to an independent `A.state` field.
- Crash/load correspondence now explicitly requires the abstract
  `ControllerStep_R` restart, an exact recovered prefix, and volatile state
  with all claims, candidates, in-flight keys, and append slot empty at the
  load barrier.
- The restarted epoch must never have been used before, and no work is
  dispatched until the load finishes.

P14 remains conditional: each continuously enabled ready claim is launched;
each launched computation makes progress to a returned result; completed
results reach the append path fairly. `Tot` on the abstract Work function
alone does not prove concrete scheduler return. This was made explicit in
§5/P14 and P13's component obligations. No conflict with P14, P15, or P16
remains.

Reviewer: `/root/s211_controller_refinement`. No F* source, implementation,
verifier, or tests were changed or run.
