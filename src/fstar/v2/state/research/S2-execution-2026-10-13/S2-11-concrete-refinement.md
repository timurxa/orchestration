# S2-11 — Concrete-to-abstract refinement boundary

## Scope and decision

S2-11 specifies P13 as the proof boundary from an implementation to the
abstract workflow contracts. It does not implement the runner or select a
platform storage/adapter design. The normative addition is
`implementation_spec.md` §6, “P13: concrete-to-abstract refinement
obligation,” with the compact P13 entry in `key_correctness_theorems.md`.

The prior spec named the concrete components P13 must cover but did not give a
concrete-to-abstract relation. P13 now requires a `ConcreteRep` relation
between concrete runtime state and the abstract P15 controller. Its durable
projection ties the current complete journal image to the linearized append
history, decodes those bytes to the same prefix as the controller, and derives
logical workflow state only by replaying that prefix. The relation also maps
volatile claims/candidates/adapter calls, ties the loaded replay context to the
exact pinned bundle, and checks the adapter trace against P7. P9 resource
identity is included only when claimed.

The P13 theorem requires:

1. Initial concrete state maps to the unique empty journal and empty abstract
   volatile controller.
2. Every concrete step maps to one authorized `ControllerStep_R` or preserves
   the abstract state by stuttering. Batched host transitions may instead map
   to a finite abstract path. A commit point maps to exactly one authorized
   event, preserving event order and bytes.
3. A recovery load occurs only after the P10 settle/fence barrier; its exact
   bytes decode to the prefix through that barrier. The restart maps to the
   abstract restart step, has empty volatile claims/candidates/in-flight
   keys/append slot, and uses a never-before-used epoch. No work dispatches
   until the load finishes. Pending calls remain durable and resume only with
   their same P7 key.
4. Concrete component refinements cover the controller/worker pool, serial
   journaler, current-head authorization, adapter trace/effect law, host
   identity/manifest/extraction, `validate_reply` and its exact `persist_x`
   projection, indexed codecs, and optional persistent resource storage.
5. Liveness transfer is conditional: the implementation must satisfy P14's
   fair claim/result-return/append/response service premises, or those remain
   explicit assumptions of the termination claim.

P13 does not assume the journaler or adapter accepts concurrent inputs. The
worker pool and adapter may perform independent work concurrently; each
journal append remains serial. Remote effect semantics, host filesystem
behavior, extraction identity, and OS progress are explicit proof-bearing
contracts or premises. They are not inferred from local code.

## Dependency clarification

The P13 theorem table initially used `P0-P12`, which accidentally made P9
mandatory. The artifact theorem is optional for workflows that treat artifact
refs as opaque typed values. The dependency is now `P0-P8, P10-P12, P15`, with
P9 added only when claiming physical persistent-resource identity. The graph
and DAG topology are unchanged.

## Adversarial cases

P13 must refute: old callbacks crossing restart; two coordinators claiming
one occurrence or writing one run without shared fencing; torn or trailing
bytes exposed as committed; an old append committing after restart loaded;
stale authorization retargeted by updating only the head; changed code or
codec behind the same identity; duplicate remote effect after response loss;
two runs colliding in the adapter-key namespace; and P9 objects that are
missing, mutable, or rebound after restart.

## Independent audit results

- **Controller/worker audit — PASS.** It confirmed that the abstract P15 rules
  already specify unique claims, exact callback binding, stale reauthorization,
  no-rerun-after-commit, and restart fencing. It found missing concrete
  simulation notation. Follow-up reviews required exact replay projection and
  fully empty volatile state at the load barrier; both are explicit in §6.
- **Journaler audit — PASS.** It confirmed P10's cut contract and adversarial
  cut set. It found ambiguity between last loaded bytes and current committed
  bytes; §6 now distinguishes `store_bytes(c)` from `load_bytes_at(c,b)` and
  connects the latter to the exact fenced history prefix. It also checked the
  abstract restart step and replay-derived controller state.
- **Adapter/identity/resource audit — dependency fix integrated.** It
  confirmed the component obligations for stable-key effect safety, exact
  manifest reload, run-ID namespace uniqueness, codecs, and optional P9. It
  found P13's table range incorrectly included optional P9; the row now lists
  P9 conditionally. It also required concrete execution of the exact pinned
  `validate_reply` and exact `persist_x` projection for each `CallOutcome`;
  §6 now states this explicitly.

No F* source, implementation, verifier, or tests were changed or run. P0-P16
remain proof targets; P13 specifies what an implementation must prove to
inherit the abstract guarantees.
