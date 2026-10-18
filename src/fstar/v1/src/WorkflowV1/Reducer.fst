module WorkflowV1.Reducer
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

let legal_event (state:journal_state) (rules:admission_contract)
    (body:event_body) : bool =
  if not (admission_matches_header state rules) then false else
  if not state.run_open then
    (match body with
     | RunOpened header ->
         state.history = [] && run_header_eq state.header header &&
         rules.root_header_valid header
     | _ -> false)
  else match body with
  | RunOpened _ -> false
  | EpochStarted next_epoch -> next_epoch > state.current_epoch
  | LocalCompleted where input id version build output ->
      rules.occurrence_valid state where &&
      not (completion_seen where state.history) &&
      rules.completion_rules.local_valid where input id version build output
  | ExpandPrepared p ->
      rules.occurrence_valid state p.prepared_at &&
      not (completion_seen p.prepared_at state.history) &&
      Option.isNone (preparation_for p.prepared_at state.history) &&
      Option.isNone (expansion_for p.prepared_at state.history) &&
      p.prepared_nodes = state.expansion_nodes_remaining &&
      generation_is_pinned rules.generation_rules.generation p &&
      rules.generation_rules.preparation_valid state p
  | ExpansionCommitted c ->
      legal_expansion_commit state rules.generation_rules c
  | ExpansionCompleted c ->
      not (completion_seen c.expansion_completed_at state.history) &&
      (match expansion_for c.expansion_completed_at state.history with
       | None -> false
       | Some manifest ->
           manifest.committed_direct_result = None &&
           manifest_children_completed c.expansion_completed_at
             manifest.committed_manifest state.history &&
           rules.completion_rules.expansion_join_valid manifest
             state.history c.expansion_result)
  | OperationPrepared p ->
      rules.occurrence_valid state p.prepared_operation_at &&
      not (completion_seen p.prepared_operation_at state.history) &&
      Option.isNone (operation_preparation p.prepared_key state.history) &&
      rules.operation_rules.preparation_valid p &&
      rules.request_matches_work_input state p &&
      valid_call_limits p.prepared_call_limits &&
      rules.operation_rules.attempt_valid p state.history &&
      (match preparation_at_occurrence p.prepared_operation_at state.history with
       | None -> p.prepared_key.key_attempt = 0
       | Some previous ->
           same_operation_family previous.prepared_key p.prepared_key) &&
      occurrence_eq p.prepared_key.key_occurrence p.prepared_operation_at &&
      p.prepared_key.key_run_id = p.prepared_operation_at.run_id &&
      p.prepared_key.key_plan_id = p.prepared_operation_at.plan_id &&
      p.prepared_key.key_operation_build = p.prepared_operation_build &&
      p.prepared_key.key_validator_id = p.prepared_validator_id &&
      p.prepared_key.key_validator_version = p.prepared_validator_version &&
      p.prepared_key.key_validator_build = p.prepared_validator_build &&
      p.prepared_key.key_driver_id = p.prepared_driver_id &&
      p.prepared_key.key_driver_version = p.prepared_driver_version &&
      p.prepared_key.key_driver_build = p.prepared_driver_build &&
      p.prepared_key.key_driver_contract_id =
        p.prepared_driver_contract_id &&
      p.prepared_key.key_driver_contract_version =
        p.prepared_driver_contract_version &&
      p.prepared_key.key_driver_contract_build =
        p.prepared_driver_contract_build &&
      p.prepared_key.key_config_id = p.prepared_config_id
  | CallReserved call maximum ->
      not (call_reserved call state.history) &&
      not (operation_terminal_seen call.call_key.key_occurrence state.history) &&
      not state.ledger.budget_quarantined &&
      operation_limit rules.operation_rules call.call_key call.call_kind
        state.history = Some maximum &&
      (match operation_preparation call.call_key state.history with
       | None -> false
       | Some p ->
           rules.operation_rules.call_admissible p call state.history &&
           (match call_count_limit call.call_kind p.prepared_call_limits with
            | None -> false
            | Some cap -> call.call_ordinal < cap &&
                call.call_ordinal = call_reservation_count call.call_key
                  call.call_kind state.history)) &&
      state.ledger.budget_spent + state.ledger.budget_reserved + maximum <=
        state.ledger.budget_limit
  | DispatchMayHaveBeenSent call ->
      call_reserved call state.history &&
      not (call_may_have_been_sent call state.history) &&
      not state.ledger.budget_quarantined &&
      not (operation_terminal_seen call.call_key.key_occurrence state.history) &&
      Option.isSome (operation_preparation call.call_key state.history)
  | CallEvidence evidence ->
      call_may_have_been_sent evidence.evidence_call state.history &&
      not (final_call_evidence_seen evidence.evidence_call state.history) &&
      (not (operation_evidence_seen evidence.evidence_call state.history) ||
       evidence.evidence_final) &&
      (match operation_preparation evidence.evidence_call.call_key state.history with
       | None -> false
       | Some p ->
           rules.operation_rules.evidence_valid p evidence &&
           rules.operation_rules.artifact_evidence_valid p evidence)
  | NotApplied call proof_bytes ->
      call.call_kind = Reconcile &&
      final_call_evidence_seen call state.history &&
      not (not_applied_event_seen call state.history) &&
      (match operation_preparation call.call_key state.history with
       | None -> false
       | Some p ->
           rules.operation_rules.not_applied_valid p call proof_bytes
             state.history)
  | CallSettled call amount proof_bytes ->
      call_reserved call state.history &&
      operation_evidence_seen call state.history &&
      final_call_evidence_seen call state.history &&
      not (call_settled call state.history) &&
      (match reservation_maximum call state.history with
       | Some maximum -> state.ledger.budget_reserved >= maximum
       | None -> false) &&
      (match final_call_charge call state.history with
       | Some reported -> reported = amount
       | None -> true) &&
      rules.operation_rules.settlement_valid call amount proof_bytes
  | TimeoutEnabled call deadline generation ->
      call_may_have_been_sent call state.history &&
      not (final_call_evidence_seen call state.history) &&
      generation = timeout_generation call state.history &&
      deadline > 0
  | OperationUnknown call deadline generation observed_at proof_bytes ->
      call_may_have_been_sent call state.history &&
      not (final_call_evidence_seen call state.history) &&
      not (timeout_unknown_seen call generation state.history) &&
      timeout_enabled_for call generation state.history = Some deadline &&
      (match operation_preparation call.call_key state.history with
       | None -> false
       | Some p ->
           rules.operation_rules.timeout_expiry_valid call deadline
             generation observed_at proof_bytes)
  | OperationCompleted c ->
      not (completion_seen c.completed_operation_at state.history) &&
      operation_key_eq c.completed_key c.terminal_evidence_call.call_key &&
      occurrence_eq c.completed_operation_at c.completed_key.key_occurrence &&
      c.completed_input = c.completed_key.key_request_bytes &&
      (match operation_preparation c.completed_key state.history with
       | None -> false
       | Some p ->
           (match terminal_evidence_record c.terminal_evidence_event_id
                    state.history with
            | None -> false
            | Some evidence ->
                rules.operation_rules.terminal_valid p c evidence &&
                rules.completion_rules.artifact_commit_valid c state.history &&
                terminal_evidence_event c.terminal_evidence_event_id
                  c.terminal_evidence_call c.completed_terminal
                  c.published_artifacts state.history))
  | NodeFailed where _ ->
      rules.occurrence_valid state where &&
      not (completion_seen where state.history) &&
      Option.isNone (expansion_for where state.history)

