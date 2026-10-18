module WorkflowV1.Protocol
open FStar.List.Tot
open WorkflowV1.Base

type call_kind =
  | Dispatch
  | Redelivery
  | Reconcile
  | Poll
  | Cancel

type call_budget = {
  budgeted_kind:call_kind;
  budgeted_maximum_calls:nat;
  budgeted_maximum_charge:nat
}

type replay_policy =
  | ReconcileOnly
  | SameKeyIdempotent
  | ReconcileBeforeRedelivery

let call_kind_eq (left:call_kind) (right:call_kind) : bool =
  match left, right with
  | Dispatch, Dispatch -> true
  | Redelivery, Redelivery -> true
  | Reconcile, Reconcile -> true
  | Poll, Poll -> true
  | Cancel, Cancel -> true
  | _, _ -> false

type operation_key = {
  key_run_id:run_id;
  key_plan_id:plan_id;
  key_occurrence:occurrence;
  key_attempt:nat;
  key_operation_id:code_id;
  key_operation_version:nat;
  key_operation_build:digest;
  key_validator_id:code_id;
  key_validator_version:nat;
  key_validator_build:digest;
  key_driver_id:code_id;
  key_driver_version:nat;
  key_driver_build:digest;
  key_driver_contract_id:code_id;
  key_driver_contract_version:nat;
  key_driver_contract_build:digest;
  key_config_id:code_id;
  key_resource_digest:digest;
  key_request_bytes:bytes
}

type call_id = {
  call_key:operation_key;
  call_kind:call_kind;
  call_ordinal:nat
}

type operation_context = {
  context_key:operation_key;
  context_call:call_id
}

let operation_key_eq (left:operation_key) (right:operation_key) : bool =
  left.key_run_id = right.key_run_id && left.key_plan_id = right.key_plan_id &&
  occurrence_eq left.key_occurrence right.key_occurrence &&
  left.key_attempt = right.key_attempt &&
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

let call_id_eq (left:call_id) (right:call_id) : bool =
  left.call_ordinal = right.call_ordinal &&
  call_kind_eq left.call_kind right.call_kind &&
  operation_key_eq left.call_key right.call_key

type effect_disposition =
  | Applied
  | DefinitelyNotApplied

noeq type accepted_at (i:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop)
    (x:i) (context:operation_context) = {
  accepted_value:o x;
  accepted_proof:valid x context accepted_value
}

noeq type terminal (i:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop) (x:i) =
  | Accepted : context:operation_context
      -> accepted_at i o valid x context
      -> effect_disposition -> terminal i o valid x
  | Rejected : operation_context -> bytes -> effect_disposition
      -> terminal i o valid x
  | Failed : operation_context -> bytes -> effect_disposition
      -> terminal i o valid x
  | Cancelled : operation_context -> bytes -> effect_disposition
      -> terminal i o valid x

let terminal_context (#i:Type0) (#o:(i -> Type0))
    (#valid:(x:i) -> operation_context -> o x -> prop)
    (#x:i) (t:terminal i o valid x) : operation_context =
  match t with
  | Accepted context _ _ -> context
  | Rejected context _ _ -> context
  | Failed context _ _ -> context
  | Cancelled context _ _ -> context

type terminal_at (i:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop)
    (x:i) (context:operation_context) =
  t:terminal i o valid x{terminal_context t == context}

type artifact_ref = {
  artifact_digest:digest;
  artifact_schema:code_id;
  artifact_schema_version:nat;
  artifact_size:nat;
  artifact_source:occurrence;
  artifact_source_call:option call_id;
  artifact_parents:list digest
}

type artifact_schema = code_id & nat
