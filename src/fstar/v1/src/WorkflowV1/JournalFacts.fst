module WorkflowV1.JournalFacts
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Artifacts
open WorkflowV1.Operations
open WorkflowV1.Expansion
open WorkflowV1.JournalTypes
open WorkflowV1.OperationFacts

let rec artifact_reference_named (reference:artifact_ref)
    (references:list artifact_ref) : bool =
  match references with
  | [] -> false
  | candidate::rest -> candidate = reference ||
      artifact_reference_named reference rest

let rec artifact_visible_in_history (reference:artifact_ref)
    (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      let here = match e.body with
        | OperationCompleted completed ->
            completed.completed_terminal_tag = AcceptedTerminal &&
            artifact_reference_named reference completed.published_artifacts
        | _ -> false in
      here || artifact_visible_in_history reference rest

let rec committed_child_count (events:list event) : nat =
  match events with
  | [] -> 0
  | e::rest ->
      (match e.body with
       | ExpansionCommitted committed ->
           length committed.committed_manifest + committed_child_count rest
       | _ -> committed_child_count rest)

let event_committed_child_count (body:event_body) : nat =
  match body with
  | ExpansionCommitted committed -> length committed.committed_manifest
  | _ -> 0


let rec event_id_seen (event_id:string) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest -> e.event_id = event_id || event_id_seen event_id rest

let rec completion_seen (where:occurrence) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      let here = match e.body with
        | LocalCompleted at _ _ _ _ _ -> occurrence_eq at where
        | OperationCompleted c -> occurrence_eq c.completed_operation_at where
        | ExpansionCompleted c ->
            occurrence_eq c.expansion_completed_at where
        | NodeFailed at _ -> occurrence_eq at where
        | _ -> false in
      here || completion_seen where rest

let rec preparation_for (where:occurrence) (events:list event)
  : option expand_prepared =
  match events with
  | [] -> None
  | e::rest ->
      (match preparation_for where rest with
       | Some p -> Some p
       | None ->
           match e.body with
           | ExpandPrepared p ->
               if occurrence_eq p.prepared_at where then Some p else None
           | _ -> None)

let rec expansion_for (where:occurrence) (events:list event)
  : option expand_committed =
  match events with
  | [] -> None
  | e::rest ->
      (match expansion_for where rest with
       | Some c -> Some c
       | None ->
           match e.body with
           | ExpansionCommitted c ->
               if occurrence_eq c.committed_at where then Some c else None
           | _ -> None)

let rec expansion_completion_for (where:occurrence) (events:list event)
    : option expansion_completed =
  match events with
  | [] -> None
  | e::rest ->
      (match expansion_completion_for where rest with
       | Some c -> Some c
       | None ->
           match e.body with
           | ExpansionCompleted c ->
               if occurrence_eq c.expansion_completed_at where then Some c
               else None
           | _ -> None)

let rec call_reserved (call:call_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | CallReserved old _ -> call_id_eq old call
       | _ -> call_reserved call rest)

let rec reservation_maximum (call:call_id) (events:list event)
    : option nat =
  match events with
  | [] -> None
  | e::rest ->
      (match e.body with
       | CallReserved old maximum ->
           if call_id_eq old call then Some maximum
           else reservation_maximum call rest
       | _ -> reservation_maximum call rest)

let rec call_settled (call:call_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | CallSettled old _ _ -> call_id_eq old call || call_settled call rest
       | _ -> call_settled call rest)

let rec call_may_have_been_sent (call:call_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | DispatchMayHaveBeenSent old -> call_id_eq old call
       | _ -> call_may_have_been_sent call rest)

let rec call_may_have_been_sent_in_epoch (call:call_id) (epoch:nat)
    (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | DispatchMayHaveBeenSent old ->
           (call_id_eq old call && e.epoch = epoch) ||
           call_may_have_been_sent_in_epoch call epoch rest
       | _ -> call_may_have_been_sent_in_epoch call epoch rest)

let rec operation_evidence_seen (call:call_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | CallEvidence evidence -> call_id_eq evidence.evidence_call call
       | _ -> operation_evidence_seen call rest)

let rec final_call_evidence_seen (call:call_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | CallEvidence evidence ->
           (call_id_eq evidence.evidence_call call && evidence.evidence_final) ||
           final_call_evidence_seen call rest
       | _ -> final_call_evidence_seen call rest)

let rec final_call_charge (call:call_id) (events:list event)
    : option nat =
  match events with
  | [] -> None
  | e::rest ->
      (match e.body with
       | CallEvidence evidence ->
           if call_id_eq evidence.evidence_call call && evidence.evidence_final
           then evidence.evidence_charge
           else final_call_charge call rest
       | _ -> final_call_charge call rest)

let rec not_applied_event_seen (call:call_id) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | NotApplied old _ -> call_id_eq old call ||
           not_applied_event_seen call rest
       | _ -> not_applied_event_seen call rest)

