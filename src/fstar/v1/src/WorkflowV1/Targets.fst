module WorkflowV1.Targets
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
open WorkflowV1.Theorems

// Proposition aliases for desired results; this module does not prove them.
type local_completion_fact (state:journal_state) (where:occurrence)
    (input output:bytes) =
  exists e. mem e state.history /\
    (match e.body with
     | LocalCompleted at saved_input _ _ _ saved_output ->
         occurrence_eq at where /\ saved_input = input /\
         saved_output = output
     | _ -> False)

type external_completion_fact (state:journal_state) (where:occurrence)
    (input terminal_bytes:bytes) =
  exists e. mem e state.history /\
    (match e.body with
     | OperationCompleted c ->
         occurrence_eq c.completed_operation_at where /\
         c.completed_input = input /\ c.completed_terminal = terminal_bytes
     | _ -> False)

type expansion_completion_fact (state:journal_state) (where:occurrence)
    (result:bytes) =
  exists e. mem e state.history /\
    (match e.body with
     | ExpansionCompleted c ->
         occurrence_eq c.expansion_completed_at where /\
         c.expansion_result = result
     | ExpansionCommitted c ->
         occurrence_eq c.committed_at where /\
         c.committed_direct_result = Some result
     | _ -> False)

// WIP targets below are propositions, not axioms. Instantiating a contract
// requires implementing its checker and discharging its soundness proof.
type target_completed_local_no_reinvoke (state:journal_state)
    (where:occurrence) (input output:bytes) =
  local_completion_fact state where input output ==>
  action_for_local state where input == ReuseCheckedCompletion output

type target_completed_external_no_dispatch (state:journal_state)
    (rules:admission_contract) (where:occurrence) (input output:bytes) =
  (exists completed. operation_completion_for where state.history ==
      Some completed /\ completed.completed_input == input /\
      completed.completed_terminal == output /\
      action_for_external state where input == ReuseOperationTerminal completed) /\
  (forall call. call.call_key.key_occurrence = where ==>
     driver_authorized state rules call == false)

type target_expansion_completion_no_chooser_or_join
    (state:journal_state) (where:occurrence) (input output:bytes) =
  expansion_completion_fact state where output ==>
  (chooser_enabled (action_for_expand state where input) == false /\
   join_enabled state where == false)

type target_generation_commit_sound (state:journal_state)
    (rules:generation_verifier) (prepared:expand_prepared)
    (committed:expand_committed) =
  (preparation_for committed.committed_at state.history == Some prepared /\
   legal_expansion_commit state rules committed == true) ==>
  generation_semantics rules.generation prepared committed

type target_child_action_requires_manifest (state:journal_state)
    (parent:occurrence) (ordinal:nat) (source resolved:plan_id) =
  child_action_enabled state parent ordinal source resolved ==>
  committed_child parent ordinal source resolved state.history

type target_incomplete_manifest_child_resumes (state:journal_state)
    (parent:occurrence) (ordinal:nat) (source resolved:plan_id) =
  committed_child parent ordinal source resolved state.history /\
  not (completion_seen
    { parent with plan_id=resolved;
      path=parent.path @ [ExpandChild ordinal source resolved] }
    state.history) ==>
  child_action_enabled state parent ordinal source resolved == true

type target_replay_restores_exact_prefix (initial:journal_state)
    (rules:admission_contract) (events:list event) (state:journal_state) =
  restore_from_events initial rules (Loaded events) == Restored state ==>
  state.history == initial.history @ events

type target_crash_cut_recovery (store:Type0)
    (contract:durable_store_contract store) (before:store) (run:run_id)
    (initial:journal_state) (rules:admission_contract)
    (state:journal_state) =
  (match contract.load (contract.crash_store before) run with
   | Loaded events ->
       event_prefix (contract.acknowledged_events before run) events /\
       (restore_from_events initial rules (Loaded events) == Restored state ==>
        state.history == initial.history @ events)
   | StorageUnavailable | StorageCorrupt -> True)

type target_acknowledged_external_completion_reused
    (store:Type0) (contract:durable_store_contract store) (before:store)
    (run:run_id) (initial:journal_state) (rules:admission_contract)
    (events:list event) (state:journal_state) (where:occurrence)
    (completed:operation_completed) =
  contract.load (contract.crash_store before) run == Loaded events /\
  event_prefix (contract.acknowledged_events before run) events /\
  restore_from_events initial rules (Loaded events) == Restored state /\
  operation_completion_for where
    (contract.acknowledged_events before run) == Some completed ==>
  action_for_external state where completed.completed_input ==
    ReuseOperationTerminal completed

type target_budget_reflects_journal (state:journal_state) =
  ledger_matches_history state.header state.history state.ledger == true

type target_expansion_budget_reflects_journal (state:journal_state) =
  state.expansion_nodes_remaining + committed_child_count state.history ==
    state.header.header_initial_nodes

