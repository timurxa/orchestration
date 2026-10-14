module WorkflowV1.Contracts
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

type operation_identity = {
  identity_operation_id:code_id;
  identity_operation_version:nat;
  identity_operation_build:digest;
  identity_validator_id:code_id;
  identity_validator_version:nat;
  identity_validator_build:digest;
  identity_driver_id:code_id;
  identity_driver_version:nat;
  identity_driver_build:digest;
  identity_driver_contract_id:code_id;
  identity_driver_contract_version:nat;
  identity_driver_contract_build:digest;
  identity_effective_config_id:code_id
}

let prepared_identity_matches (identity:operation_identity)
    (p:operation_prepared) : prop =
  p.prepared_key.key_operation_id == identity.identity_operation_id /\
  p.prepared_key.key_operation_version == identity.identity_operation_version /\
  p.prepared_key.key_operation_build == identity.identity_operation_build /\
  p.prepared_key.key_validator_id == identity.identity_validator_id /\
  p.prepared_key.key_validator_version == identity.identity_validator_version /\
  p.prepared_key.key_validator_build == identity.identity_validator_build /\
  p.prepared_operation_build == identity.identity_operation_build /\
  p.prepared_validator_id == identity.identity_validator_id /\
  p.prepared_validator_version == identity.identity_validator_version /\
  p.prepared_validator_build == identity.identity_validator_build /\
  p.prepared_key.key_driver_id == identity.identity_driver_id /\
  p.prepared_key.key_driver_version == identity.identity_driver_version /\
  p.prepared_key.key_driver_build == identity.identity_driver_build /\
  p.prepared_key.key_driver_contract_id ==
    identity.identity_driver_contract_id /\
  p.prepared_key.key_driver_contract_version ==
    identity.identity_driver_contract_version /\
  p.prepared_key.key_driver_contract_build ==
    identity.identity_driver_contract_build /\
  p.prepared_config_id == identity.identity_effective_config_id

