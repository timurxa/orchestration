module WorkflowExamples
open FStar.String
open FStar.List.Tot
open WorkflowCore
open WorkflowStore

let ctx0 (run_id:nat) (budget:budget) : context = {
  run_id=run_id; event_sequence=0; budget=budget;
  operations=[]; expansions=[]; artifacts=[]
}

let clean_budget (limit:nat) : budget = { limit=limit; spent=0; reserved=0 }

let add_code (name:string) (version:nat) (amount:nat) : code_ref nat nat nat = {
  id=name; version=version;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=amount; apply=(fun c x -> c + x)
}

let add_flow (amount:nat) : workflow nat nat = pure (add_code "example.add" 1 amount)

let test_local_api () : Tot bool =
  let ctx=ctx0 1 (clean_budget 20) in
  let seq=then_flow (add_flow 3) (add_flow 4) in
  let seq_ok=(seq.evaluate ctx [] 5).value = Some 12 in
  let fan=fork (add_flow 10) (add_flow 20) in
  let fan_ok=(fan.evaluate ctx [] 5).value = Some (15, 25) in
  let mapped=lift (Lists (Options Id)) (add_flow 1) in
  let mapped_ok=(mapped.evaluate ctx [] [Some 2; None; Some 7]).value =
    Some [Some 3; None; Some 8] in
  let product=lift (Products Id Id) (add_flow 2) in
  let product_ok=(product.evaluate ctx [] (4, 9)).value = Some (6, 11) in
  let empty_ok=(((lift (Lists Id) (add_flow 1)).evaluate ctx [] []).value = Some []) in
  let absent_ok=(((lift (Options Id) (add_flow 1)).evaluate ctx [] None).value = Some None) in
  seq_ok && fan_ok && mapped_ok && product_ok && empty_ok && absent_ok

let op_spec (name:string) (charge:nat) (output:nat) : op_spec nat nat nat = {
  operation_id=name; operation_version=1; capability="fake." ^ name;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=0; maximum_charge=charge
}

let commit (state:durable_state) (body:event_body) : option durable_state =
  apply_event state { sequence=next_sequence state; body=body }

let storage_roundtrip (state:durable_state) : Tot (option durable_state) =
  match encode_state state with
  | None -> None
  | Some wire -> decode_state wire

let test_external_fork () : Tot bool =
  let left=external (op_spec "left" 4 11) in
  let right=external (op_spec "right" 3 22) in
  let plan=fork left right in
  match open_run "examples-v1" 9 nat_codec plan 5 (clean_budget 7) with
  | None -> false
  | Some initial ->
    let e0=resume_evaluate "examples-v1" nat_codec plan initial in
    (match e0.actions with
     | PrepareOperation left_record :: PrepareOperation stale_right :: [] ->
       (match commit initial (OperationPrepared left_record) with
        | None -> false
        | Some reserved_left ->
          (match commit reserved_left
             (OperationStatusChanged left_record.occurrence left_record.attempt Pending) with
           | None -> false
           | Some pending_left0 ->
             (match storage_roundtrip pending_left0 with
              | None -> false
              | Some pending_left ->
             let ep=resume_evaluate "examples-v1" nat_codec plan pending_left in
             let reconcile_visible = match ep.actions with
               | ReconcileOperation where attempt :: _ ->
                 occurrence_equal where left_record.occurrence &&
                 attempt = left_record.attempt
               | _ -> false in
             (match pick_ready_action (context_of_state pending_left) ep.actions with
              | Some (PrepareOperation right_record) ->
                let stale_rejected=commit pending_left (OperationPrepared stale_right) = None in
                (match commit pending_left (OperationPrepared right_record) with
                 | None -> false
                 | Some both_reserved ->
                   (match commit both_reserved
                      (OperationStatusChanged right_record.occurrence right_record.attempt
                         (Succeeded (WNat 22) 2)) with
                    | None -> false
                    | Some right_done ->
                      (match commit right_done
                         (OperationStatusChanged left_record.occurrence left_record.attempt
                            (Succeeded (WNat 11) 3)) with
                       | None -> false
                       | Some done_state ->
                         let final=resume_evaluate "examples-v1" nat_codec plan done_state in
                         let duplicate=apply_event done_state {
                           sequence=next_sequence done_state;
                           body=OperationStatusChanged left_record.occurrence left_record.attempt
                             (Succeeded (WNat 11) 3)
                         } in
                         let late=apply_event done_state {
                           sequence=next_sequence done_state;
                           body=OperationStatusChanged left_record.occurrence left_record.attempt
                             (Failed "late failure")
                         } in
                         final.value = Some (11, 22) &&
                         done_state.budget = {limit=7; spent=5; reserved=0} &&
                         state_is_replay_valid done_state &&
                         duplicate <> None && late = None &&
                         reconcile_visible && stale_rejected &&
                         storage_roundtrip done_state = Some done_state))
                 )
              | _ -> false))))
     | _ -> false)

