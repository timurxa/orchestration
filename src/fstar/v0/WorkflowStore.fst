module WorkflowStore
open FStar.List.Tot
open WorkflowCore

// Stable, versioned positional wire schema. The OCaml host serializes only `wire`.
let rec encode_list (#a:Type0) (encode:a -> Tot wire) (xs:list a)
  : Tot wire (decreases xs) =
  match xs with
  | [] -> WList []
  | x::rest ->
    (match encode_list encode rest with
     | WList tail -> WList (encode x :: tail)
     | _ -> WList [])

let rec decode_list_items (#a:Type0) (decode:wire -> Tot (option a)) (xs:list wire)
  : Tot (option (list a)) (decreases xs) =
  match xs with
  | [] -> Some []
  | x::rest ->
    (match decode x, decode_list_items decode rest with
     | Some head, Some tail -> Some (head::tail)
     | _, _ -> None)

let decode_list (#a:Type0) (decode:wire -> Tot (option a)) (value:wire)
  : Tot (option (list a)) =
  match value with | WList xs -> decode_list_items decode xs | _ -> None

let encode_option (#a:Type0) (encode:a -> Tot wire) (value:option a) : wire =
  match value with | None -> WOption None | Some x -> WOption (Some (encode x))

let decode_option (#a:Type0) (decode:wire -> Tot (option a)) (value:wire)
  : Tot (option (option a)) =
  match value with
  | WOption None -> Some None
  | WOption (Some x) -> (match decode x with | Some y -> Some (Some y) | None -> None)
  | _ -> None

let encode_codec_tag (x:codec_tag) : wire = WList [WText x.tag_id; WNat x.tag_version]
let decode_codec_tag (x:wire) : Tot (option codec_tag) =
  match x with | WList [WText id; WNat version] -> Some {tag_id=id; tag_version=version} | _ -> None

let encode_budget (x:budget) : wire = WList [WNat x.limit; WNat x.spent; WNat x.reserved]
let decode_budget (x:wire) : Tot (option budget) =
  match x with
  | WList [WNat limit; WNat spent; WNat reserved] ->
    let b={limit=limit; spent=spent; reserved=reserved} in
    if valid_budget b then Some b else None
  | _ -> None

let encode_path_segment (x:path_segment) : wire =
  match x with
  | ThenLeft -> WList [WNat 0]
  | ThenRight -> WList [WNat 1]
  | ForkLeft -> WList [WNat 2]
  | ForkRight -> WList [WNat 3]
  | LiftList index -> WList [WNat 4; WNat index]
  | LiftOption -> WList [WNat 5]
  | LiftProductLeft -> WList [WNat 6]
  | LiftProductRight -> WList [WNat 7]
  | ExpandChild id -> WList [WNat 8; WText id]

let decode_path_segment (x:wire) : Tot (option path_segment) =
  match x with
  | WList [WNat 0] -> Some ThenLeft
  | WList [WNat 1] -> Some ThenRight
  | WList [WNat 2] -> Some ForkLeft
  | WList [WNat 3] -> Some ForkRight
  | WList [WNat 4; WNat index] -> Some (LiftList index)
  | WList [WNat 5] -> Some LiftOption
  | WList [WNat 6] -> Some LiftProductLeft
  | WList [WNat 7] -> Some LiftProductRight
  | WList [WNat 8; WText id] -> Some (ExpandChild id)
  | _ -> None

let encode_occurrence (x:occurrence) : Tot wire =
  WList [WNat x.run_id; encode_list encode_path_segment x.path]
let decode_occurrence (x:wire) : Tot (option occurrence) =
  match x with
  | WList [WNat run_id; path_wire] ->
    (match decode_list decode_path_segment path_wire with
     | Some path -> Some {run_id=run_id; path=path}
     | None -> None)
  | _ -> None

let encode_code_tag (x:code_tag) : wire =
  WList [WText x.code_id; WNat x.code_version; encode_codec_tag x.capture_tag; x.capture_data]
let decode_code_tag (x:wire) : Tot (option code_tag) =
  match x with
  | WList [WText code_id; WNat code_version; tag_wire; capture_data] ->
    (match decode_codec_tag tag_wire with
     | Some capture_tag -> Some {code_id=code_id; code_version=code_version;
                                 capture_tag=capture_tag; capture_data=capture_data}
     | None -> None)
  | _ -> None

let rec encode_shape (x:shape) : Tot wire (decreases x) =
  match x with
  | Id -> WList [WNat 0]
  | Lists inner -> WList [WNat 1; encode_shape inner]
  | Options inner -> WList [WNat 2; encode_shape inner]
  | Products left right -> WList [WNat 3; encode_shape left; encode_shape right]

let rec decode_shape (x:wire) : Tot (option shape) (decreases x) =
  match x with
  | WList [WNat 0] -> Some Id
  | WList [WNat 1; inner] -> (match decode_shape inner with | Some s -> Some (Lists s) | None -> None)
  | WList [WNat 2; inner] -> (match decode_shape inner with | Some s -> Some (Options s) | None -> None)
  | WList [WNat 3; left; right] ->
    (match decode_shape left, decode_shape right with
     | Some l, Some r -> Some (Products l r)
     | _, _ -> None)
  | _ -> None

let rec encode_manifest (x:plan_manifest) : Tot wire (decreases x) =
  match x with
  | MPure code input output -> WList [WNat 0; encode_code_tag code;
                                       encode_codec_tag input; encode_codec_tag output]
  | MThen left right -> WList [WNat 1; encode_manifest left; encode_manifest right]
  | MFork left right -> WList [WNat 2; encode_manifest left; encode_manifest right]
  | MLift shape inner -> WList [WNat 3; encode_shape shape; encode_manifest inner]
  | MExternal op capability version capture capture_tag input output charge ->
    WList [WNat 4; WText op; WText capability; WNat version; capture;
           encode_codec_tag capture_tag; encode_codec_tag input;
           encode_codec_tag output; WNat charge]
  | MSo code input output resolver resolver_version ->
    WList [WNat 5; encode_code_tag code; encode_codec_tag input;
           encode_codec_tag output; WText resolver; WNat resolver_version]

let rec decode_manifest (x:wire) : Tot (option plan_manifest) (decreases x) =
  match x with
  | WList [WNat 0; code; input; output] ->
    (match decode_code_tag code, decode_codec_tag input, decode_codec_tag output with
     | Some c, Some i, Some o -> Some (MPure c i o) | _, _, _ -> None)
  | WList [WNat 1; left; right] ->
    (match decode_manifest left, decode_manifest right with
     | Some l, Some r -> Some (MThen l r) | _, _ -> None)
  | WList [WNat 2; left; right] ->
    (match decode_manifest left, decode_manifest right with
     | Some l, Some r -> Some (MFork l r) | _, _ -> None)
  | WList [WNat 3; shape; inner] ->
    (match decode_shape shape, decode_manifest inner with
     | Some s, Some p -> Some (MLift s p) | _, _ -> None)
  | WList [WNat 4; WText op; WText capability; WNat version; capture;
           capture_tag; input; output; WNat charge] ->
    (match decode_codec_tag capture_tag, decode_codec_tag input, decode_codec_tag output with
     | Some c, Some i, Some o -> Some (MExternal op capability version capture c i o charge)
     | _, _, _ -> None)
  | WList [WNat 5; code; input; output; WText resolver; WNat resolver_version] ->
    (match decode_code_tag code, decode_codec_tag input, decode_codec_tag output with
     | Some c, Some i, Some o -> Some (MSo c i o resolver resolver_version)
     | _, _, _ -> None)
  | _ -> None

let encode_child_ref (x:child_ref) : wire =
  WList [WText x.child_id; WNat x.child_version; encode_codec_tag x.child_capture_tag; x.child_capture]
let decode_child_ref (x:wire) : Tot (option child_ref) =
  match x with
  | WList [WText child_id; WNat child_version; tag_wire; child_capture] ->
    (match decode_codec_tag tag_wire with
     | Some child_capture_tag -> Some {child_id=child_id; child_version=child_version;
                                       child_capture_tag=child_capture_tag; child_capture=child_capture}
     | None -> None)
  | _ -> None

let encode_choice (x:route_choice) : wire =
  match x with
  | ReturnWire output -> WList [WNat 0; output]
  | Child child -> WList [WNat 1; encode_child_ref child]
let decode_choice (x:wire) : Tot (option route_choice) =
  match x with
  | WList [WNat 0; output] -> Some (ReturnWire output)
  | WList [WNat 1; child] -> (match decode_child_ref child with | Some r -> Some (Child r) | None -> None)
  | _ -> None

let encode_status (x:op_status) : wire =
  match x with
  | Prepared -> WList [WNat 0]
  | Pending -> WList [WNat 1]
  | Unknown -> WList [WNat 2]
  | Succeeded output actual -> WList [WNat 3; output; WNat actual]
  | Failed message -> WList [WNat 4; WText message]
  | Cancelled message -> WList [WNat 5; WText message]
  | NotApplied evidence -> WList [WNat 6; WText evidence]
let decode_status (x:wire) : Tot (option op_status) =
  match x with
  | WList [WNat 0] -> Some Prepared
  | WList [WNat 1] -> Some Pending
  | WList [WNat 2] -> Some Unknown
  | WList [WNat 3; output; WNat actual] -> Some (Succeeded output actual)
  | WList [WNat 4; WText message] -> Some (Failed message)
  | WList [WNat 5; WText message] -> Some (Cancelled message)
  | WList [WNat 6; WText evidence] ->
    if evidence <> "" then Some (NotApplied evidence) else None
  | _ -> None

let encode_operation (x:op_record) : wire =
  WList [encode_occurrence x.occurrence; WNat x.decision_sequence; WText x.capability;
    WText x.operation_id; WNat x.operation_version; x.capture; encode_codec_tag x.capture_tag;
    x.request; encode_codec_tag x.input_tag; encode_codec_tag x.output_tag; WNat x.reservation;
    encode_budget x.reservation_snapshot; WNat x.attempt; encode_status x.status]
let decode_operation (x:wire) : Tot (option op_record) =
  match x with
  | WList [where; WNat decision_sequence; WText capability; WText operation_id;
    WNat operation_version; capture; capture_tag; request; input_tag; output_tag;
    WNat reservation; snapshot; WNat attempt; status] ->
    (match decode_occurrence where, decode_codec_tag capture_tag, decode_codec_tag input_tag,
           decode_codec_tag output_tag, decode_budget snapshot, decode_status status with
     | Some occurrence, Some capture_tag, Some input_tag, Some output_tag,
       Some reservation_snapshot, Some status ->
       Some {occurrence=occurrence; decision_sequence=decision_sequence; capability=capability;
        operation_id=operation_id; operation_version=operation_version; capture=capture;
        capture_tag=capture_tag; request=request; input_tag=input_tag; output_tag=output_tag;
        reservation=reservation; reservation_snapshot=reservation_snapshot; attempt=attempt;
        status=status}
     | _, _, _, _, _, _ -> None)
  | _ -> None

let encode_expansion (x:expansion_record) : wire =
  WList [encode_occurrence x.occurrence; WNat x.decision_sequence; WText x.route_id;
    WNat x.route_version; x.route_capture; encode_codec_tag x.route_capture_tag;
    encode_codec_tag x.input_tag; encode_codec_tag x.output_tag; WText x.resolver_id;
    WNat x.resolver_version; x.input; encode_budget x.snapshot; encode_choice x.choice;
    encode_option encode_manifest x.child_manifest]
let decode_expansion (x:wire) : Tot (option expansion_record) =
  match x with
  | WList [where; WNat decision_sequence; WText route_id; WNat route_version;
    route_capture; route_capture_tag; input_tag; output_tag; WText resolver_id;
    WNat resolver_version; input; snapshot; choice; child_manifest] ->
    (match decode_occurrence where, decode_codec_tag route_capture_tag,
      decode_codec_tag input_tag, decode_codec_tag output_tag, decode_budget snapshot,
      decode_choice choice, decode_option decode_manifest child_manifest with
     | Some occurrence, Some route_capture_tag, Some input_tag, Some output_tag,
       Some snapshot, Some choice, Some child_manifest ->
       Some {occurrence=occurrence; decision_sequence=decision_sequence; route_id=route_id;
        route_version=route_version; route_capture=route_capture; route_capture_tag=route_capture_tag;
        input_tag=input_tag; output_tag=output_tag; resolver_id=resolver_id;
        resolver_version=resolver_version; input=input; snapshot=snapshot; choice=choice;
        child_manifest=child_manifest}
     | _, _, _, _, _, _, _ -> None)
  | _ -> None

let encode_artifact_kind (x:artifact_kind) : wire =
  match x with
  | TypedValue -> WNat 0 | BlobBytes -> WNat 1 | BlobTree -> WNat 2
  | OperationInput -> WNat 3 | MaterializedFile -> WNat 4
  | DurableReference -> WNat 5 | LiveCapability -> WNat 6
let decode_artifact_kind (x:wire) : Tot (option artifact_kind) =
  match x with
  | WNat 0 -> Some TypedValue | WNat 1 -> Some BlobBytes | WNat 2 -> Some BlobTree
  | WNat 3 -> Some OperationInput | WNat 4 -> Some MaterializedFile
  | WNat 5 -> Some DurableReference | WNat 6 -> Some LiveCapability
  | _ -> None

let encode_string (x:string) : wire = WText x
let decode_string (x:wire) : Tot (option string) = match x with | WText s -> Some s | _ -> None
let encode_artifact (x:artifact_record) : wire =
  let validation=match x.validation with
    | None -> WOption None
    | Some (name, version) -> WOption (Some (WPair (WText name) (WNat version))) in
  WList [WText x.artifact_id; encode_artifact_kind x.kind; encode_codec_tag x.codec;
    x.contents; encode_occurrence x.producer; encode_list encode_string x.provenance;
    validation; WBool x.materialization_available]
let decode_artifact (x:wire) : Tot (option artifact_record) =
  match x with
  | WList [WText artifact_id; kind; codec; contents; producer; provenance; validation; WBool available] ->
    let decode_validation v = match v with
      | WOption None -> Some None
      | WOption (Some (WPair (WText name) (WNat version))) -> Some (Some (name, version))
      | _ -> None in
    (match decode_artifact_kind kind, decode_codec_tag codec, decode_occurrence producer,
           decode_list decode_string provenance, decode_validation validation with
     | Some kind, Some codec, Some producer, Some provenance, Some validation ->
       Some {artifact_id=artifact_id; kind=kind; codec=codec; contents=contents;
         producer=producer; provenance=provenance; validation=validation;
         materialization_available=available}
     | _, _, _, _, _ -> None)
  | _ -> None

let encode_event_body (x:event_body) : wire =
  match x with
  | ExpansionSaved expansion -> WList [WNat 0; encode_expansion expansion]
  | OperationPrepared operation -> WList [WNat 1; encode_operation operation]
  | OperationStatusChanged where attempt status ->
    WList [WNat 2; encode_occurrence where; WNat attempt; encode_status status]
  | OperationNotAppliedConfirmed where attempt adapter evidence ->
    WList [WNat 3; encode_occurrence where; WNat attempt; WText adapter; WText evidence]
  | ArtifactSaved artifact -> WList [WNat 4; encode_artifact artifact]
let decode_event_body (x:wire) : Tot (option event_body) =
  match x with
  | WList [WNat 0; expansion] ->
    (match decode_expansion expansion with | Some e -> Some (ExpansionSaved e) | None -> None)
  | WList [WNat 1; operation] ->
    (match decode_operation operation with | Some o -> Some (OperationPrepared o) | None -> None)
  | WList [WNat 2; where; WNat attempt; status] ->
    (match decode_occurrence where, decode_status status with
     | Some o, Some s -> Some (OperationStatusChanged o attempt s) | _, _ -> None)
  | WList [WNat 3; where; WNat attempt; WText adapter; WText evidence] ->
    if adapter = "" || evidence = "" then None else
    (match decode_occurrence where with
     | Some o -> Some (OperationNotAppliedConfirmed o attempt adapter evidence)
     | _ -> None)
  | WList [WNat 4; artifact] ->
    (match decode_artifact artifact with | Some a -> Some (ArtifactSaved a) | None -> None)
  | _ -> None

let encode_event (x:journal_event) : wire = WList [WNat x.sequence; encode_event_body x.body]
let decode_event (x:wire) : Tot (option journal_event) =
  match x with
  | WList [WNat sequence; body] ->
    (match decode_event_body body with | Some b -> Some {sequence=sequence; body=b} | None -> None)
  | _ -> None

let encode_header (x:run_header) : wire =
  WList [WNat x.run_id; WText x.build_id; encode_manifest x.root_manifest;
    encode_codec_tag x.root_input_tag; x.root_input; encode_budget x.initial_budget]
let decode_header (x:wire) : Tot (option run_header) =
  match x with
  | WList [WNat run_id; WText build_id; manifest; input_tag; input; initial_budget] ->
    if build_id = "" then None else
    (match decode_manifest manifest, decode_codec_tag input_tag, decode_budget initial_budget with
     | Some root_manifest, Some root_input_tag, Some initial_budget ->
       Some {run_id=run_id; build_id=build_id; root_manifest=root_manifest;
        root_input_tag=root_input_tag; root_input=input; initial_budget=initial_budget}
     | _, _, _ -> None)
  | _ -> None

let encode_state (x:durable_state) : Tot (option wire) =
  if not (state_is_replay_valid x) then None
  else Some (WList [WNat 1; encode_header x.header; encode_list encode_event x.journal])

let decode_state (x:wire) : Tot (option durable_state) =
  match x with
  | WList [WNat 1; header; events] ->
    (match decode_header header, decode_list decode_event events with
     | Some decoded_header, Some decoded_events -> replay decoded_header decoded_events
     | _, _ -> None)
  | _ -> None

let wire_schema_version : nat = 1