noeq type operation_verifier = {
  // Resolved per preparation so one run may contain different operations and
  // drivers while each occurrence still pins one exact implementation.
  pinned_identity:operation_prepared -> operation_identity;
  spec_maximum_charge:operation_prepared -> call_kind -> nat;
  spec_maximum_calls:operation_prepared -> call_kind -> nat;
  spec_maximum_attempts:operation_prepared -> nat;
  spec_replay_policy:operation_prepared -> replay_policy;
  spec_supports_cancel:operation_prepared -> bool;
  spec_artifact_policy:operation_prepared -> artifact_policy;
  hash_artifact_bytes:bytes -> Tot digest;
  check_artifact_schema:code_id -> nat -> bytes -> Tot bool;
  preparation_valid:operation_prepared -> Tot bool;
  preparation_sound:(p:operation_prepared) -> Lemma
    (preparation_valid p == true ==>
      prepared_operation_relation p /\
      prepared_identity_matches (pinned_identity p) p /\
      (forall kind. call_limit kind p.prepared_call_limits ==
         Some (spec_maximum_charge p kind)) /\
      (forall kind. call_count_limit kind p.prepared_call_limits ==
         Some (spec_maximum_calls p kind)) /\
      p.prepared_maximum_attempts == spec_maximum_attempts p /\
      p.prepared_replay_policy == spec_replay_policy p /\
      p.prepared_supports_cancel == spec_supports_cancel p /\
      p.prepared_artifact_policy == spec_artifact_policy p);
  attempt_valid:operation_prepared -> list event -> Tot bool;
  attempt_sound:(p:operation_prepared) -> (events:list event) -> Lemma
    (attempt_valid p events == true ==> valid_next_attempt p events);
  call_admissible:operation_prepared -> call_id -> list event -> Tot bool;
  call_sound:(p:operation_prepared) -> (call:call_id) -> (events:list event)
    -> Lemma (call_admissible p call events == true ==>
       call_transition_relation p call events);
  // This relation is instantiated by the pinned OpSpec codecs/validator.
  // For Accepted, it must decode the exact request and raw evidence, run
  // OpSpec.validate, encode the resulting indexed terminal, and establish
  // equality with completed_terminal. Other terminal tags need an equally
  // pinned classification proof. terminal_disposition_fact separately proves
  // the disposition belongs to the original operation effect, not a cancel
  // acknowledgement. A wire decode alone is insufficient.
  terminal_revalidation_fact:operation_prepared -> operation_completed
    -> evidence_record -> prop;
  terminal_disposition_fact:operation_prepared -> operation_completed
    -> evidence_record -> prop;
  terminal_valid:operation_prepared -> operation_completed
    -> evidence_record -> Tot bool;
  terminal_sound:(p:operation_prepared) -> (c:operation_completed)
    -> (e:evidence_record)
    -> Lemma (terminal_valid p c e == true ==>
       validated_operation_terminal p c /\
       terminal_revalidation_fact p c e /\
       terminal_disposition_fact p c e);
  evidence_valid:operation_prepared -> evidence_record -> Tot bool;
  // evidence_fact must be proved against the driver's backend trace model.
  // In particular, final Reconcile/DefinitelyNotApplied evidence must rule
  // out every future delayed application; a wire flag alone is insufficient.
  evidence_fact:operation_prepared -> evidence_record -> prop;
  final_evidence_fact:operation_prepared -> evidence_record -> prop;
  // This bridge must be proved by the exact pinned driver contract for the
  // evidence call, not by trusting evidence_disposition as a wire flag.
  driver_finality_fact:operation_prepared -> evidence_record -> prop;
  artifact_evidence_valid:operation_prepared -> evidence_record -> Tot bool;
  artifact_evidence_sound:(p:operation_prepared) -> (e:evidence_record)
    -> Lemma (artifact_evidence_valid p e == true ==>
       artifact_descriptors_valid p.prepared_artifact_policy
         e.evidence_call p.prepared_artifact_parent_digests
         e.evidence_artifacts /\
       artifact_descriptors_size e.evidence_artifacts <=
         p.prepared_artifact_policy.maximum_artifact_bundle_bytes /\
       (forall reference.
          artifact_ref_member reference e.evidence_artifacts == true ==>
          staged_artifact_matches hash_artifact_bytes check_artifact_schema
            reference));
  evidence_sound:(p:operation_prepared) -> (e:evidence_record) -> Lemma
    (evidence_valid p e == true ==>
       correlated_evidence p e /\ evidence_fact p e /\
       (e.evidence_final == true ==> final_evidence_fact p e) /\
       (e.evidence_final == true /\
        e.evidence_call.call_kind == Reconcile /\
        e.evidence_disposition == Some DefinitelyNotApplied ==>
          driver_finality_fact p e));
  not_applied_valid:operation_prepared -> call_id -> bytes -> list event
    -> Tot bool;
  not_applied_sound:(p:operation_prepared) -> (call:call_id)
    -> (proof_bytes:bytes) -> (events:list event)
    -> Lemma (not_applied_valid p call proof_bytes events == true ==>
       exists evidence. mem evidence events /\
         (match evidence.body with
          | CallEvidence e ->
              call_id_eq e.evidence_call call /\
              e.evidence_call.call_kind == Reconcile /\
              e.evidence_final /\
              e.evidence_disposition == Some DefinitelyNotApplied /\
              driver_finality_fact p e
          | _ -> False));
  timeout_expiry_valid:call_id -> nat -> nat -> nat -> bytes -> Tot bool;
  timeout_expiry_sound:(call:call_id) -> (deadline:nat)
    -> (generation:nat) -> (observed_at:nat)
    -> (proof_bytes:bytes)
    -> Lemma (timeout_expiry_valid call deadline generation observed_at
         proof_bytes == true ==> deadline <= observed_at);
  settlement_valid:call_id -> nat -> bytes -> Tot bool;
  settled_charge:call_id -> nat -> prop;
  final_settlement:call_id -> nat -> prop;
  // This fact is the boundary to driver's actual_charge/charge_final laws.
  settled_amount_is_driver_actual:call_id -> nat -> prop;
  settlement_sound:(call:call_id) -> (amount:nat) -> (proof_bytes:bytes)
    -> Lemma (settlement_valid call amount proof_bytes == true ==>
       settled_charge call amount /\ final_settlement call amount /\
       settled_amount_is_driver_actual call amount)
}