type target_terminal_rechecked_from_raw (rules:admission_contract)
    (prepared:operation_prepared) (completed:operation_completed)
    (evidence:evidence_record) =
  rules.operation_rules.terminal_valid prepared completed evidence == true ==>
  (validated_operation_terminal prepared completed /\
   rules.operation_rules.terminal_revalidation_fact
     prepared completed evidence /\
   rules.operation_rules.terminal_disposition_fact
     prepared completed evidence)

type target_retry_requires_driver_finality (rules:admission_contract)
    (prepared:operation_prepared) (call:call_id) (proof_bytes:bytes)
    (events:list event) =
  rules.operation_rules.not_applied_valid prepared call proof_bytes events
    == true ==>
  exists evidence. mem evidence events /\
    (match evidence.body with
     | CallEvidence e ->
         call_id_eq e.evidence_call call /\
         e.evidence_final /\
         e.evidence_disposition == Some DefinitelyNotApplied /\
         rules.operation_rules.driver_finality_fact prepared e
     | _ -> False)

type target_settlement_matches_driver (rules:admission_contract)
    (call:call_id) (amount:nat) (proof_bytes:bytes) =
  rules.operation_rules.settlement_valid call amount proof_bytes == true ==>
  (rules.operation_rules.settled_charge call amount /\
   rules.operation_rules.final_settlement call amount /\
   rules.operation_rules.settled_amount_is_driver_actual call amount)

type target_timeout_is_expired (rules:admission_contract) (call:call_id)
    (deadline generation observed:nat) (proof_bytes:bytes) =
  rules.operation_rules.timeout_expiry_valid call deadline generation
    observed proof_bytes == true ==> deadline <= observed

type target_artifact_visibility (store:Type0)
    (contract:artifact_store_contract store) (state:store)
    (reference:artifact_ref) (events:list event) =
  artifact_visible_in_history reference events == true ==>
  (match resolve_published_artifact contract state events reference with
   | ArtifactReady wire ->
       length wire == reference.artifact_size /\
       contract.hash_artifact_bytes wire == reference.artifact_digest /\
       contract.check_artifact_schema reference.artifact_schema
         reference.artifact_schema_version wire == true
   | ArtifactUnavailable | ArtifactCorrupt -> True)

type target_unpublished_artifact_hidden (store:Type0)
    (contract:artifact_store_contract store) (state:store)
    (reference:artifact_ref) (events:list event) =
  artifact_visible_in_history reference events == false ==>
  resolve_published_artifact contract state events reference ==
    ArtifactUnavailable

// Remaining spec obligations are intentionally named for the top-down proof
// plan. They become theorems as the abstract evaluator and host refinements
// are added: T1 typed denotation; T2 canonical identities; T3 codec soundness;
// T4 all reducer invariants; T5 completed-node no-reinvoke; T6 every-cut
// recovery; T7 restart/uninterrupted observations; T8 adapter safety/progress;
// T9 artifacts; T10 budget; T11 extraction refinement; T12 effect authorization;
// T13 bounded graph termination; T14 library lowering/substitution.
type target_reducer_invariant (state:journal_state) : prop =
  state.ledger.budget_limit == state.header.header_budget_limit /\
  budget_valid state.ledger = true /\
  ledger_matches_history state.header state.history state.ledger = true /\
  state.expansion_nodes_remaining + committed_child_count state.history ==
    state.header.header_initial_nodes

type target_driver_contract (rules:admission_contract)
    (prepared:operation_prepared) (evidence:evidence_record) =
  rules.operation_rules.evidence_valid prepared evidence == true ==>
  (correlated_evidence prepared evidence /\
   rules.operation_rules.evidence_fact prepared evidence /\
   (evidence.evidence_final == true ==>
      rules.operation_rules.final_evidence_fact prepared evidence) /\
   (evidence.evidence_final == true /\
    evidence.evidence_call.call_kind == Reconcile /\
    evidence.evidence_disposition == Some DefinitelyNotApplied ==>
      rules.operation_rules.driver_finality_fact prepared evidence))

type target_host_refinement (b h:Type0) (driver:driver_contract b)
    (refinement:host_driver_refinement b h driver) =
  refinement.relates refinement.host_initial driver.initial_backend /\
  (forall host_before host_after abstract_before call request evidence.
     refinement.relates host_before abstract_before /\
     refinement.host_call_step host_before call request evidence host_after ==>
     exists abstract_after.
       driver.call_step abstract_before call request evidence abstract_after /\
       refinement.relates host_after abstract_after) /\
  (forall host_before host_after abstract_before.
     refinement.relates host_before abstract_before /\
     refinement.host_autonomous_step host_before host_after ==>
     exists abstract_after.
       driver.autonomous_step abstract_before abstract_after /\
       refinement.relates host_after abstract_after)