let test_crash_after_intent () : Tot bool =
  let plan=fork (external (op_spec "left" 4 11))
                (external (op_spec "right" 3 22)) in
  match open_run "examples-v1" 10 nat_codec plan 5 (clean_budget 7) with
  | None -> false
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
     | PrepareOperation intent :: _ ->
       (match commit initial (OperationPrepared intent) with
        | None -> false
        | Some prepared0 ->
          let dispatchable =
            match (resume_evaluate "examples-v1" nat_codec plan prepared0).actions with
            | DispatchOperation where attempt :: _ ->
              occurrence_equal where intent.occurrence && attempt = intent.attempt &&
              action_ready (context_of_state prepared0) (DispatchOperation where attempt)
            | _ -> false in
          (match storage_roundtrip prepared0 with
           | None -> false
           | Some prepared ->
             match recover_after_process_loss prepared with
             | None -> false
             | Some recovered ->
               let evaluation=resume_evaluate "examples-v1" nat_codec plan recovered in
               let old=find_operation_attempt intent.occurrence intent.attempt recovered.operations in
               let next=pick_ready_action (context_of_state recovered) evaluation.actions in
               old <> None &&
               (match old with | Some x -> x.status = Unknown && recovered.budget.reserved = 4
                 | None -> false) &&
               (match next with | Some (PrepareOperation op) -> op.operation_id = "right"
                 | _ -> false) && state_is_replay_valid recovered && dispatchable))
     | _ -> false)

let direct_route : route_code nat nat nat = {
  route_id="example.direct"; route_version=1;
  resolver_id="example.direct-resolver"; resolver_version=1;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=2;
  choose=(fun capture input snapshot -> Return (capture + input + snapshot.limit));
  resolve=(fun _ -> None)
}

let child_route : route_code nat nat nat = {
  route_id="example.child"; route_version=1;
  resolver_id="example.child-resolver"; resolver_version=1;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=4;
  choose=(fun capture input _ ->
    Expand { child_id="example.add"; child_version=1;
      child_capture_tag=tag_of_codec nat_codec; child_capture=WNat capture });
  resolve=(fun ref ->
    match nat_codec.decode ref.child_capture with
    | Some amount ->
      if ref.child_id = "example.add" && ref.child_version = 1 &&
         ref.child_capture_tag = tag_of_codec nat_codec
      then Some (add_flow amount) else None
    | _ -> None)
}

let sum_pair_code : code_ref nat (nat & nat) nat = {
  id="example.pair-sum"; version=1;
  capture_codec=nat_codec; input_codec=pair_codec nat_codec nat_codec;
  output_codec=nat_codec; capture=0;
  apply=(fun _ (left, right) -> left + right)
}

let parallel_child_plan : workflow nat nat =
  then_flow
    (fork (external (op_spec "child-left" 2 31))
          (external (op_spec "child-right" 2 32)))
    (pure sum_pair_code)

let parallel_child_route : route_code nat nat nat = {
  route_id="example.parallel-child"; route_version=1;
  resolver_id="example.parallel-resolver"; resolver_version=1;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=0;
  choose=(fun _ _ _ -> Expand {child_id="example.parallel"; child_version=1;
    child_capture_tag=tag_of_codec nat_codec; child_capture=WNat 0});
  resolve=(fun ref ->
    if ref.child_id = "example.parallel" && ref.child_version = 1 &&
       ref.child_capture_tag = tag_of_codec nat_codec && ref.child_capture = WNat 0
    then Some parallel_child_plan
    else None)
}