noeq type completion_verifier = {
  local_valid:occurrence -> bytes -> code_id -> nat -> digest -> bytes -> Tot bool;
  local_result:occurrence -> bytes -> code_id -> nat -> digest -> bytes -> prop;
  local_sound:(where:occurrence) -> (input:bytes) -> (id:code_id)
    -> (version:nat) -> (build:digest) -> (output:bytes)
    -> Lemma (local_valid where input id version build output == true ==>
      local_result where input id version build output);
  // Completion may publish only the exact descriptor bundle from the
  // referenced final reply; store refinement proves staged bytes read back.
  artifact_commit_valid:operation_completed -> list event -> Tot bool;
  artifact_bundle_valid:operation_completed -> list event -> prop;
  artifact_commit_sound:(c:operation_completed) -> (events:list event)
    -> Lemma (artifact_commit_valid c events == true ==>
      artifact_bundle_valid c events);
  expansion_join_valid:expand_committed -> list event -> bytes -> Tot bool;
  expansion_join_result:expand_committed -> list event -> bytes -> prop;
  expansion_join_sound:(c:expand_committed) -> (events:list event)
    -> (output:bytes)
    -> Lemma (expansion_join_valid c events output == true ==>
       expansion_join_result c events output)
}


noeq type generation_verifier = {
  generation:generation_contract;
  expected_input:journal_state -> occurrence -> Tot (option bytes);
  expected_snapshot:journal_state -> occurrence -> Tot bytes;
  preparation_valid:journal_state -> expand_prepared -> Tot bool;
  preparation_exact:(state:journal_state) -> (p:expand_prepared)
    -> Lemma (preparation_valid state p == true ==>
       expected_input state p.prepared_at == Some p.prepared_input /\
       expected_snapshot state p.prepared_at == p.prepared_snapshot);
  accepts_generation:expand_prepared -> expand_committed -> Tot bool;
  acceptance_sound:(p:expand_prepared) -> (c:expand_committed)
    -> Lemma (accepts_generation p c == true ==>
       generation_semantics generation p c)
}

noeq type admission_contract = {
  admission_id:code_id;
  admission_version:nat;
  admission_build:digest;
  work_registry:typed_work_registry_contract;
  root_work:run_header -> Tot (option typed_work_package);
  root_work_sound:(header:run_header) -> (plan:typed_work_package)
    -> Lemma (root_work header == Some plan ==>
       plan.packed_plan_id == header.header_root_plan /\
       work_registry.resolve_work plan.packed_plan_id == Some plan /\
       work_registry.work_matches_canonical_fields plan);
  root_header_valid:run_header -> Tot bool;
  root_header_identity:run_header -> prop;
  root_header_sound:(header:run_header) -> Lemma
    (root_header_valid header == true ==>
       root_header_identity header /\
       header.header_registry_id == work_registry.code_registry.registry_id /\
       header.header_registry_version ==
         work_registry.code_registry.registry_version /\
       header.header_registry_build ==
         work_registry.code_registry.registry_build /\
       exists plan. root_work header == Some plan /\
         plan.packed_plan_id == header.header_root_plan /\
         work_registry.work_matches_canonical_fields plan);
  occurrence_semantics:journal_state -> occurrence -> prop;
  resolve_work_at_occurrence:journal_state -> occurrence
    -> Tot (option typed_work_package);
  occurrence_work_sound:(state:journal_state) -> (where:occurrence)
    -> (plan:typed_work_package)
    -> Lemma (resolve_work_at_occurrence state where == Some plan ==>
       occurrence_semantics state where /\
       plan.packed_plan_id == where.plan_id /\
       work_registry.resolve_work where.plan_id == Some plan /\
       work_registry.work_matches_canonical_fields plan);
  occurrence_valid:journal_state -> occurrence -> Tot bool;
  occurrence_sound:(state:journal_state) -> (where:occurrence)
    -> Lemma (occurrence_valid state where == true ==>
       occurrence_semantics state where);
  generation_rules:generation_verifier;
  operation_rules:operation_verifier;
  expected_request:journal_state -> occurrence -> Tot (option bytes);
  request_matches_work_input:journal_state -> operation_prepared -> Tot bool;
  request_input_sound:(state:journal_state) -> (p:operation_prepared)
    -> Lemma (request_matches_work_input state p == true ==>
       expected_request state p.prepared_operation_at == Some p.prepared_request);
  completion_rules:completion_verifier
}
