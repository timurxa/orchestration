module WorkflowV1.Operations
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Artifacts

noeq type adapter_contract (i raw:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop) = {
  hash_bytes:bytes -> Tot digest;
  request_materialization:i -> bytes -> prop;
  response_correlation:call_id -> bytes -> prop;
  checked_result:(x:i) -> (context:operation_context) -> raw
    -> option (accepted_at i o valid x context) -> prop;
  check_artifact_schema:code_id -> nat -> bytes -> Tot bool;
  artifact_integrity:artifact_policy -> call_id -> list digest
    -> artifact_candidate -> Tot bool;
  artifact_integrity_sound:(policy:artifact_policy) -> (call:call_id)
    -> (expected_parents:list digest)
    -> (candidate:artifact_candidate)
    -> Lemma (artifact_integrity policy call expected_parents candidate == true ==>
       artifact_candidate_valid hash_bytes check_artifact_schema policy call
         expected_parents candidate);
  effect_isolation:operation_key -> prop
}

noeq type adapter_refinement_obligation (i raw:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop)
    (contract:adapter_contract i raw o valid) = {
  materialization_proof:(x:i) -> (wire:bytes)
    -> contract.request_materialization x wire;
  correlation_proof:(call:call_id) -> (wire:bytes)
    -> contract.response_correlation call wire;
  checked_result_proof:(x:i) -> (context:operation_context)
    -> (raw_value:raw)
    -> (result:option (accepted_at i o valid x context))
    -> contract.checked_result x context raw_value result;
  artifact_proof:(policy:artifact_policy) -> (call:call_id)
    -> (expected_parents:list digest)
    -> (candidate:artifact_candidate)
    -> contract.artifact_integrity policy call expected_parents candidate;
  isolation_proof:(key:operation_key) -> contract.effect_isolation key
}

noeq type op_spec (c i raw:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop) = {
  operation_id:code_id;
  operation_version:nat;
  operation_build:digest;
  validator_id:code_id;
  validator_version:nat;
  validator_build:digest;
  configuration:c;
  configuration_codec:codec c (fun _ -> True);
  request_codec:codec i (fun _ -> True);
  raw_codec:codec raw (fun _ -> True);
  accepted_codec:indexed_codec (i & operation_context)
    (fun xi -> accepted_at i o valid xi._1 xi._2)
    (fun _ _ -> True);
  terminal_codec:indexed_codec (i & operation_context)
    (fun xi -> terminal_at i o valid xi._1 xi._2)
    (fun _ _ -> True);
  validate:(x:i) -> (context:operation_context) -> raw
    -> Tot (option (accepted_at i o valid x context));
  maximum_charge:(x:i) -> call_kind -> nat;
  maximum_calls:call_kind -> nat;
  maximum_attempts:nat;
  replay_policy:replay_policy;
  supports_cancel:bool;
  artifact_policy:artifact_policy
}

type driver_ref = {
  driver_id:code_id;
  driver_version:nat;
  driver_build:digest;
  contract_id:code_id;
  contract_version:nat;
  contract_build:digest
}

type evidence_record = {
  evidence_call:call_id;
  evidence_raw:bytes;
  evidence_artifacts:list artifact_ref;
  evidence_final:bool;
  evidence_disposition:option effect_disposition;
  evidence_terminal_bytes:option bytes;
  evidence_charge:option nat
}

noeq type backend_trace (b:Type0)
    (call_step:b -> call_id -> bytes -> evidence_record -> b -> prop)
    (autonomous_step:b -> b -> prop) : b -> b -> Type =
  | BackendTraceRefl : state:b
      -> backend_trace b call_step autonomous_step state state
  | BackendTraceCall : before:b -> after:b -> call:call_id
      -> request:bytes -> evidence:evidence_record
      -> call_step before call request evidence after
      -> backend_trace b call_step autonomous_step before after
  | BackendTraceAutonomous : before:b -> after:b
      -> autonomous_step before after
      -> backend_trace b call_step autonomous_step before after
  | BackendTraceTrans : before:b -> middle:b -> after:b
      -> backend_trace b call_step autonomous_step before middle
      -> backend_trace b call_step autonomous_step middle after
      -> backend_trace b call_step autonomous_step before after