let resource_boundary_route : route_code nat nat nat = {
  route_id="example.resource-boundary"; route_version=1;
  resolver_id="example.resource-resolver"; resolver_version=1;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=2;
  choose=(fun _ input snapshot ->
    if available snapshot >= 3 then
      Expand {child_id="example.add"; child_version=1;
        child_capture_tag=tag_of_codec nat_codec; child_capture=WNat 2}
    else Return 0);
  resolve=(fun ref ->
    if ref.child_id = "example.add" && ref.child_version = 1 &&
       ref.child_capture_tag = tag_of_codec nat_codec && ref.child_capture = WNat 2
    then Some (add_flow 2) else None)
}

let fork_demo_plan () : workflow nat (nat & nat) =
  fork (external (op_spec "left" 4 11)) (external (op_spec "right" 3 22))

let route_demo_plan () : workflow nat nat = so child_route

let new_fork_run (run_id:nat) : option durable_state =
  open_run "examples-v1" run_id nat_codec (fork_demo_plan ()) 5 (clean_budget 7)

let new_route_run (run_id:nat) : option durable_state =
  open_run "examples-v1" run_id nat_codec (route_demo_plan ()) 5 (clean_budget 8)

let pending_fork_checkpoint (run_id:nat) : Tot (option durable_state) =
  match new_fork_run run_id with
  | None -> None
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec (fork_demo_plan ()) initial).actions with
     | PrepareOperation intent :: _ ->
       (match commit initial (OperationPrepared intent) with
        | None -> None
        | Some prepared -> commit prepared
          (OperationStatusChanged intent.occurrence intent.attempt Pending))
     | _ -> None)

let expansion_checkpoint (run_id:nat) : Tot (option durable_state) =
  match new_route_run run_id with
  | None -> None
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec (route_demo_plan ()) initial).actions with
     | SaveExpansion expansion :: [] -> commit initial (ExpansionSaved expansion)
     | _ -> None)

let direct_expansion_checkpoint (run_id:nat) : Tot (option durable_state) =
  let plan=so direct_route in
  match open_run "examples-v1" run_id nat_codec plan 5 (clean_budget 8) with
  | None -> None
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
     | SaveExpansion expansion :: [] -> commit initial (ExpansionSaved expansion)
     | _ -> None)

let state_wire (state:durable_state) : Tot (option wire) = encode_state state

let decrement_code : code_ref nat nat nat = {
  id="example.decrement"; version=1;
  capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
  capture=0; apply=(fun _ value -> if value = 0 then 0 else value - 1)
}

let rec bounded_route (fuel:nat) : Tot (route_code nat nat nat) (decreases fuel) =
  let next_fuel=if fuel = 0 then 0 else fuel - 1 in
  {
    route_id="example.bounded"; route_version=1;
    resolver_id="example.bounded-resolver"; resolver_version=1;
    capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
    capture=fuel;
    choose=(fun _ input _ ->
      if fuel = 0 || input = 0 then Return input
      else Expand { child_id="example.bounded-child"; child_version=1;
        child_capture_tag=tag_of_codec nat_codec; child_capture=WNat next_fuel });
    resolve=(fun ref ->
      if fuel > 0 && ref.child_id = "example.bounded-child" &&
         ref.child_version = 1 && ref.child_capture_tag = tag_of_codec nat_codec &&
         ref.child_capture = WNat next_fuel
      then Some (then_flow (pure decrement_code) (so (bounded_route next_fuel)))
      else None)
  }

let bounded_fuel_decreases (fuel:nat) : Lemma (fuel > 0 ==> fuel - 1 < fuel) = ()

let rec bounded_expansion_count (fuel:nat) : Tot nat (decreases fuel) =
  if fuel = 0 then 0 else 1 + bounded_expansion_count (fuel - 1)

let rec bounded_expansion_count_law (fuel:nat)
  : Lemma (bounded_expansion_count fuel = fuel) (decreases fuel) =
  if fuel = 0 then () else bounded_expansion_count_law (fuel - 1)

let run_route_once (route:route_code nat nat nat) (run_id:nat) (input:nat) (expected:nat)
  : Tot bool =
  let plan=so route in
  match open_run "examples-v1" run_id nat_codec plan input (clean_budget 8) with
  | None -> false
  | Some initial ->
    let first=resume_evaluate "examples-v1" nat_codec plan initial in
    match first.actions with
    | SaveExpansion record :: [] ->
      (match commit initial (ExpansionSaved record) with
       | None -> false
       | Some saved ->
         (match storage_roundtrip saved with
          | None -> false
          | Some restored ->
            let resumed=resume_evaluate "examples-v1" nat_codec plan restored in
            resumed.value = Some expected && state_is_replay_valid restored))
    | _ -> false

