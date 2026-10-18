module WorkflowV1.Theorems
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Artifacts
open WorkflowV1.Operations
open WorkflowV1.Work
open WorkflowV1.Expansion
open WorkflowV1.JournalTypes
open WorkflowV1.OperationFacts
open WorkflowV1.JournalFacts
open WorkflowV1.Contracts
open WorkflowV1.Admission
open WorkflowV1.Budget
open WorkflowV1.Reducer
open WorkflowV1.Recovery
open WorkflowV1.Storage
open WorkflowV1.Actions

// Proof bodies discharged by F*. These establish consequences of the
// abstract definitions and the explicit contract premises they receive.
let rec lemma_driver_trace_preserves_invariant (#b:Type0)
    (contract:driver_contract b) (before after:b)
    (trace:backend_trace b contract.call_step contract.autonomous_step
       before after)
    (valid:contract.backend_invariant before)
  : Lemma (contract.backend_invariant after) (decreases trace) =
  match trace with
  | BackendTraceRefl _ -> valid
  | BackendTraceCall prior next call request evidence step ->
      contract.call_preserves_invariant prior call request evidence next
  | BackendTraceAutonomous prior next step ->
      contract.autonomous_preserves_invariant prior next
  | BackendTraceTrans prior middle next first second ->
      lemma_driver_trace_preserves_invariant contract prior middle first valid;
      lemma_driver_trace_preserves_invariant contract middle next second ();
      ()

let lemma_driver_trace_keeps_per_key_effect_bound (#b:Type0)
    (contract:driver_contract b) (before after:b) (key:operation_key)
    (trace:backend_trace b contract.call_step contract.autonomous_step
       before after)
    (valid:contract.backend_invariant before)
  : Lemma (contract.effect_count after key <= 1) =
  lemma_driver_trace_preserves_invariant contract before after trace valid;
  contract.per_key_effect_bound after

// The abstract backend contract constrains behavior; this simulation is the
// separate obligation that connects those laws to an actual host driver.

let rec lemma_committed_child_count_append (events:list event)
    (event:event) : Lemma
      (committed_child_count (events @ [event]) ==
       committed_child_count events + event_committed_child_count event.body)
    (decreases events) =
  match events with
  | [] -> ()
  | _::rest -> lemma_committed_child_count_append rest event


let rec lemma_retry_permission_requires_event (key:operation_key)
    (events:list event)
    (permission:retry_permission_after key false events == true)
  : Lemma (not_applied_event_for_key key events == true)
    (decreases events) =
  match events with
  | [] -> ()
  | e::rest ->
      (match e.body with
       | NotApplied call _ ->
           if operation_key_eq call.call_key key &&
              call.call_kind = Reconcile then ()
           else lemma_retry_permission_requires_event key rest permission
       | _ -> lemma_retry_permission_requires_event key rest permission)


let lemma_append_event_history_exact (state:journal_state)
    (rules:admission_contract) (event:event) (next:journal_state)
    (appended:append_event state rules event == Some next)
  : Lemma (next.history == state.history @ [event]) =
  ()

let rec lemma_append_snoc_cons (#a:Type0) (xs:list a) (x:a) (ys:list a)
  : Lemma ((xs @ [x]) @ ys == xs @ (x :: ys)) (decreases xs) =
  match xs with
  | [] -> ()
  | _::rest -> lemma_append_snoc_cons rest x ys

let rec lemma_replay_history_exact (initial:journal_state)
    (rules:admission_contract) (events:list event) (final:journal_state)
    (replayed:replay_events initial rules events == Some final)
  : Lemma (final.history == initial.history @ events)
    (decreases events) =
  match events with
  | [] -> ()
  | event::rest ->
      (match append_event initial rules event with
       | None -> ()
       | Some next ->
           lemma_append_event_history_exact initial rules event next ();
           lemma_replay_history_exact next rules rest final replayed;
           assert (next.history == initial.history @ [event]);
           assert (final.history == next.history @ rest);
           assert (final.history == (initial.history @ [event]) @ rest);
           lemma_append_snoc_cons initial.history event rest;
           assert (final.history == initial.history @ (event :: rest));
           ())


let lemma_restored_state_is_exact_replay
    (initial:journal_state) (rules:admission_contract)
    (events:list event) (state:journal_state)
    (restored:restore_from_events initial rules (Loaded events) == Restored state)
  : Lemma (state.history == initial.history @ events) =
  match replay_events initial rules events with
  | None -> ()
  | Some replayed ->
      lemma_replay_history_exact initial rules events replayed ();
      assert (state == replayed);
      ()


let lemma_uncertain_append_blocks_next_transition (#store:Type0)
    (after:store) : Lemma
      (semantic_transition_allowed
        (phase_after_append (AppendUncertain after)) == false) =
  ()


let lemma_unpublished_artifact_is_hidden (#store:Type0)
    (contract:artifact_store_contract store) (state:store)
    (events:list event) (reference:artifact_ref)
    (unpublished:artifact_visible_in_history reference events == false)
  : Lemma (resolve_published_artifact contract state events reference ==
      ArtifactUnavailable) =
  ()


let lemma_local_completion_disables_invocation
    (state:journal_state) (where:occurrence) (input output:bytes)
    (completion:local_completion_for where state.history == Some (input, output))
  : Lemma (action_for_local state where input == ReuseCheckedCompletion output) =
  ()

let lemma_committed_expansion_disables_chooser
    (state:journal_state) (where:occurrence) (committed:expand_committed)
    (commit:expansion_for where state.history == Some committed)
  : Lemma (chooser_enabled
      (action_for_expand state where committed.committed_input) == false) =
  ()

let lemma_children_require_committed_manifest
    (state:journal_state) (parent:occurrence) (ordinal:nat)
    (source resolved:plan_id)
    (enabled:child_action_enabled state parent ordinal source resolved == true)
  : Lemma (committed_child parent ordinal source resolved state.history) =
  ()

let lemma_incomplete_manifest_child_is_ready
    (state:journal_state) (parent:occurrence) (ordinal:nat)
    (source resolved:plan_id)
    (manifest:committed_child parent ordinal source resolved state.history == true)
    (unfinished:not (completion_seen
       (manifest_child_occurrence parent ordinal source resolved)
       state.history) == true)
  : Lemma (child_action_enabled state parent ordinal source resolved == true) =
  ()

let lemma_join_completion_disables_join
    (state:journal_state) (where:occurrence) (completed:expansion_completed)
    (is_completion:expansion_completion_for where state.history == Some completed)
  : Lemma (join_enabled state where == false) =
  ()

let lemma_terminal_occurrence_disables_driver
    (state:journal_state) (rules:admission_contract) (call:call_id)
    (terminal:operation_terminal_seen call.call_key.key_occurrence
      state.history == true)
  : Lemma (driver_authorized state rules call == false) =
  ()

let lemma_append_preserves_budget_projection
    (state:journal_state) (rules:admission_contract) (event:event)
    (next:journal_state)
    (appended:append_event state rules event == Some next)
  : Lemma (ledger_matches_history next.header next.history next.ledger == true) =
  ()

let lemma_append_preserves_expansion_budget
    (state:journal_state) (rules:admission_contract) (event:event)
    (next:journal_state)
    (accounting:state.expansion_nodes_remaining +
       committed_child_count state.history == state.header.header_initial_nodes)
    (appended:append_event state rules event == Some next)
  : Lemma (next.expansion_nodes_remaining +
       committed_child_count next.history == state.header.header_initial_nodes) =
  lemma_append_event_history_exact state rules event next appended;
  lemma_committed_child_count_append state.history event;
  match event.body with
  | ExpansionCommitted committed ->
      assert (next.expansion_nodes_remaining ==
        state.expansion_nodes_remaining -
          length committed.committed_manifest);
      assert (length committed.committed_manifest <=
        state.expansion_nodes_remaining);
      ()
  | _ -> ()

let rec lemma_replay_preserves_expansion_budget
    (initial:journal_state) (rules:admission_contract)
    (events:list event) (final:journal_state)
    (initial_accounting:initial.expansion_nodes_remaining +
       committed_child_count initial.history ==
         initial.header.header_initial_nodes)
    (replayed:replay_events initial rules events == Some final)
  : Lemma (final.expansion_nodes_remaining +
       committed_child_count final.history ==
         initial.header.header_initial_nodes)
    (decreases events) =
  match events with
  | [] ->
      assert (final == initial);
      initial_accounting
  | event::rest ->
      (match append_event initial rules event with
       | None -> ()
       | Some next ->
           lemma_append_preserves_expansion_budget initial rules event next
             initial_accounting ();
           lemma_replay_preserves_expansion_budget next rules rest final ()
             replayed)

let lemma_completed_operation_reused
    (state:journal_state) (where:occurrence) (completed:operation_completed)
    (saved:operation_completion_for where state.history == Some completed)
  : Lemma (action_for_external state where completed.completed_input ==
       ReuseOperationTerminal completed) =
  ()

let lemma_accepted_generation_has_semantics
    (rules:generation_verifier) (prepared:expand_prepared)
    (committed:expand_committed)
    (accepted:rules.accepts_generation prepared committed == true)
  : Lemma (generation_semantics rules.generation prepared committed) =
  rules.acceptance_sound prepared committed

let lemma_legal_expansion_commit_has_semantics
    (state:journal_state) (rules:generation_verifier)
    (prepared:expand_prepared) (committed:expand_committed)
    (is_prepared:preparation_for committed.committed_at state.history ==
       Some prepared)
    (is_legal:legal_expansion_commit state rules committed == true)
  : Lemma (generation_semantics rules.generation prepared committed) =
  assert (rules.accepts_generation prepared committed == true);
  lemma_accepted_generation_has_semantics rules prepared committed ()
