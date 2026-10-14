# S2-06 integrated review

**Verdict: S2-06 acceptance met at contract level.** This is review of specification targets only; P15 is not a discharged F* theorem.

§4.2 now closes prior abstract-model gaps: it defines exact frontier actions, `ControllerStep_R`, volatile controller/claim/candidate/append-slot state, atomic claim and append steps, current-state `AuthorizedEvent` reconstruction after stale heads, and a one-coordinator-per-run scope. Separate coordinators require shared fencing/claim epochs, correctly distinguishing durable append serialization from global claim uniqueness.

Commit/ack is explicit: commit linearization makes event visible; `CommittedUnacked` blocks another append; crash clears volatile state and P10 determines old/new prefix. Bootstrap binds `RunStarted` to `StartRequest`; precommit crash leaves empty journal and permits resubmission, postcommit recovery ignores request. `ReadyInputAgreement` now states sparse reconstruction and universal agreement over all legal full environments, including generated root input. External intents/outcomes defer effect safety and keyed recovery to P7, consistent with S2-07. `AuthorizedEvent`, `SemWF(C,T,J,S)`, and P10 cuts preserve S2-05 provenance separation; no contradiction found.

**Refinement note, not abstract blocker:** P13 must realize restart epoch advancement with non-reused attempt IDs (or prove old worker callbacks cannot cross a restart). The abstract restart step states this behavior; implementation mechanism remains host refinement. No F* or tests run.
