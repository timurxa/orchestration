module WorkflowV1.Actions
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Expansion
open WorkflowV1.JournalTypes
open WorkflowV1.JournalFacts
open WorkflowV1.Contracts
open WorkflowV1.Admission
open WorkflowV1.Reducer

let rec local_completion_for (where:occurrence) (events:list event)
    : option (bytes & bytes) =
  match events with
  | [] -> None
  | e::rest ->
      (match e.body with
       | LocalCompleted at input _ _ _ output ->
           if occurrence_eq at where then Some (input, output)
           else local_completion_for where rest
       | _ -> local_completion_for where rest)

type local_action =
  | InvokeLocal
  | ReuseCheckedCompletion : bytes -> local_action
  | CompletionInputMismatch
  | StopAfterFailure

let action_for_local (state:journal_state) (where:occurrence)
    (requested_input:bytes) : local_action =
  match local_completion_for where state.history with
  | Some (saved_input, output) ->
      if saved_input = requested_input
      then ReuseCheckedCompletion output
      else CompletionInputMismatch
  | None ->
      if completion_seen where state.history then StopAfterFailure
      else InvokeLocal

let rec operation_completion_for (where:occurrence) (events:list event)
    : option operation_completed =
  match events with
  | [] -> None
  | e::rest ->
      (match operation_completion_for where rest with
       | Some c -> Some c
       | None ->
           match e.body with
           | OperationCompleted c ->
               if occurrence_eq c.completed_operation_at where then Some c
               else None
           | _ -> None)

type external_action =
  | PrepareOperation
  | ResumePreparedOperation : operation_prepared -> external_action
  | ReuseOperationTerminal : operation_completed -> external_action
  | OperationInputMismatch
  | StopOperationAfterFailure

let action_for_external (state:journal_state) (where:occurrence)
    (requested_input:bytes) : external_action =
  match operation_completion_for where state.history with
  | Some completed ->
      if completed.completed_input = requested_input
      then ReuseOperationTerminal completed
      else OperationInputMismatch
  | None ->
      if completion_seen where state.history then StopOperationAfterFailure
      else
        (match preparation_at_occurrence where state.history with
         | Some prepared ->
             if prepared.prepared_request = requested_input
             then ResumePreparedOperation prepared
             else OperationInputMismatch
         | None -> PrepareOperation)

type expand_action =
  | PrepareExpansion
  | ChooseFromSavedPreparation : expand_prepared -> expand_action
  | ReturnCommittedExpansionValue : bytes -> expand_action
  | ResumeCommittedManifest : expand_committed -> expand_action
  | ReuseExpansionCompletion : bytes -> expand_action
  | ExpansionInputMismatch
  | StopExpansionAfterFailure

let action_for_expand (state:journal_state) (where:occurrence)
    (requested_input:bytes) : expand_action =
  match expansion_for where state.history with
  | Some committed ->
      if committed.committed_input <> requested_input
      then ExpansionInputMismatch
      else
        (match expansion_completion_for where state.history with
         | Some completed -> ReuseExpansionCompletion completed.expansion_result
         | None ->
             (match committed.committed_direct_result with
              | Some output -> ReturnCommittedExpansionValue output
              | None -> ResumeCommittedManifest committed))
  | None ->
      if completion_seen where state.history then StopExpansionAfterFailure
      else
        (match preparation_for where state.history with
         | Some p ->
             if p.prepared_input = requested_input
             then ChooseFromSavedPreparation p
             else ExpansionInputMismatch
         | None -> PrepareExpansion)

let manifest_child_occurrence (parent:occurrence) (ordinal:nat)
    (source resolved:plan_id) : occurrence =
  { parent with
    plan_id=resolved;
    path=parent.path @ [ExpandChild ordinal source resolved] }

let chooser_enabled (action:expand_action) : bool =
  match action with
  | ChooseFromSavedPreparation _ -> true
  | _ -> false

let child_action_enabled (state:journal_state) (parent:occurrence)
    (ordinal:nat) (source resolved:plan_id) : bool =
  let child = manifest_child_occurrence parent ordinal source resolved in
  committed_child parent ordinal source resolved state.history &&
  not (completion_seen child state.history)

let join_enabled (state:journal_state) (where:occurrence) : bool =
  match expansion_for where state.history with
  | None -> false
  | Some manifest ->
      manifest.committed_direct_result = None &&
      expansion_completion_for where state.history = None &&
      manifest_children_completed where manifest.committed_manifest
        state.history

// Small proved consequences of the definitions, not assumptions about a host.