let test_routes () : Tot bool =
  let changed_child={child_route with resolve=(fun _ -> Some (add_flow 99))} in
  let plan=so child_route in
  let changed_plan=so changed_child in
  let changed_child_rejected =
    match open_run "examples-v1" 28 nat_codec plan 5 (clean_budget 8) with
    | None -> false
    | Some initial ->
      (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
       | SaveExpansion expansion :: [] ->
         (match commit initial (ExpansionSaved expansion) with
          | Some saved -> (resume_evaluate "examples-v1" nat_codec changed_plan saved).failure <> None
          | None -> false)
       | _ -> false) in
  run_route_once direct_route 21 5 15 && run_route_once child_route 22 5 9 &&
  changed_child_rejected

let test_multi_operation_child () : Tot bool =
  let plan=so parallel_child_route in
  match open_run "examples-v1" 25 nat_codec plan 5 (clean_budget 4) with
  | None -> false
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
     | SaveExpansion expansion :: [] ->
       (match commit initial (ExpansionSaved expansion) with
        | None -> false
        | Some saved ->
          match (resume_evaluate "examples-v1" nat_codec plan saved).actions with
          | PrepareOperation left :: PrepareOperation right :: [] ->
            left.occurrence.path <> right.occurrence.path &&
            left.occurrence.run_id = 25 && right.occurrence.run_id = 25 &&
            left.operation_id = "child-left" && right.operation_id = "child-right"
          | _ -> false)
     | _ -> false)

let test_resource_boundary_route () : Tot bool =
  let plan=so resource_boundary_route in
  let case (run_id:nat) (limit:nat) (expected:nat) : bool =
    match open_run "examples-v1" run_id nat_codec plan 1 (clean_budget limit) with
    | None -> false
    | Some initial ->
      (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
       | SaveExpansion expansion :: [] ->
         (match commit initial (ExpansionSaved expansion) with
          | None -> false
          | Some saved ->
            (resume_evaluate "examples-v1" nat_codec plan saved).value = Some expected &&
            expansion.snapshot = clean_budget limit && storage_roundtrip saved = Some saved)
       | _ -> false) in
  case 26 3 3 && case 27 2 0

let test_bounded_nested_route () : Tot bool =
  let plan=so (bounded_route 3) in
  match open_run "examples-v1" 23 nat_codec plan 4 (clean_budget 8) with
  | None -> false
  | Some initial ->
    let rec drive (state:durable_state) (remaining:nat) : Tot bool (decreases remaining) =
      let current=resume_evaluate "examples-v1" nat_codec plan state in
      match current.value, current.actions with
      | Some result, [] -> result = 1 && remaining = 0 && state_is_replay_valid state
      | None, SaveExpansion expansion :: [] ->
        (match commit state (ExpansionSaved expansion) with
         | None -> false
         | Some next -> if remaining = 0 then false else drive next (remaining - 1))
      | _, _ -> false in
    drive initial 4

let test_budget_accounting () : Tot bool =
  let plan=external (op_spec "budget" 5 7) in
  match open_run "examples-v1" 30 nat_codec plan 1 (clean_budget 5) with
  | None -> false
  | Some initial ->
    let action=(resume_evaluate "examples-v1" nat_codec plan initial).actions in
    match action with
    | PrepareOperation intent :: [] ->
      (match commit initial (OperationPrepared intent) with
       | None -> false
       | Some reserved ->
         let unknown=commit reserved
           (OperationStatusChanged intent.occurrence intent.attempt Unknown) in
         match unknown with
         | None -> false
         | Some unresolved ->
           let still_reserved=unresolved.budget.reserved = 5 in
           let success=commit unresolved
             (OperationStatusChanged intent.occurrence intent.attempt (Succeeded (WNat 7) 5)) in
           match success with
           | None -> false
           | Some finished -> still_reserved && finished.budget.spent = 5 &&
             finished.budget.reserved = 0 && state_is_replay_valid finished
             && commit finished
               (OperationPrepared { intent with attempt=1 }) = None
      )
    | _ -> false

