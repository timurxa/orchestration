module WorkflowV1.OperationFacts
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Operations
open WorkflowV1.JournalTypes

let rec call_limit_count (kind:call_kind)
    (limits:list call_budget) : Tot nat (decreases limits) =
  match limits with
  | [] -> 0
  | entry::rest ->
      (if call_kind_eq kind entry.budgeted_kind then 1 else 0) +
      call_limit_count kind rest

let rec call_limit (kind:call_kind)
    (limits:list call_budget) : Tot (option nat) (decreases limits) =
  match limits with
  | [] -> None
  | entry::rest ->
      if call_kind_eq kind entry.budgeted_kind
      then Some entry.budgeted_maximum_charge
      else call_limit kind rest

let rec call_count_limit (kind:call_kind)
    (limits:list call_budget) : Tot (option nat) (decreases limits) =
  match limits with
  | [] -> None
  | entry::rest ->
      if call_kind_eq kind entry.budgeted_kind
      then Some entry.budgeted_maximum_calls
      else call_count_limit kind rest

let valid_call_limits (limits:list call_budget) : bool =
  length limits = 5 &&
  call_limit_count Dispatch limits = 1 &&
  call_limit_count Redelivery limits = 1 &&
  call_limit_count Reconcile limits = 1 &&
  call_limit_count Poll limits = 1 &&
  call_limit_count Cancel limits = 1

let prepared_operation_relation (p:operation_prepared) : prop =
  p.prepared_key.key_request_bytes == p.prepared_request /\
  occurrence_eq p.prepared_key.key_occurrence p.prepared_operation_at /\
  p.prepared_key.key_operation_build == p.prepared_operation_build /\
  p.prepared_key.key_validator_id == p.prepared_validator_id /\
  p.prepared_key.key_validator_version == p.prepared_validator_version /\
  p.prepared_key.key_validator_build == p.prepared_validator_build /\
  p.prepared_key.key_driver_id == p.prepared_driver_id /\
  p.prepared_key.key_driver_version == p.prepared_driver_version /\
  p.prepared_key.key_driver_build == p.prepared_driver_build /\
  p.prepared_key.key_driver_contract_id == p.prepared_driver_contract_id /\
  p.prepared_key.key_driver_contract_version ==
    p.prepared_driver_contract_version /\
  p.prepared_key.key_driver_contract_build ==
    p.prepared_driver_contract_build /\
  p.prepared_key.key_config_id == p.prepared_config_id /\
  p.prepared_key.key_attempt < p.prepared_maximum_attempts /\
  valid_call_limits p.prepared_call_limits

let validated_operation_terminal (p:operation_prepared)
    (c:operation_completed) : prop =
  operation_key_eq p.prepared_key c.completed_key /\
  p.prepared_request == c.completed_input /\
  operation_key_eq c.terminal_evidence_call.call_key c.completed_key

let correlated_evidence (p:operation_prepared) (e:evidence_record) : prop =
  operation_key_eq e.evidence_call.call_key p.prepared_key /\
  e.evidence_call.call_key.key_request_bytes == p.prepared_request


let same_operation_family (left:operation_key) (right:operation_key) : bool =
  left.key_run_id = right.key_run_id &&
  left.key_plan_id = right.key_plan_id &&
  occurrence_eq left.key_occurrence right.key_occurrence &&
  left.key_operation_id = right.key_operation_id &&
  left.key_operation_version = right.key_operation_version &&
  left.key_operation_build = right.key_operation_build &&
  left.key_validator_id = right.key_validator_id &&
  left.key_validator_version = right.key_validator_version &&
  left.key_validator_build = right.key_validator_build &&
  left.key_driver_id = right.key_driver_id &&
  left.key_driver_version = right.key_driver_version &&
  left.key_driver_build = right.key_driver_build &&
  left.key_driver_contract_id = right.key_driver_contract_id &&
  left.key_driver_contract_version = right.key_driver_contract_version &&
  left.key_driver_contract_build = right.key_driver_contract_build &&
  left.key_config_id = right.key_config_id &&
  left.key_resource_digest = right.key_resource_digest &&
  left.key_request_bytes = right.key_request_bytes

let rec latest_preparation_for_family (key:operation_key)
    (events:list event) : option operation_prepared =
  match events with
  | [] -> None
  | e::rest ->
      (match latest_preparation_for_family key rest with
       | Some previous -> Some previous
       | None ->
           match e.body with
           | OperationPrepared p ->
               if same_operation_family p.prepared_key key then Some p else None
           | _ -> None)

let rec retry_permission_after (key:operation_key) (enabled:bool)
    (events:list event) : Tot bool (decreases events) =
  match events with
  | [] -> enabled
  | e::rest ->
      (match e.body with
       | CallReserved call _ ->
           retry_permission_after key
             (if operation_key_eq call.call_key key then false else enabled)
             rest
       | NotApplied call _ ->
           retry_permission_after key
             (if operation_key_eq call.call_key key then
                call.call_kind = Reconcile
              else enabled)
             rest
       | _ -> retry_permission_after key enabled rest)

let not_applied_evidence_for_key (key:operation_key)
    (events:list event) : bool =
  retry_permission_after key false events

let valid_next_attempt (p:operation_prepared) (events:list event) : prop =
  p.prepared_key.key_attempt < p.prepared_maximum_attempts /\
  (match latest_preparation_for_family p.prepared_key events with
   | None -> p.prepared_key.key_attempt == 0
   | Some previous ->
       p.prepared_key.key_attempt == previous.prepared_key.key_attempt + 1 /\
       not_applied_evidence_for_key previous.prepared_key events)

let rec call_reservation_count (key:operation_key) (kind:call_kind)
    (events:list event) : Tot nat (decreases events) =
  match events with
  | [] -> 0
  | e::rest ->
      let earlier = call_reservation_count key kind rest in
      match e.body with
      | CallReserved call _ ->
          if operation_key_eq call.call_key key &&
             call_kind_eq call.call_kind kind
          then earlier + 1 else earlier
      | _ -> earlier

let call_kind_reserved (key:operation_key) (kind:call_kind)
    (events:list event) : bool =
  call_reservation_count key kind events > 0

let call_transition_relation (p:operation_prepared) (call:call_id)
    (events:list event) : prop =
  operation_key_eq p.prepared_key call.call_key /\
  (match call_count_limit call.call_kind p.prepared_call_limits with
   | None -> False
   | Some maximum_calls ->
       call.call_ordinal < maximum_calls /\
       call.call_ordinal == call_reservation_count p.prepared_key
         call.call_kind events /\
       (match call.call_kind with
        | Dispatch -> not (call_kind_reserved p.prepared_key Dispatch events)
        | Redelivery ->
            call_kind_reserved p.prepared_key Dispatch events /\
            (match p.prepared_replay_policy with
             | ReconcileOnly -> False
             | SameKeyIdempotent -> True
             | ReconcileBeforeRedelivery ->
                 not_applied_evidence_for_key p.prepared_key events)
        | Reconcile | Poll ->
            call_kind_reserved p.prepared_key Dispatch events
        | Cancel ->
            p.prepared_supports_cancel /\
            call_kind_reserved p.prepared_key Dispatch events))