let rec not_applied_event_for_key (key:operation_key)
    (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | NotApplied call _ ->
           (operation_key_eq call.call_key key &&
            call.call_kind = Reconcile) ||
           not_applied_event_for_key key rest
       | _ -> not_applied_event_for_key key rest)


let rec timeout_generation (call:call_id) (events:list event) : nat =
  match events with
  | [] -> 0
  | e::rest ->
      (match e.body with
       | TimeoutEnabled old _ _ ->
           (if call_id_eq old call then 1 else 0) +
             timeout_generation call rest
       | _ -> timeout_generation call rest)

let rec timeout_enabled_for (call:call_id) (generation:nat)
    (events:list event) : option nat =
  match events with
  | [] -> None
  | e::rest ->
      (match e.body with
       | TimeoutEnabled old deadline old_generation ->
           if call_id_eq old call && old_generation = generation
           then Some deadline
           else timeout_enabled_for call generation rest
       | _ -> timeout_enabled_for call generation rest)

let rec timeout_unknown_seen (call:call_id) (generation:nat)
    (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | OperationUnknown old _ old_generation _ _ ->
           (call_id_eq old call && old_generation = generation) ||
           timeout_unknown_seen call generation rest
       | _ -> timeout_unknown_seen call generation rest)

let rec operation_preparation (key:operation_key) (events:list event)
    : option operation_prepared =
  match events with
  | [] -> None
  | e::rest ->
      (match e.body with
       | OperationPrepared p ->
           if operation_key_eq p.prepared_key key then Some p
           else operation_preparation key rest
       | _ -> operation_preparation key rest)

let rec preparation_at_occurrence (where:occurrence) (events:list event)
    : option operation_prepared =
  match events with
  | [] -> None
  | e::rest ->
      (match preparation_at_occurrence where rest with
       | Some p -> Some p
       | None ->
           match e.body with
           | OperationPrepared p ->
               if occurrence_eq p.prepared_operation_at where then Some p
               else None
           | _ -> None)

let rec operation_terminal_seen (where:occurrence) (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      (match e.body with
       | OperationCompleted c ->
           occurrence_eq c.completed_operation_at where ||
           operation_terminal_seen where rest
       | _ -> operation_terminal_seen where rest)

let rec artifact_refs_equal (candidates:list artifact_ref)
    (references:list artifact_ref) : bool =
  match candidates, references with
  | [], [] -> true
  | candidate::candidate_tail, reference::reference_tail ->
      candidate = reference &&
      artifact_refs_equal candidate_tail reference_tail
  | _, _ -> false

let rec terminal_evidence_event (event_id:string) (call:call_id)
    (terminal_bytes:bytes) (published:list artifact_ref)
    (events:list event) : bool =
  match events with
  | [] -> false
  | e::rest ->
      if e.event_id <> event_id then
        terminal_evidence_event event_id call terminal_bytes published rest
      else
        (match e.body with
         | CallEvidence evidence ->
             call_id_eq evidence.evidence_call call &&
             evidence.evidence_final &&
             evidence.evidence_disposition <> None &&
             evidence.evidence_terminal_bytes = Some terminal_bytes &&
             artifact_refs_equal evidence.evidence_artifacts published
         | _ -> false)

let rec terminal_evidence_record (event_id:string)
    (events:list event) : option evidence_record =
  match events with
  | [] -> None
  | e::rest ->
      if e.event_id <> event_id then terminal_evidence_record event_id rest
      else
        (match e.body with
         | CallEvidence evidence -> Some evidence
         | _ -> None)