let test_not_applied_retry () : Tot bool =
  let plan=external (op_spec "retry" 3 7) in
  match open_run "examples-v1" 31 nat_codec plan 1 (clean_budget 3) with
  | None -> false
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
     | PrepareOperation intent :: [] ->
       (match commit initial (OperationPrepared intent) with
        | None -> false
        | Some prepared ->
          (match commit prepared (OperationStatusChanged intent.occurrence intent.attempt Unknown) with
           | None -> false
           | Some unknown ->
             let wrong=commit unknown
               (OperationNotAppliedConfirmed intent.occurrence intent.attempt "wrong-adapter" "receipt-1") in
             (match commit unknown
                (OperationNotAppliedConfirmed intent.occurrence intent.attempt intent.capability "receipt-1") with
              | None -> false
              | Some released ->
                (match (resume_evaluate "examples-v1" nat_codec plan released).actions with
                 | PrepareOperation retry :: [] ->
                   (match commit released (OperationPrepared retry) with
                    | None -> false
                    | Some retried ->
                      (match commit retried
                         (OperationStatusChanged retry.occurrence retry.attempt (Failed "scripted")) with
                       | None -> false
                       | Some failed_state ->
                         wrong = None && retry.attempt = intent.attempt + 1 &&
                         released.budget.reserved = 0 && failed_state.budget.spent = 3 &&
                         state_is_replay_valid failed_state &&
                         storage_roundtrip failed_state = Some failed_state))
                 | _ -> false))))
     | _ -> false)

let test_failure_and_cancellation () : Tot bool =
  let case (run_id:nat) (status:op_status) : bool =
    let plan=external (op_spec "terminal" 2 7) in
    match open_run "examples-v1" run_id nat_codec plan 1 (clean_budget 2) with
    | None -> false
    | Some initial ->
      (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
       | PrepareOperation intent :: [] ->
         (match commit initial (OperationPrepared intent) with
          | None -> false
          | Some prepared ->
            (match commit prepared
              (OperationStatusChanged intent.occurrence intent.attempt status) with
             | None -> false
             | Some terminal ->
               let again=commit terminal
                 (OperationStatusChanged intent.occurrence intent.attempt status) in
               terminal.budget.spent = 2 && terminal.budget.reserved = 0 &&
               state_is_replay_valid terminal && again <> None))
       | _ -> false) in
  case 32 (Failed "scripted failure") && case 33 (Cancelled "scripted cancellation")

let test_artifacts () : Tot bool =
  let plan=add_flow 1 in
  match open_run "examples-v1" 50 nat_codec plan 2 (clean_budget 4) with
  | None -> false
  | Some initial ->
    let producer={run_id=50; path=[]} in
    let tree : blob_tree = [([[97; 98]], [65; 66; 67])] in
    let good_tree={artifact_id="tree"; kind=BlobTree;
      codec=tag_of_codec blob_tree_codec; contents=blob_tree_codec.encode tree;
      producer=producer; provenance=[]; validation=Some ("tree.v1", 1);
      materialization_available=false} in
    let bad_tree={good_tree with artifact_id="bad-tree";
      contents=blob_tree_codec.encode [([], [65])]} in
    let bad_materialized={good_tree with artifact_id="live-path"; kind=MaterializedFile;
      materialization_available=true} in
    let bad_ref={artifact_id="bad-ref"; kind=DurableReference;
      codec=tag_of_codec durable_reference_codec; contents=WText "https://example/object";
      producer=producer; provenance=[]; validation=None; materialization_available=false} in
    let root={artifact_id="root"; kind=BlobBytes; codec=tag_of_codec blob_bytes_codec;
      contents=WBytes [1; 2; 255]; producer=producer; provenance=[]; validation=None;
      materialization_available=false} in
    let child={artifact_id="child"; kind=TypedValue; codec=tag_of_codec nat_codec;
      contents=WNat 9; producer=producer; provenance=["root"]; validation=None;
      materialization_available=false} in
    let missing_parent={child with artifact_id="orphan"; provenance=["absent"]} in
    let saved=commit initial (ArtifactSaved root) in
    match saved with
    | None -> false
    | Some root_saved ->
      match commit root_saved (ArtifactSaved child) with
      | None -> false
      | Some complete ->
        valid_artifact 50 good_tree && not (valid_artifact 50 bad_tree) &&
        not (valid_artifact 50 bad_materialized) && not (valid_artifact 50 bad_ref) &&
        commit complete (ArtifactSaved missing_parent) = None &&
        state_is_replay_valid complete && storage_roundtrip complete = Some complete

