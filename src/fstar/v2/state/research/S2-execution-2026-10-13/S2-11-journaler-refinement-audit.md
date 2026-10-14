# S2-11 journaler and storage refinement audit

**Result: PASS after byte/load and restart-relation clarifications.** This
review checked P13 against P10's exact byte, prefix, and recovery-load laws.

The concrete journaler must implement one serial compare-and-append path with
an exact current-head check, one linearization point, atomic complete-prefix
visibility, stale rejection without mutation, and durable-before-ack behavior.
Every supported load returns physical bytes that decode to the latest
committed prefix; canonical encoding reproduces the exact bytes. A torn tail,
trailing bytes, alternate authority, or raw write path violates the contract.
Before restart load, all old append requests are committed or aborted; none
can linearize afterward. The chosen filesystem/database/device implementation
must prove these laws, not simply claim “flush” or rely on a local mutex.

The initial P13 notation used bytes from the last recovery load for arbitrary
live states, which could lag a just-committed event. It now distinguishes
`store_bytes(c)`, the current complete committed image, from
`load_bytes_at(c,b)`, the exact bytes returned at a fenced recovery barrier.
The crash-load clause selects the committed prefix through barrier `b`, proves
the load bytes decode to it, equates it with `J(c')`, and requires the
corresponding abstract restart step and replay relation. Thus the abstract
controller cannot retain a stale or unrelated state after load.

Adversarial cuts include before write; torn/incomplete write; commit before
ack; competing compare-and-append at one head; stale append after another
commit; restart racing queued/abandoned writes; old append released after
load; repeated loads checking monotone prefixes; and malformed/noncanonical
bytes. The valid result is old prefix or full new prefix only, with no fork or
partial event; a committed event remains at its position and no old append
changes the post-barrier view.

Reviewer: `/root/s211_journaler_refinement`. P10's abstract contract was
already complete; this adds the P13 concrete proof boundary. No F* source,
implementation, verifier, or tests were changed or run.
