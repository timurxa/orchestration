module WorkflowV1.Storage
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Artifacts
open WorkflowV1.JournalTypes
open WorkflowV1.JournalFacts
open WorkflowV1.Recovery

let event_eq (left:event) (right:event) : bool =
  left.sequence = right.sequence && left.event_id = right.event_id &&
  left.epoch = right.epoch && left.body = right.body

let rec event_prefix (prefix:list event) (whole:list event)
    : Tot bool (decreases prefix) =
  match prefix, whole with
  | [], _ -> true
  | left::lefts, right::rights ->
      event_eq left right && event_prefix lefts rights
  | _, _ -> false

let next_sequence_after (events:list event) : nat = length events + 1

let epoch_after_event (previous:nat) (body:event_body) : nat =
  match body with
  | EpochStarted next_epoch -> next_epoch
  | _ -> previous

type append_outcome (store:Type0) =
  | AppendAcknowledged : store -> append_outcome store
  | AppendUncertain : store -> append_outcome store
  | AppendRejected : store -> append_outcome store

noeq type durable_store_contract (store:Type0) = {
  load:(store -> run_id -> Tot load_result);
  durable_events:(store -> run_id -> Tot (list event));
  acknowledged_events:(store -> run_id -> Tot (list event));
  active_epoch:(store -> run_id -> Tot nat);
  crash_store:store -> Tot store;
  append:(store -> run_id -> nat -> nat -> event
    -> Tot (append_outcome store));
  append_result_law:(before:store) -> (run:run_id) -> (expected_sequence:nat)
    -> (epoch:nat) -> (event:event) -> (result:append_outcome store)
    -> Lemma (append before run expected_sequence epoch event == result ==>
       (match result with
        | AppendAcknowledged after ->
            durable_events after run == durable_events before run @ [event] /\
            acknowledged_events after run ==
              acknowledged_events before run @ [event] /\
            active_epoch after run ==
              epoch_after_event (active_epoch before run) event.body
        | AppendUncertain after ->
            (durable_events after run == durable_events before run \/
             durable_events after run == durable_events before run @ [event]) /\
            acknowledged_events after run == acknowledged_events before run /\
            (active_epoch after run == active_epoch before run \/
             active_epoch after run ==
               epoch_after_event (active_epoch before run) event.body)
        | AppendRejected after ->
            durable_events after run == durable_events before run /\
            acknowledged_events after run == acknowledged_events before run /\
            active_epoch after run == active_epoch before run));
  load_is_exact_durable_log:(state:store) -> (run:run_id)
    -> (events:list event) -> Lemma
       (load state run == Loaded events ==> events == durable_events state run);
  epoch_fences_append:(state:store) -> (run:run_id) -> (epoch:nat)
    -> (event:event) -> Lemma
       (epoch <> event.epoch ==> append state run event.sequence epoch event ==
          AppendRejected state);
  current_epoch_fences_append:(state:store) -> (run:run_id) -> (epoch:nat)
    -> (event:event) -> Lemma
       (epoch <> active_epoch state run ==>
          append state run event.sequence epoch event == AppendRejected state);
  sequence_fences_append:(state:store) -> (run:run_id)
    -> (expected_sequence:nat) -> (epoch:nat) -> (event:event)
    -> Lemma (expected_sequence <>
        next_sequence_after (durable_events state run) ==>
       append state run expected_sequence epoch event == AppendRejected state);
  loaded_log_is_a_complete_event_prefix:(state:store) -> (run:run_id)
    -> (events:list event) -> Lemma
       (load state run == Loaded events ==>
          event_prefix events (durable_events state run));
  crash_cut_is_acknowledged_prefix_or_one_whole_event:
    (state:store) -> (run:run_id) -> Lemma
      (durable_events (crash_store state) run == acknowledged_events state run \/
       (exists uncertain.
          durable_events (crash_store state) run ==
            acknowledged_events state run @ [uncertain]));
  loaded_log_contains_acknowledged_prefix:(state:store) -> (run:run_id)
    -> (events:list event) -> Lemma
       (load (crash_store state) run == Loaded events ==>
          event_prefix (acknowledged_events state run) events)
}

type append_phase =
  | ReadyToAppend
  | ReloadRequired

let phase_after_append (#store:Type0) (result:append_outcome store)
    : append_phase =
  match result with
  | AppendUncertain _ -> ReloadRequired
  | AppendAcknowledged _ | AppendRejected _ -> ReadyToAppend

let semantic_transition_allowed (phase:append_phase) : bool =
  match phase with
  | ReadyToAppend -> true
  | ReloadRequired -> false


type artifact_load =
  | ArtifactReady : bytes -> artifact_load
  | ArtifactUnavailable
  | ArtifactCorrupt

noeq type artifact_store_contract (store:Type0) = {
  hash_artifact_bytes:bytes -> Tot digest;
  check_artifact_schema:code_id -> nat -> bytes -> Tot bool;
  put_immutable:store -> artifact_candidate -> Tot store;
  // Internal staging read. Callers resolve published artifacts only through
  // resolve_published_artifact below.
  load_staged_artifact:store -> artifact_ref -> Tot artifact_load;
  put_returns_exact_bytes:(before:store) -> (candidate:artifact_candidate)
    -> Lemma (load_staged_artifact (put_immutable before candidate)
         candidate.candidate_ref == ArtifactReady candidate.candidate_bytes);
  put_preserves_existing_bytes:(before:store) -> (candidate:artifact_candidate)
    -> (reference:artifact_ref) -> (wire:bytes) -> Lemma
       (load_staged_artifact before reference == ArtifactReady wire ==>
        load_staged_artifact (put_immutable before candidate) reference ==
          ArtifactReady wire);
  loaded_artifact_is_sound:(state:store) -> (reference:artifact_ref)
    -> (wire:bytes) -> Lemma
       (load_staged_artifact state reference == ArtifactReady wire ==>
          length wire == reference.artifact_size /\
          hash_artifact_bytes wire == reference.artifact_digest /\
          check_artifact_schema reference.artifact_schema
            reference.artifact_schema_version wire == true)
}

let resolve_published_artifact (#store:Type0)
    (contract:artifact_store_contract store) (state:store)
    (events:list event) (reference:artifact_ref) : artifact_load =
  if artifact_visible_in_history reference events
  then contract.load_staged_artifact state reference
  else ArtifactUnavailable