let test_identity_route () : Tot bool =
  let identity : route_code nat nat nat = {
    route_id="example.identity"; route_version=1;
    resolver_id="example.identity-resolver"; resolver_version=1;
    capture_codec=nat_codec; input_codec=nat_codec; output_codec=nat_codec;
    capture=0; choose=(fun _ input _ -> Return input); resolve=(fun _ -> None)
  } in
  run_route_once identity 24 42 42

let test_pair_codec_versions () : Tot bool =
  let left_v2={nat_codec with codec_version=2} in
  let right_v3={nat_codec with codec_version=3} in
  let base=pair_codec nat_codec nat_codec in
  let left_changed=pair_codec left_v2 nat_codec in
  let right_changed=pair_codec nat_codec right_v3 in
  let split_left={nat_codec with codec_id="x,y"} in
  let split_right={nat_codec with codec_id="z"} in
  let joined_left={nat_codec with codec_id="x"} in
  let joined_right={nat_codec with codec_id="y,z"} in
  let delimiter_left=pair_codec split_left split_right in
  let delimiter_right=pair_codec joined_left joined_right in
  let plan=pure sum_pair_code in
  let tags_distinct=tag_of_codec base <> tag_of_codec left_changed &&
                    tag_of_codec base <> tag_of_codec right_changed &&
                    tag_of_codec delimiter_left <> tag_of_codec delimiter_right in
  let wire_roundtrip=decode_codec_tag (encode_codec_tag (tag_of_codec left_changed)) =
                     Some (tag_of_codec left_changed) in
  match open_run "examples-v1" 41 base plan (2, 3) (clean_budget 0) with
  | None -> false
  | Some state ->
      tags_distinct && wire_roundtrip &&
      (resume_evaluate "examples-v1" base plan state).value = Some 5 &&
      (resume_evaluate "examples-v1" left_changed plan state).failure <> None &&
      (resume_evaluate "examples-v1" right_changed plan state).failure <> None

let test_recorded_nondeterminism () : Tot bool =
  let plan=external (op_spec "clock.sample" 0 0) in
  let sample:nat=1700000000 in
  match open_run "examples-v1" 39 nat_codec plan 0 (clean_budget 0) with
  | None -> false
  | Some initial ->
    (match (resume_evaluate "examples-v1" nat_codec plan initial).actions with
     | PrepareOperation intent :: [] ->
       (match commit initial (OperationPrepared intent) with
        | None -> false
        | Some prepared ->
          let dispatch=(resume_evaluate "examples-v1" nat_codec plan prepared).actions in
          (match commit prepared (OperationStatusChanged intent.occurrence intent.attempt
                    (Succeeded (WNat sample) 0)) with
           | None -> false
           | Some observed ->
             let restored=storage_roundtrip observed in
             let resumed=match restored with
               | Some state -> (resume_evaluate "examples-v1" nat_codec plan state).value = Some sample
               | None -> false in
             resumed && (match dispatch with
               | DispatchOperation where attempt :: [] ->
                 occurrence_equal where intent.occurrence && attempt=intent.attempt
               | _ -> false)))
     | _ -> false)

let test_invalid_durable_inputs () : Tot bool =
  let plan=add_flow 1 in
  match open_run "examples-v1" 40 nat_codec plan 2 (clean_budget 4) with
  | None -> false
  | Some state ->
    let malformed={state with header={state.header with root_input=WText "bad"}} in
    let changed_valid_root={state with header={state.header with root_input=WNat 50}} in
    let changed=resume_evaluate "examples-v1" nat_codec plan
      {state with header={state.header with build_id="other-build"}} in
    (resume_evaluate "examples-v1" nat_codec plan malformed).failure <> None &&
    changed.failure <> None &&
    state_is_replay_valid changed_valid_root &&
    (resume_evaluate "examples-v1" nat_codec plan changed_valid_root).value = Some 51

let all_tests () : Tot bool =
  test_local_api () && test_external_fork () && test_routes () && test_identity_route () &&
  test_pair_codec_versions () &&
  test_multi_operation_child () && test_resource_boundary_route () && test_crash_after_intent () &&
  test_bounded_nested_route () &&
  test_budget_accounting () && test_not_applied_retry () && test_failure_and_cancellation () &&
  test_artifacts () && test_recorded_nondeterminism () && test_invalid_durable_inputs ()

let main () : Tot nat = if all_tests () then 0 else 1