let append_event (state:journal_state) (rules:admission_contract)
    (e:event) : option journal_state =
  if e.sequence <> state.next_sequence || e.epoch <> state.current_epoch ||
     event_id_seen e.event_id state.history ||
     not (budget_valid state.ledger) ||
     not (ledger_matches_history state.header state.history state.ledger) ||
     not (legal_event state rules e.body)
  then None
  else
    let nodes_after = match e.body with
      | ExpansionCommitted c -> c.committed_nodes_after
      | _ -> state.expansion_nodes_remaining in
    let ledger_after_result = match e.body with
      | CallReserved _ maximum ->
          Some (ledger_after_reservation state.ledger maximum)
      | CallSettled call amount _ ->
          (match reservation_maximum call state.history with
           | Some maximum -> ledger_after_settlement state.ledger maximum amount
           | None -> None)
      | _ -> Some state.ledger in
    (match ledger_after_result with
     | None -> None
     | Some ledger_after ->
         let epoch_after = match e.body with
           | EpochStarted next_epoch -> next_epoch
           | _ -> state.current_epoch in
         let open_after = match e.body with
           | RunOpened _ -> true
           | _ -> state.run_open in
         let next = {
           state with
           run_open=open_after;
           current_epoch=epoch_after;
           next_sequence=state.next_sequence + 1;
           history=state.history @ [e];
           expansion_nodes_remaining=nodes_after;
           ledger=ledger_after
         } in
         if budget_valid next.ledger &&
            ledger_matches_history next.header next.history next.ledger
         then Some next else None)

let rec replay_events (initial:journal_state) (rules:admission_contract)
    (events:list event) : Tot (option journal_state) (decreases events) =
  match events with
  | [] -> Some initial
  | event::rest ->
      (match append_event initial rules event with
       | None -> None
       | Some next -> replay_events next rules rest)
