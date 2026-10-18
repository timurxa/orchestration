module WorkflowV1.JournalTypes
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Artifacts
open WorkflowV1.Operations
open WorkflowV1.Expansion

type operation_prepared = {
  prepared_operation_at:occurrence;
  prepared_key:operation_key;
  prepared_request:bytes;
  prepared_driver_id:code_id;
  prepared_driver_version:nat;
  prepared_driver_build:digest;
  prepared_driver_contract_id:code_id;
  prepared_driver_contract_version:nat;
  prepared_driver_contract_build:digest;
  prepared_config_id:code_id;
  prepared_operation_build:digest;
  prepared_validator_id:code_id;
  prepared_validator_version:nat;
  prepared_validator_build:digest;
  prepared_artifact_parent_digests:list digest;
  prepared_maximum_attempts:nat;
  prepared_replay_policy:replay_policy;
  prepared_supports_cancel:bool;
  prepared_artifact_policy:artifact_policy;
  prepared_call_limits:list call_budget
}

type terminal_tag =
  | AcceptedTerminal
  | RejectedTerminal
  | FailedTerminal
  | CancelledTerminal

type operation_completed = {
  completed_operation_at:occurrence;
  completed_key:operation_key;
  completed_input:bytes;
  completed_terminal_tag:terminal_tag;
  completed_terminal:bytes;
  terminal_evidence_call:call_id;
  terminal_evidence_event_id:string;
  published_artifacts:list artifact_ref
}


type event_body =
  | RunOpened : run_header -> event_body
  | EpochStarted : nat -> event_body
  | LocalCompleted : occurrence -> bytes -> code_id -> nat -> digest
      -> bytes -> event_body
  | ExpandPrepared : expand_prepared -> event_body
  | ExpansionCommitted : expand_committed -> event_body
  | ExpansionCompleted : expansion_completed -> event_body
  | OperationPrepared : operation_prepared -> event_body
  | CallReserved : call_id -> nat -> event_body
  | DispatchMayHaveBeenSent : call_id -> event_body
  | CallEvidence : evidence_record -> event_body
  | NotApplied : call_id -> bytes -> event_body
  | CallSettled : call_id -> nat -> bytes -> event_body
  | OperationCompleted : operation_completed -> event_body
  | TimeoutEnabled : call_id -> nat -> nat -> event_body
  | OperationUnknown : call_id -> nat -> nat -> nat -> bytes -> event_body
  | NodeFailed : occurrence -> bytes -> event_body

type event = {
  sequence:nat;
  event_id:string;
  epoch:nat;
  body:event_body
}


type budget = {
  budget_limit:nat;
  budget_spent:nat;
  budget_reserved:nat;
  budget_overage:nat;
  budget_quarantined:bool
}

let budget_valid (b:budget) : bool =
  b.budget_spent + b.budget_reserved <= b.budget_limit + b.budget_overage &&
  (b.budget_quarantined ||
    (b.budget_overage = 0 &&
     b.budget_spent + b.budget_reserved <= b.budget_limit))

let budget_invariant (b:budget) : prop = budget_valid b = true

type journal_state = {
  header:run_header;
  run_open:bool;
  current_epoch:nat;
  next_sequence:nat;
  history:list event;
  expansion_nodes_remaining:nat;
  ledger:budget
}

let empty_state (header:run_header) (epoch:nat) : journal_state = {
  header=header;
  run_open=false;
  current_epoch=epoch;
  next_sequence=1;
  history=[];
  expansion_nodes_remaining=header.header_initial_nodes;
  ledger={ budget_limit=header.header_budget_limit;
           budget_spent=0;
           budget_reserved=0;
           budget_overage=0;
           budget_quarantined=false }
}
