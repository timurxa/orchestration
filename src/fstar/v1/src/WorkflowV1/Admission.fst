module WorkflowV1.Admission
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Operations
open WorkflowV1.Work
open WorkflowV1.Expansion
open WorkflowV1.JournalTypes
open WorkflowV1.OperationFacts
open WorkflowV1.JournalFacts
open WorkflowV1.Contracts

let admission_matches_header (state:journal_state)
    (rules:admission_contract) : bool =
  state.header.header_admission_id = rules.admission_id &&
  state.header.header_admission_version = rules.admission_version &&
  state.header.header_admission_build = rules.admission_build &&
  state.header.header_registry_id =
    rules.work_registry.code_registry.registry_id &&
  state.header.header_registry_version =
    rules.work_registry.code_registry.registry_version &&
  state.header.header_registry_build =
    rules.work_registry.code_registry.registry_build

let rec committed_child (parent:occurrence) (ordinal:nat)
    (source resolved:plan_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      let here = match e.body with
        | ExpansionCommitted c ->
            if occurrence_eq c.committed_at parent then
              (let rec member (xs:list child_manifest_entry) : bool =
                 match xs with
                 | [] -> false
                 | x::tail ->
                     (x.ordinal = ordinal && x.source_id = source &&
                      x.resolved_id = resolved) || member tail in
               member c.committed_manifest)
            else false
        | _ -> false in
      here || committed_child parent ordinal source resolved rest

let rec successful_node_result (where:occurrence) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      let here = match e.body with
        | LocalCompleted at _ _ _ _ _ -> occurrence_eq at where
        | OperationCompleted c -> occurrence_eq c.completed_operation_at where
        | ExpansionCompleted c -> occurrence_eq c.expansion_completed_at where
        | ExpansionCommitted c ->
            occurrence_eq c.committed_at where &&
            Option.isSome c.committed_direct_result
        | _ -> false in
      here || successful_node_result where rest

let rec manifest_children_completed (parent:occurrence)
    (entries:list child_manifest_entry) (events:list event) : bool =
  match entries with
  | [] -> true
  | entry::rest ->
      let child = { parent with
        plan_id=entry.resolved_id;
        path=parent.path @ [ExpandChild entry.ordinal entry.source_id
          entry.resolved_id] } in
      successful_node_result child events &&
      manifest_children_completed parent rest events

let rec prep_matches (p:expand_prepared) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | ExpandPrepared old ->
           occurrence_eq old.prepared_at p.prepared_at &&
           old.prepared_input = p.prepared_input &&
           old.prepared_input_digest = p.prepared_input_digest &&
           old.prepared_snapshot = p.prepared_snapshot &&
           old.prepared_snapshot_digest = p.prepared_snapshot_digest &&
           old.prepared_expand_id = p.prepared_expand_id &&
           old.prepared_expand_version = p.prepared_expand_version &&
           old.prepared_expand_build = p.prepared_expand_build &&
           old.prepared_decoder_id = p.prepared_decoder_id &&
           old.prepared_decoder_version = p.prepared_decoder_version &&
           old.prepared_decoder_build = p.prepared_decoder_build &&
           old.prepared_checker_id = p.prepared_checker_id &&
           old.prepared_checker_version = p.prepared_checker_version &&
           old.prepared_checker_build = p.prepared_checker_build &&
           old.prepared_registry_id = p.prepared_registry_id &&
           old.prepared_registry_version = p.prepared_registry_version &&
           old.prepared_registry_build = p.prepared_registry_build &&
           old.prepared_join_id = p.prepared_join_id &&
           old.prepared_join_version = p.prepared_join_version &&
           old.prepared_join_build = p.prepared_join_build &&
           old.prepared_maximum_children = p.prepared_maximum_children &&
           old.prepared_depth = p.prepared_depth &&
           old.prepared_nodes = p.prepared_nodes
       | _ -> prep_matches p rest)

let legal_expansion_commit (state:journal_state) (g:generation_verifier)
    (c:expand_committed) : bool =
  match preparation_for c.committed_at state.history with
  | None -> false
  | Some p ->
      prep_matches p state.history &&
      occurrence_eq p.prepared_at c.committed_at &&
      p.prepared_input = c.committed_input &&
      p.prepared_snapshot = c.committed_snapshot &&
      not (Option.isSome (expansion_for c.committed_at state.history)) &&
      g.accepts_generation p c &&
      valid_generation g.generation p c &&
      valid_manifest_shape p.prepared_maximum_children p.prepared_depth
        state.expansion_nodes_remaining c.committed_manifest &&
      c.committed_nodes_after =
        state.expansion_nodes_remaining - length c.committed_manifest &&
      c.committed_child_depth =
        (match c.committed_manifest with
         | [] -> p.prepared_depth
         | _::_ -> p.prepared_depth - 1)

let operation_limit (rules:operation_verifier) (key:operation_key)
    (kind:call_kind) (events:list event) : option nat =
  match operation_preparation key events with
  | None -> None
  | Some p ->
      if not (rules.preparation_valid p) then None
      else call_limit kind p.prepared_call_limits

let driver_authorized (state:journal_state) (rules:admission_contract)
    (call:call_id) : bool =
  admission_matches_header state rules &&
  call_reserved call state.history &&
  call_may_have_been_sent_in_epoch call state.current_epoch state.history &&
  not (operation_evidence_seen call state.history) &&
  not (call_settled call state.history) &&
  not (operation_terminal_seen call.call_key.key_occurrence state.history) &&
  not state.ledger.budget_quarantined &&
  (match operation_preparation call.call_key state.history with
   | None -> false
   | Some p ->
       rules.operation_rules.preparation_valid p &&
       operation_limit rules.operation_rules call.call_key call.call_kind
         state.history = reservation_maximum call state.history)

noeq type authorized_driver_call (state:journal_state)
    (rules:admission_contract) (call:call_id) = {
  authorized_call:call_id;
  authorization_proof:driver_authorized state rules authorized_call == true;
  exact_requested_call:authorized_call == call
}

let authorize_driver (state:journal_state) (rules:admission_contract)
    (call:call_id) : option (authorized_driver_call state rules call) =
  if driver_authorized state rules call then
    Some { authorized_call=call;
           authorization_proof=();
           exact_requested_call=() }
  else None