// Concrete drivers must prove these laws for an explicit backend model.
// In particular, final NotApplied evidence excludes all future delayed
// application, and the invariant bounds logical effects per operation key.
noeq type driver_contract (b:Type0) = {
  contract_id:code_id;
  contract_version:nat;
  contract_build:digest;
  initial_backend:b;
  call_step:b -> call_id -> bytes -> evidence_record -> b -> prop;
  autonomous_step:b -> b -> prop;
  backend_invariant:b -> prop;
  effect_count:b -> operation_key -> nat;
  actual_charge:b -> call_id -> option nat;
  backend_initial:unit -> Lemma (backend_invariant initial_backend);
  call_preserves_invariant:(before:b) -> (call:call_id) -> (request:bytes)
    -> (evidence:evidence_record) -> (after:b)
    -> Lemma (call_step before call request evidence after /\
       backend_invariant before ==> backend_invariant after);
  autonomous_preserves_invariant:(before:b) -> (after:b)
    -> Lemma (autonomous_step before after /\
       backend_invariant before ==> backend_invariant after);
  per_key_effect_bound:(state:b) -> Lemma
    (backend_invariant state ==>
       (forall key. effect_count state key <= 1));
  effect_count_monotone_call:(before:b) -> (call:call_id)
    -> (request:bytes) -> (evidence:evidence_record) -> (after:b)
    -> (key:operation_key)
    -> Lemma (call_step before call request evidence after ==>
       effect_count before key <= effect_count after key);
  effect_count_monotone_autonomous:(before:b) -> (after:b)
    -> (key:operation_key)
    -> Lemma (autonomous_step before after ==>
       effect_count before key <= effect_count after key);
  correlation_sound:(before:b) -> (call:call_id) -> (request:bytes)
    -> (evidence:evidence_record) -> (after:b)
    -> Lemma (call_step before call request evidence after ==>
       call_id_eq evidence.evidence_call call /\
       call.call_key.key_request_bytes == request);
  final_not_applied_sound:(before:b) -> (call:call_id) -> (request:bytes)
    -> (evidence:evidence_record) -> (after:b)
    -> Lemma (call_step before call request evidence after /\
       call.call_kind == Reconcile /\ evidence.evidence_final /\
       evidence.evidence_disposition == Some DefinitelyNotApplied ==>
       (forall (future:b). forall
          (trace:backend_trace b call_step autonomous_step after future).
          effect_count future call.call_key == 0));
  charge_sound:(before:b) -> (call:call_id) -> (request:bytes)
    -> (evidence:evidence_record) -> (after:b) -> (amount:nat)
    -> Lemma (call_step before call request evidence after /\
       evidence.evidence_charge == Some amount ==>
       actual_charge after call == Some amount);
  charge_final:(before:b) -> (call:call_id) -> (request:bytes)
    -> (evidence:evidence_record) -> (after:b) -> (amount:nat)
    -> Lemma (call_step before call request evidence after /\
       evidence.evidence_final /\ evidence.evidence_charge == Some amount ==>
       (forall (future:b). forall
          (trace:backend_trace b call_step autonomous_step after future).
          actual_charge future call == Some amount))
}


noeq type host_driver_refinement (b h:Type0)
    (driver:driver_contract b) = {
  relates:h -> b -> prop;
  host_initial:h;
  host_call_step:h -> call_id -> bytes -> evidence_record -> h -> prop;
  host_autonomous_step:h -> h -> prop;
  host_stutter_step:h -> h -> prop;
  initial_related:unit -> Lemma
    (relates host_initial driver.initial_backend);
  call_simulation:(host_before:h) -> (host_after:h)
    -> (abstract_before:b) -> (call:call_id) -> (request:bytes)
    -> (evidence:evidence_record)
    -> Lemma (relates host_before abstract_before /\
       host_call_step host_before call request evidence host_after ==>
       exists abstract_after.
         driver.call_step abstract_before call request evidence abstract_after /\
         relates host_after abstract_after);
  autonomous_simulation:(host_before:h) -> (host_after:h)
    -> (abstract_before:b)
    -> Lemma (relates host_before abstract_before /\
       host_autonomous_step host_before host_after ==>
       exists abstract_after.
         driver.autonomous_step abstract_before abstract_after /\
         relates host_after abstract_after);
  stutter_simulation:(host_before:h) -> (host_after:h)
    -> (abstract_state:b)
    -> Lemma (relates host_before abstract_state /\
       host_stutter_step host_before host_after ==>
       relates host_after abstract_state)
}

noeq type bound_operation (b c i raw:Type0) (o:i -> Type0)
    (valid:(x:i) -> operation_context -> o x -> prop) = {
  // Inline authors and reusable adapter libraries build this same package;
  // packaging does not change the verifier or durability boundary.
  spec:op_spec c i raw o valid;
  driver:driver_ref;
  driver_laws:driver_contract b;
  concrete_driver_state:Type0;
  concrete_driver_refinement:
    host_driver_refinement b concrete_driver_state driver_laws;
  driver_identity_exact:
    driver.contract_id == driver_laws.contract_id /\
    driver.contract_version == driver_laws.contract_version /\
    driver.contract_build == driver_laws.contract_build;
  effective_config_id:code_id;
  adapter:adapter_contract i raw o valid;
  adapter_proofs:adapter_refinement_obligation i raw o valid adapter;
  request_materializes_canonical_input:(x:i) -> Lemma
    (adapter.request_materialization x (spec.request_codec.encode x));
  validator_refinement:(x:i) -> (context:operation_context) -> (raw_value:raw)
    -> Lemma (adapter.checked_result x context raw_value
       (spec.validate x context raw_value))
}
