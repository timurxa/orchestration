module WorkflowCore
open FStar.String
open FStar.List.Tot

// Durable values cross the process boundary only through explicit codecs.
type wire =
  | WNat : nat -> wire
  | WBool : bool -> wire
  | WText : string -> wire
  | WBytes : list nat -> wire
  | WList : list wire -> wire
  | WPair : wire -> wire -> wire
  | WOption : option wire -> wire

noeq type codec (a:Type0) = {
  codec_id:string;
  codec_version:nat;
  encode:a -> Tot wire;
  decode:wire -> Tot (option a);
  roundtrip:x:a -> Lemma (decode (encode x) == Some x)
}

let nat_codec : codec nat = {
  codec_id="core.nat"; codec_version=1;
  encode=(fun n -> WNat n);
  decode=(fun w -> match w with | WNat n -> Some n | _ -> None);
  roundtrip=(fun _ -> ())
}

let text_codec : codec string = {
  codec_id="core.text"; codec_version=1;
  encode=(fun s -> WText s);
  decode=(fun w -> match w with | WText s -> Some s | _ -> None);
  roundtrip=(fun _ -> ())
}

let bool_codec : codec bool = {
  codec_id="core.bool"; codec_version=1;
  encode=(fun b -> WBool b);
  decode=(fun w -> match w with | WBool b -> Some b | _ -> None);
  roundtrip=(fun _ -> ())
}

// Cantor pairing keeps both component codec versions in the composite tag.
let pair_codec_version (left_version:nat) (right_version:nat) : nat =
  let sum_versions=left_version + right_version in
  sum_versions * (sum_versions + 1) / 2 + right_version

// Escape the composite grammar's delimiters so pair IDs cannot alias when
// component IDs themselves contain commas, parentheses, or backslashes.
let rec escape_codec_id_chars (chars:list char) : Tot string (decreases chars) =
  match chars with
  | [] -> ""
  | ch::rest ->
      let encoded=if ch = '\\' || ch = '(' || ch = ')' || ch = ','
                  then "\\" ^ string_of_char ch
                  else string_of_char ch in
      encoded ^ escape_codec_id_chars rest

let escape_codec_id (id:string) : string =
  escape_codec_id_chars (list_of_string id)

let pair_codec (#a #b:Type0) (left:codec a) (right:codec b) : codec (a & b) = {
  codec_id="core.pair(" ^ escape_codec_id left.codec_id ^ "," ^ escape_codec_id right.codec_id ^ ")";
  codec_version=pair_codec_version left.codec_version right.codec_version;
  encode=(fun (x, y) -> WPair (left.encode x) (right.encode y));
  decode=(fun wire -> match wire with
    | WPair l r -> (match left.decode l, right.decode r with
                    | Some x, Some y -> Some (x, y) | _, _ -> None)
    | _ -> None);
  roundtrip=(fun (x, y) -> left.roundtrip x; right.roundtrip y)
}

// BlobTree paths are lists of Unicode scalar values per segment. The host
// materializer hex-encodes each scalar, so separators and traversal strings
// cannot escape the materialization root.
type blob_tree = list ((list (list nat)) & list nat)
type durable_reference = { reference_uri:string; reference_digest:string }

let blob_bytes_codec : codec (list nat) = {
  codec_id="core.blob-bytes"; codec_version=1;
  encode=(fun bytes -> WBytes bytes);
  decode=(fun wire -> match wire with | WBytes bytes -> Some bytes | _ -> None);
  roundtrip=(fun _ -> ())
}

let durable_reference_codec : codec durable_reference = {
  codec_id="core.durable-reference"; codec_version=1;
  encode=(fun ref -> WPair (WText ref.reference_uri) (WText ref.reference_digest));
  decode=(fun wire -> match wire with
          | WPair (WText uri) (WText digest) -> Some {reference_uri=uri; reference_digest=digest}
          | _ -> None);
  roundtrip=(fun _ -> ())
}

let rec encode_nat_values (xs:list nat) : wire =
  match xs with | [] -> WList [] | x::rest ->
    (match encode_nat_values rest with | WList tail -> WList (WNat x::tail) | _ -> WList [])

let rec decode_nat_list (xs:list wire) : Tot (option (list nat)) (decreases xs) =
  match xs with
  | [] -> Some []
  | WNat n::rest ->
    (match decode_nat_list rest with | Some tail -> Some (n::tail) | None -> None)
  | _::_ -> None

let decode_nat_values (x:wire) : Tot (option (list nat)) =
  match x with | WList xs -> decode_nat_list xs | _ -> None

let rec encode_tree_path (path:list (list nat)) : wire =
  match path with | [] -> WList [] | segment::rest ->
    (match encode_tree_path rest with | WList tail -> WList (encode_nat_values segment::tail) | _ -> WList [])

let rec decode_tree_path_list (xs:list wire) : Tot (option (list (list nat))) (decreases xs) =
  match xs with
  | [] -> Some []
  | segment::rest ->
    (match decode_nat_values segment, decode_tree_path_list rest with
     | Some value, Some tail -> Some (value::tail)
     | _, _ -> None)

let decode_tree_path (x:wire) : Tot (option (list (list nat))) =
  match x with | WList xs -> decode_tree_path_list xs | _ -> None

let rec encode_tree_entries (tree:blob_tree) : wire =
  match tree with
  | [] -> WList []
  | (path, bytes)::rest ->
    (match encode_tree_entries rest with
     | WList tail -> WList (WPair (encode_tree_path path) (WBytes bytes)::tail)
     | _ -> WList [])

let rec decode_tree_entry_list (xs:list wire) : Tot (option blob_tree) (decreases xs) =
  match xs with
  | [] -> Some []
  | WPair path_wire (WBytes bytes)::rest ->
    (match decode_tree_path path_wire, decode_tree_entry_list rest with
     | Some path, Some tail -> Some ((path, bytes)::tail)
     | _, _ -> None)
  | _::_ -> None

let decode_tree_entries (x:wire) : Tot (option blob_tree) =
  match x with | WList xs -> decode_tree_entry_list xs | _ -> None

let rec valid_scalars (xs:list nat) : bool =
  match xs with
  | [] -> true
  | x::rest -> x > 0 && x <= 1114111 && (x < 55296 || x > 57343) && valid_scalars rest

let rec valid_tree_tail (path:list (list nat)) : bool =
  match path with
  | [] -> true
  | segment::rest -> segment <> [] && valid_scalars segment && valid_tree_tail rest

let valid_tree_path (path:list (list nat)) : bool =
  match path with
  | [] -> false
  | segment::rest -> segment <> [] && valid_scalars segment && valid_tree_tail rest

let rec tree_path_prefix (left:list (list nat)) (right:list (list nat)) : bool =
  match left, right with
  | [], _ -> true
  | _, [] -> false
  | x::xs, y::ys -> x = y && tree_path_prefix xs ys

let tree_paths_conflict (left:list (list nat)) (right:list (list nat)) : bool =
  tree_path_prefix left right || tree_path_prefix right left

let rec no_tree_path_conflicts (path:list (list nat)) (tree:blob_tree) : bool =
  match tree with
  | [] -> true
  | (other, _)::rest -> not (tree_paths_conflict path other) && no_tree_path_conflicts path rest

let rec valid_bytes (xs:list nat) : bool =
  match xs with | [] -> true | x::rest -> x <= 255 && valid_bytes rest

let rec valid_blob_tree (tree:blob_tree) : bool =
  match tree with
  | [] -> true
  | (path, bytes)::rest -> valid_tree_path path && valid_bytes bytes &&
                           no_tree_path_conflicts path rest && valid_blob_tree rest

let rec nat_values_roundtrip (xs:list nat)
  : Lemma (decode_nat_values (encode_nat_values xs) = Some xs) (decreases xs) =
  match xs with | [] -> () | _::rest -> nat_values_roundtrip rest

let rec tree_path_roundtrip (path:list (list nat))
  : Lemma (decode_tree_path (encode_tree_path path) = Some path) (decreases path) =
  match path with
  | [] -> ()
  | segment::rest -> nat_values_roundtrip segment; tree_path_roundtrip rest

let rec blob_tree_roundtrip (tree:blob_tree)
  : Lemma (decode_tree_entries (encode_tree_entries tree) = Some tree) (decreases tree) =
  match tree with
  | [] -> ()
  | (path, bytes)::rest -> tree_path_roundtrip path; nat_values_roundtrip bytes; blob_tree_roundtrip rest

let blob_tree_codec : codec blob_tree = {
  codec_id="core.blob-tree"; codec_version=1;
  encode=encode_tree_entries;
  decode=decode_tree_entries;
  roundtrip=(fun tree -> blob_tree_roundtrip tree)
}

type codec_tag = { tag_id:string; tag_version:nat }
let tag_of_codec (#a:Type0) (c:codec a) : codec_tag = { tag_id=c.codec_id; tag_version=c.codec_version }

type shape =
  | Id
  | Lists : shape -> shape
  | Options : shape -> shape
  | Products : shape -> shape -> shape

let rec carrier (s:shape) (a:Type0) : Type0 =
  match s with
  | Id -> a
  | Lists t -> list (carrier t a)
  | Options t -> option (carrier t a)
  | Products t u -> (carrier t a & carrier u a)

type code_tag = {
  code_id:string;
  code_version:nat;
  capture_tag:codec_tag;
  capture_data:wire
}

type plan_manifest =
  | MPure : code_tag -> codec_tag -> codec_tag -> plan_manifest
  | MThen : plan_manifest -> plan_manifest -> plan_manifest
  | MFork : plan_manifest -> plan_manifest -> plan_manifest
  | MLift : shape -> plan_manifest -> plan_manifest
  | MExternal : string -> string -> nat -> wire -> codec_tag -> codec_tag -> codec_tag -> nat -> plan_manifest
  | MSo : code_tag -> codec_tag -> codec_tag -> string -> nat -> plan_manifest

type path_segment =
  | ThenLeft
  | ThenRight
  | ForkLeft
  | ForkRight
  | LiftList : nat -> path_segment
  | LiftOption
  | LiftProductLeft
  | LiftProductRight
  | ExpandChild : string -> path_segment

type path = list path_segment
type occurrence = { run_id:nat; path:path }

let rec path_equal (x:path) (y:path) : bool =
  match x, y with
  | [], [] -> true
  | a::xs, b::ys -> (a = b) && path_equal xs ys
  | _, _ -> false

let occurrence_equal (x:occurrence) (y:occurrence) : bool =
  x.run_id = y.run_id && path_equal x.path y.path

let path_append (p:path) (s:path_segment) : path = p @ [s]

type budget = {
  limit:nat;
  spent:nat;
  reserved:nat
}

let valid_budget (b:budget) : bool = b.spent + b.reserved <= b.limit
let available (b:budget) : nat =
  if b.spent + b.reserved <= b.limit then b.limit - (b.spent + b.reserved) else 0

let reserve (b:budget) (n:nat) : option budget =
  if valid_budget b && n <= available b
  then Some { b with reserved = b.reserved + n }
  else None

let settle_success (b:budget) (reserved:nat) (actual:nat) : option budget =
  if valid_budget b && reserved <= b.reserved && actual <= reserved
  then Some { b with reserved = b.reserved - reserved; spent = b.spent + actual }
  else None

let settle_failure (b:budget) (reserved:nat) : option budget =
  if valid_budget b && reserved <= b.reserved
  then Some { b with reserved = b.reserved - reserved; spent = b.spent + reserved }
  else None

let settle_not_applied (b:budget) (reserved:nat) : option budget =
  if valid_budget b && reserved <= b.reserved
  then Some { b with reserved = b.reserved - reserved }
  else None

let settle_unknown (b:budget) (reserved:nat) : option budget =
  if valid_budget b && reserved <= b.reserved then Some b else None

let reserve_preserves_budget (b:budget) (n:nat) (b':budget)
  : Lemma (reserve b n = Some b' ==> valid_budget b') = ()

let settle_success_preserves_budget (b:budget) (r:nat) (c:nat) (b':budget)
  : Lemma (settle_success b r c = Some b' ==> valid_budget b') = ()

let settle_failure_preserves_budget (b:budget) (r:nat) (b':budget)
  : Lemma (settle_failure b r = Some b' ==> valid_budget b') = ()

let settle_not_applied_preserves_budget (b:budget) (r:nat) (b':budget)
  : Lemma (settle_not_applied b r = Some b' ==> valid_budget b') = ()

type child_ref = {
  child_id:string;
  child_version:nat;
  child_capture_tag:codec_tag;
  child_capture:wire
}

type route_choice =
  | ReturnWire : wire -> route_choice
  | Child : child_ref -> route_choice

type op_status =
  | Prepared
  | Pending
  | Unknown
  | Succeeded : wire -> nat -> op_status
  | Failed : string -> op_status
  | Cancelled : string -> op_status
  | NotApplied : string -> op_status

type op_record = {
  occurrence:occurrence;
  decision_sequence:nat;
  capability:string;
  operation_id:string;
  operation_version:nat;
  capture:wire;
  capture_tag:codec_tag;
  request:wire;
  input_tag:codec_tag;
  output_tag:codec_tag;
  reservation:nat;
  reservation_snapshot:budget;
  attempt:nat;
  status:op_status
}

type expansion_record = {
  occurrence:occurrence;
  decision_sequence:nat;
  route_id:string;
  route_version:nat;
  route_capture:wire;
  route_capture_tag:codec_tag;
  input_tag:codec_tag;
  output_tag:codec_tag;
  resolver_id:string;
  resolver_version:nat;
  input:wire;
  snapshot:budget;
  choice:route_choice;
  child_manifest:option plan_manifest
}

type artifact_kind =
  | TypedValue
  | BlobBytes
  | BlobTree
  | OperationInput
  | MaterializedFile
  | DurableReference
  | LiveCapability

type artifact_record = {
  artifact_id:string;
  kind:artifact_kind;
  codec:codec_tag;
  contents:wire;
  producer:occurrence;
  provenance:list string;
  validation:option (string & nat);
  materialization_available:bool
}

type action =
  | SaveExpansion : expansion_record -> action
  | PrepareOperation : op_record -> action
  | DispatchOperation : occurrence -> nat -> action
  | ReconcileOperation : occurrence -> nat -> action

type event_body =
  | ExpansionSaved : expansion_record -> event_body
  | OperationPrepared : op_record -> event_body
  | OperationStatusChanged : occurrence -> nat -> op_status -> event_body
  | OperationNotAppliedConfirmed : occurrence -> nat -> string -> string -> event_body
  | ArtifactSaved : artifact_record -> event_body

type run_header = {
  run_id:nat;
  build_id:string;
  root_manifest:plan_manifest;
  root_input_tag:codec_tag;
  root_input:wire;
  initial_budget:budget
}

type journal_event = { sequence:nat; body:event_body }

type durable_state = {
  header:run_header;
  budget:budget;
  operations:list op_record;
  expansions:list expansion_record;
  artifacts:list artifact_record;
  journal:list journal_event
}

type context = {
  run_id:nat;
  event_sequence:nat;
  budget:budget;
  operations:list op_record;
  expansions:list expansion_record;
  artifacts:list artifact_record
}

noeq type evaluation (a:Type0) = {
  value:option a;
  actions:list action;
  failure:option string;
  blocked:bool
}

let completed (#a:Type0) (x:a) : evaluation a = {
  value=Some x; actions=[]; failure=None; blocked=false
}

let failed (#a:Type0) (message:string) : evaluation a = {
  value=None; actions=[]; failure=Some message; blocked=false
}

let blocked (#a:Type0) (actions:list action) : evaluation a = {
  value=None; actions; failure=None; blocked=true
}

let first_failure (a:option string) (b:option string) : option string =
  match a with | Some _ -> a | None -> b

let combine_evaluations (#a #b:Type0) (left:evaluation a) (right:evaluation b)
  : evaluation (a & b) = {
  value=(match left.value, right.value, left.failure, right.failure with
         | Some x, Some y, None, None -> Some (x, y)
         | _, _, _, _ -> None);
  actions=left.actions @ right.actions;
  failure=first_failure left.failure right.failure;
  blocked=left.blocked || right.blocked
}

let propagate (#a #b:Type0) (e:evaluation a) : evaluation b = {
  value=None; actions=e.actions; failure=e.failure; blocked=e.blocked
}

noeq type workflow (i:Type0) (o:Type0) = {
  manifest:plan_manifest;
  evaluate:context -> path -> i -> Tot (evaluation o)
}

noeq type code_ref (c:Type0) (i:Type0) (o:Type0) = {
  id:string;
  version:nat;
  capture_codec:codec c;
  input_codec:codec i;
  output_codec:codec o;
  capture:c;
  apply:c -> i -> Tot o
}

let pure (#c #i #o:Type0) (f:code_ref c i o) : workflow i o = {
  manifest=MPure
    { code_id=f.id; code_version=f.version;
      capture_tag=tag_of_codec f.capture_codec;
      capture_data=f.capture_codec.encode f.capture }
    (tag_of_codec f.input_codec) (tag_of_codec f.output_codec);
  evaluate=(fun _ _ x -> completed (f.apply f.capture x))
}

let then_flow (#i #m #o:Type0) (first:workflow i m) (second:workflow m o) : workflow i o = {
  manifest=MThen first.manifest second.manifest;
  evaluate=(fun ctx path x ->
    let left = first.evaluate ctx (path_append path ThenLeft) x in
    match left.failure, left.value with
    | Some _, _ -> propagate left
    | None, None -> propagate left
    | None, Some y -> second.evaluate ctx (path_append path ThenRight) y)
}

let fork (#i #a #b:Type0) (left:workflow i a) (right:workflow i b) : workflow i (a & b) = {
  manifest=MFork left.manifest right.manifest;
  evaluate=(fun ctx path x ->
    let l = left.evaluate ctx (path_append path ForkLeft) x in
    let r = right.evaluate ctx (path_append path ForkRight) x in
    combine_evaluations l r)
}

let rec eval_list (#a #b:Type0) (w:workflow a b) (ctx:context) (path:path)
  (index:nat) (xs:list a) : Tot (evaluation (list b)) (decreases xs) =
  match xs with
  | [] -> completed []
  | x::tail ->
    let head = w.evaluate ctx (path_append path (LiftList index)) x in
    let rest = eval_list w ctx path (index + 1) tail in
    {
      value=(match head.value, rest.value, head.failure, rest.failure with
             | Some y, Some ys, None, None -> Some (y::ys)
             | _, _, _, _ -> None);
      actions=head.actions @ rest.actions;
      failure=first_failure head.failure rest.failure;
      blocked=head.blocked || rest.blocked
    }

let eval_option (#a #b:Type0) (w:workflow a b) (ctx:context) (path:path)
  (x:option a) : Tot (evaluation (option b)) =
  match x with
  | None -> completed None
  | Some value ->
    let e = w.evaluate ctx (path_append path LiftOption) value in
    { value=(match e.value with | Some y -> Some (Some y) | None -> None);
      actions=e.actions; failure=e.failure; blocked=e.blocked }

let eval_product (#a #b #c #d:Type0)
  (left:workflow a b) (right:workflow c d)
  (ctx:context) (path:path) (x:a & c) : Tot (evaluation (b & d)) =
  let l = left.evaluate ctx (path_append path LiftProductLeft) x._1 in
  let r = right.evaluate ctx (path_append path LiftProductRight) x._2 in
  combine_evaluations l r

let rec lift (#a #b:Type0) (s:shape) (w:workflow a b)
  : Tot (workflow (carrier s a) (carrier s b)) (decreases s) =
  match s with
  | Id -> w
  | Lists t ->
    let inner = lift t w in
    { manifest=MLift s inner.manifest;
      evaluate=(fun ctx path xs -> eval_list inner ctx path 0 xs) }
  | Options t ->
    let inner = lift t w in
    { manifest=MLift s inner.manifest;
      evaluate=(fun ctx path xs -> eval_option inner ctx path xs) }
  | Products t u ->
    let left = lift t w in
    let right = lift u w in
    { manifest=MLift s w.manifest;
      evaluate=(fun ctx path xs -> eval_product left right ctx path xs) }

let rec find_operation (where:occurrence) (xs:list op_record)
  : Tot (option op_record) (decreases xs) =
  match xs with
  | [] -> None
  | x::rest -> if occurrence_equal where x.occurrence then Some x else find_operation where rest

let rec find_expansion (where:occurrence) (xs:list expansion_record)
  : Tot (option expansion_record) (decreases xs) =
  match xs with
  | [] -> None
  | x::rest -> if occurrence_equal where x.occurrence then Some x else find_expansion where rest

let rec find_operation_attempt (where:occurrence) (attempt:nat) (xs:list op_record)
  : Tot (option op_record) (decreases xs) =
  match xs with
  | [] -> None
  | x::rest ->
    if occurrence_equal where x.occurrence && x.attempt = attempt
    then Some x else find_operation_attempt where attempt rest

let rec find_artifact (id:string) (xs:list artifact_record)
  : Tot (option artifact_record) (decreases xs) =
  match xs with
  | [] -> None
  | x::rest -> if x.artifact_id = id then Some x else find_artifact id rest

let action_ready (ctx:context) (a:action) : bool =
  match a with
  | SaveExpansion _ | PrepareOperation _ -> true
  | DispatchOperation where attempt ->
    (match find_operation_attempt where attempt ctx.operations with
     | Some record -> record.status = Prepared
     | None -> false)
  | ReconcileOperation where attempt ->
    // Reconciliation is enqueued as a nonblocking adapter poll. It must not
    // occupy the scheduler's synchronous ready-action slot.
    false

let rec pick_ready_action (ctx:context) (actions:list action)
  : Tot (option action) (decreases actions) =
  match actions with
  | [] -> None
  | first::rest -> if action_ready ctx first then Some first else pick_ready_action ctx rest

let pending_does_not_block_ready (ctx:context) (where:occurrence) (attempt:nat)
  (record:op_record) (ready:action)
  : Lemma (
    find_operation_attempt where attempt ctx.operations = Some record /\
    record.status = Pending /\ action_ready ctx ready ==>
    pick_ready_action ctx (ReconcileOperation where attempt :: ready :: []) = Some ready) = ()

type fork_slots (a:eqtype) (b:eqtype) = {
  left_slot:option a;
  right_slot:option b
}

let empty_fork_slots (#a #b:eqtype) : fork_slots a b = { left_slot=None; right_slot=None }
let put_left (#a #b:eqtype) (x:a) (s:fork_slots a b) : fork_slots a b = { s with left_slot=Some x }
let put_right (#a #b:eqtype) (y:b) (s:fork_slots a b) : fork_slots a b = { s with right_slot=Some y }
let join_fork (#a #b:eqtype) (s:fork_slots a b) : option (a & b) =
  match s.left_slot, s.right_slot with
  | Some x, Some y -> Some (x, y)
  | _, _ -> None

let fork_slot_commutes (#a #b:eqtype) (x:a) (y:b) (s:fork_slots a b)
  : Lemma (put_right y (put_left x s) = put_left x (put_right y s)) = ()

let fork_slot_join_ordered (#a #b:eqtype) (x:a) (y:b) (s:fork_slots a b)
  : Lemma (join_fork (put_right y (put_left x s)) = Some (x, y)) = ()

let rec find_event (sequence:nat) (xs:list journal_event)
  : Tot (option journal_event) (decreases xs) =
  match xs with
  | [] -> None
  | x::rest -> if x.sequence = sequence then Some x else find_event sequence rest

let status_equal (a:op_status) (b:op_status) : bool =
  match a, b with
  | Prepared, Prepared | Pending, Pending | Unknown, Unknown -> true
  | NotApplied x, NotApplied y -> x = y
  | Succeeded x c, Succeeded y d -> x = y && c = d
  | Failed x, Failed y | Cancelled x, Cancelled y -> x = y
  | _, _ -> false

let rec replace_operation_attempt (where:occurrence) (attempt:nat)
  (status:op_status) (xs:list op_record) : Tot (option (list op_record)) (decreases xs) =
  match xs with
  | [] -> None
  | x::rest ->
    if occurrence_equal where x.occurrence && x.attempt = attempt
    then Some ({x with status=status}::rest)
    else (match replace_operation_attempt where attempt status rest with
          | None -> None
          | Some updated -> Some (x::updated))

let valid_provenance (xs:list string) : bool =
  FStar.List.Tot.for_all (fun x -> x <> "") xs

let valid_blob_tree_wire (value:wire) : bool =
  match decode_tree_entries value with
  | Some tree -> valid_blob_tree tree
  | None -> false

let valid_artifact (run_id:nat) (x:artifact_record) : bool =
  x.artifact_id <> "" && x.codec.tag_id <> "" &&
  x.producer.run_id = run_id && not x.materialization_available &&
  valid_provenance x.provenance &&
  (match x.validation with | None -> true | Some (name, _) -> name <> "") &&
  (match x.kind, x.contents with
   | BlobBytes, WBytes bytes -> valid_bytes bytes &&
       x.codec = tag_of_codec blob_bytes_codec
   | BlobTree, tree_wire -> valid_blob_tree_wire tree_wire &&
       x.codec = tag_of_codec blob_tree_codec
   | DurableReference, WPair (WText uri) (WText digest) -> uri <> "" && digest <> "" &&
       x.codec = tag_of_codec durable_reference_codec
   | TypedValue, _ | OperationInput, _ -> true
   | MaterializedFile, _ | LiveCapability, _ -> false
   | _, _ -> false)

let initial_state (header:run_header) : durable_state = {
  header=header;
  budget=header.initial_budget;
  operations=[];
  expansions=[];
  artifacts=[];
  journal=[]
}

let next_sequence (state:durable_state) : nat = length state.journal

let apply_event_body (state:durable_state) (body:event_body)
  : Tot (option durable_state) =
  match body with
  | ExpansionSaved record ->
    let route_choice_valid =
      match record.choice, record.child_manifest with
      | ReturnWire _, None | Child _, Some _ -> true
      | _, _ -> false in
    if record.occurrence.run_id <> state.header.run_id ||
       record.decision_sequence <> next_sequence state ||
       record.snapshot <> state.budget || not (valid_budget record.snapshot) ||
       not route_choice_valid || record.route_id = "" || record.resolver_id = "" ||
       record.route_capture_tag.tag_id = "" || record.input_tag.tag_id = "" ||
       record.output_tag.tag_id = "" ||
       find_expansion record.occurrence state.expansions <> None
    then None
    else Some { state with expansions=record::state.expansions }
  | OperationPrepared record ->
    let previous = find_operation record.occurrence state.operations in
    let attempt_ok =
      match previous with
      | None -> record.attempt = 0
      | Some old ->
        (match old.status with
         | NotApplied _ -> record.attempt = old.attempt + 1
         | _ -> false) in
    (match reserve state.budget record.reservation with
     | None -> None
     | Some next_budget ->
       if record.status <> Prepared || record.occurrence.run_id <> state.header.run_id ||
          record.decision_sequence <> next_sequence state ||
          record.reservation_snapshot <> state.budget || not attempt_ok ||
          record.operation_id = "" || record.capability = "" ||
          record.capture_tag.tag_id = "" || record.input_tag.tag_id = "" ||
          record.output_tag.tag_id = "" ||
          find_operation_attempt record.occurrence record.attempt state.operations <> None
       then None
       else Some { state with budget=next_budget; operations=record::state.operations })
  | OperationStatusChanged where attempt next_status ->
    (match find_operation_attempt where attempt state.operations with
     | None -> None
     | Some old ->
       let unchanged = status_equal old.status next_status in
       let allowed =
         match old.status, next_status with
         | Prepared, Pending | Prepared, Unknown -> true
         | Prepared, Succeeded _ _ | Prepared, Failed _ | Prepared, Cancelled _ -> true
         | Pending, Unknown -> true
         | Pending, Succeeded _ _ | Pending, Failed _ | Pending, Cancelled _ -> true
         | Unknown, Succeeded _ _ -> true
         | Unknown, Failed _ | Unknown, Cancelled _ -> true
         | _, _ -> false in
       let settled =
         if unchanged then Some state.budget
         else match next_status with
           | Pending | Unknown -> Some state.budget
           | NotApplied _ -> None
           | Succeeded _ actual -> settle_success state.budget old.reservation actual
           | Failed _ | Cancelled _ -> settle_failure state.budget old.reservation
           | Prepared -> None in
       if where.run_id <> state.header.run_id ||
          (match next_status with | NotApplied _ -> true | _ -> false) ||
          (not unchanged && not allowed)
       then None
       else match settled, replace_operation_attempt where attempt next_status state.operations with
         | Some next_budget, Some next_operations ->
           Some { state with budget=next_budget; operations=next_operations }
         | _, _ -> None)
  | OperationNotAppliedConfirmed where attempt adapter_id evidence_id ->
    (match find_operation_attempt where attempt state.operations with
     | None -> None
     | Some old ->
       let allowed = match old.status with | Prepared | Pending | Unknown -> true | _ -> false in
       if where.run_id <> state.header.run_id || not allowed ||
          adapter_id <> old.capability || evidence_id = ""
       then None
       else match settle_not_applied state.budget old.reservation,
                  replace_operation_attempt where attempt (NotApplied evidence_id) state.operations with
         | Some next_budget, Some next_operations ->
           Some { state with budget=next_budget; operations=next_operations }
         | _, _ -> None)
  | ArtifactSaved artifact ->
    if not (valid_artifact state.header.run_id artifact) ||
       find_artifact artifact.artifact_id state.artifacts <> None ||
       not (FStar.List.Tot.for_all
         (fun parent -> find_artifact parent state.artifacts <> None) artifact.provenance)
    then None
    else Some { state with artifacts=artifact::state.artifacts }

let apply_event (state:durable_state) (event:journal_event)
  : Tot (option durable_state) =
  if event.sequence < next_sequence state then
    (match find_event event.sequence state.journal with
     | Some old -> if old = event then Some state else None
     | None -> None)
  else if event.sequence > next_sequence state then None
  else
    match apply_event_body state event.body with
    | None -> None
    | Some changed -> Some { changed with journal=state.journal @ [event] }

let rec replay_from (state:durable_state) (events:list journal_event)
  : Tot (option durable_state) (decreases events) =
  match events with
  | [] -> Some state
  | event::rest ->
    (match apply_event state event with
     | None -> None
     | Some next -> replay_from next rest)

let rec prepared_records (operations:list op_record) : Tot (list op_record) (decreases operations) =
  match operations with
  | [] -> []
  | operation::rest ->
    (match operation.status with
     | Prepared -> operation :: prepared_records rest
     | _ -> prepared_records rest)

let rec mark_recovered_prepared (state:durable_state) (operations:list op_record)
  : Tot (option durable_state) (decreases operations) =
  match operations with
  | [] -> Some state
  | operation::rest ->
    (match find_operation_attempt operation.occurrence operation.attempt state.operations with
     | Some current ->
       (match current.status with
        | Prepared ->
          (match apply_event state {
             sequence=next_sequence state;
             body=OperationStatusChanged operation.occurrence operation.attempt Unknown
           } with
           | Some next -> mark_recovered_prepared next rest
           | None -> None)
        | _ -> mark_recovered_prepared state rest)
     | _ -> mark_recovered_prepared state rest)

let replay (header:run_header) (events:list journal_event)
  : Tot (option durable_state) =
  if valid_budget header.initial_budget
  then replay_from (initial_state header) events
  else None

let state_is_replay_valid (state:durable_state) : Tot bool =
  if not (valid_budget state.header.initial_budget) then false
  else match replay state.header state.journal with
       | None -> false
       | Some rebuilt -> rebuilt = state

let recover_after_process_loss (state:durable_state) : Tot (option durable_state) =
  if not (state_is_replay_valid state) then None
  else mark_recovered_prepared state (prepared_records state.operations)

let context_of_state (state:durable_state) : context = {
  run_id=state.header.run_id;
  event_sequence=next_sequence state;
  budget=state.budget;
  operations=state.operations;
  expansions=state.expansions;
  artifacts=state.artifacts
}

let open_run (#i #o:Type0) (build_id:string) (run_id:nat)
  (input_codec:codec i) (plan:workflow i o) (input:i) (budget:budget)
  : Tot (option durable_state) =
  if build_id = "" || not (valid_budget budget) then None
  else Some (initial_state {
    run_id=run_id;
    build_id=build_id;
    root_manifest=plan.manifest;
    root_input_tag=tag_of_codec input_codec;
    root_input=input_codec.encode input;
    initial_budget=budget
  })

let resume_evaluate (#i #o:Type0) (build_id:string) (input_codec:codec i)
  (plan:workflow i o) (state:durable_state) : Tot (evaluation o) =
  if not (state_is_replay_valid state) then failed "durable event state is invalid"
  else if build_id <> state.header.build_id ||
          plan.manifest <> state.header.root_manifest ||
          tag_of_codec input_codec <> state.header.root_input_tag
  then failed "build, plan, or root codec changed; migration is required"
  else match input_codec.decode state.header.root_input with
       | None -> failed "persisted root input failed codec validation"
       | Some input -> plan.evaluate (context_of_state state) [] input

let rec replay_from_append_law (state:durable_state) (first:list journal_event)
  (second:list journal_event)
  : Lemma (
    replay_from state (first @ second) =
    (match replay_from state first with
     | None -> None
     | Some prefix -> replay_from prefix second)) (decreases first) =
  match first with
  | [] -> ()
  | event::rest ->
    (match apply_event state event with
     | None -> ()
     | Some next -> replay_from_append_law next rest second)

let replay_append_law (header:run_header) (first:list journal_event)
  (second:list journal_event)
  : Lemma (
    replay header (first @ second) =
    (match replay header first with
     | None -> None
     | Some prefix -> replay_from prefix second)) =
  replay_from_append_law (initial_state header) first second

let apply_event_preserves_replay_valid (state:durable_state) (event:journal_event)
  (next:durable_state)
  : Lemma (
    state_is_replay_valid state ==>
    apply_event state event = Some next ==>
    state_is_replay_valid next) =
  match replay state.header state.journal with
  | None -> ()
  | Some rebuilt ->
      if rebuilt = state then
        replay_append_law state.header state.journal [event]

let apply_event_preserves_budget (state:durable_state) (event:journal_event)
  (next:durable_state)
  : Lemma (valid_budget state.budget ==> apply_event state event = Some next ==> valid_budget next.budget) =
  match event.sequence < next_sequence state with
  | true -> ()
  | false ->
    (match apply_event_body state event.body with
     | None -> ()
     | Some changed ->
       match event.body with
       | OperationPrepared record -> reserve_preserves_budget state.budget record.reservation changed.budget
       | OperationStatusChanged where attempt status ->
         (match find_operation_attempt where attempt state.operations with
          | None -> ()
          | Some old ->
            if status_equal old.status status then () else
            match status with
            | Succeeded _ actual -> settle_success_preserves_budget state.budget old.reservation actual changed.budget
            | Failed _ | Cancelled _ -> settle_failure_preserves_budget state.budget old.reservation changed.budget
            | _ -> ())
       | OperationNotAppliedConfirmed where attempt _ _ ->
         (match find_operation_attempt where attempt state.operations with
          | None -> ()
          | Some old -> settle_not_applied_preserves_budget state.budget old.reservation changed.budget)
       | _ -> ())

let rec replay_from_preserves_budget (state:durable_state) (events:list journal_event)
  (result:durable_state)
  : Lemma (valid_budget state.budget ==> replay_from state events = Some result ==> valid_budget result.budget)
    (decreases events) =
  match events with
  | [] -> ()
  | event::rest ->
    (match apply_event state event with
     | None -> ()
     | Some next ->
       apply_event_preserves_budget state event next;
       replay_from_preserves_budget next rest result)

let replay_preserves_budget (header:run_header) (events:list journal_event)
  (state:durable_state)
  : Lemma (replay header events = Some state ==> valid_budget state.budget) =
  replay_from_preserves_budget (initial_state header) events state

noeq type op_spec (c:Type0) (i:Type0) (o:Type0) = {
  operation_id:string;
  operation_version:nat;
  capability:string;
  capture_codec:codec c;
  input_codec:codec i;
  output_codec:codec o;
  capture:c;
  maximum_charge:nat
}

let matches_operation (#c #i #o:Type0) (spec:op_spec c i o)
  (input:wire) (before:budget) (record:op_record) : bool =
  record.operation_id = spec.operation_id &&
  record.capability = spec.capability &&
  record.operation_version = spec.operation_version &&
  record.capture = spec.capture_codec.encode spec.capture &&
  record.capture_tag = tag_of_codec spec.capture_codec &&
  record.request = input &&
  record.input_tag = tag_of_codec spec.input_codec &&
  record.output_tag = tag_of_codec spec.output_codec &&
  record.reservation = spec.maximum_charge &&
  record.reservation_snapshot = before

let external (#c #i #o:Type0) (spec:op_spec c i o) : workflow i o = {
  manifest=MExternal spec.operation_id spec.capability spec.operation_version
    (spec.capture_codec.encode spec.capture)
    (tag_of_codec spec.capture_codec) (tag_of_codec spec.input_codec)
    (tag_of_codec spec.output_codec) spec.maximum_charge;
  evaluate=(fun ctx path input ->
    let where = { run_id=ctx.run_id; path=path } in
    let request = spec.input_codec.encode input in
    match find_operation where ctx.operations with
    | None ->
      if valid_budget ctx.budget && spec.maximum_charge <= available ctx.budget then
        blocked [PrepareOperation {
          occurrence=where;
          decision_sequence=ctx.event_sequence;
          capability=spec.capability;
          operation_id=spec.operation_id;
          operation_version=spec.operation_version;
          capture=spec.capture_codec.encode spec.capture;
          capture_tag=tag_of_codec spec.capture_codec;
          request=request;
          input_tag=tag_of_codec spec.input_codec;
          output_tag=tag_of_codec spec.output_codec;
          reservation=spec.maximum_charge;
          reservation_snapshot=ctx.budget;
          attempt=0;
          status=Prepared
        }]
      else failed "resource budget exhausted"
    | Some record ->
      if not (matches_operation spec request record.reservation_snapshot record) then
        failed "stored operation intent does not match current code or input"
      else
        match record.status with
        | Prepared -> blocked [DispatchOperation where record.attempt]
        | Pending -> blocked [ReconcileOperation where record.attempt]
        | Unknown -> blocked [ReconcileOperation where record.attempt]
        | NotApplied _ ->
          if valid_budget ctx.budget && spec.maximum_charge <= available ctx.budget then
            blocked [PrepareOperation {
              occurrence=where;
              decision_sequence=ctx.event_sequence;
              capability=spec.capability;
              operation_id=spec.operation_id;
              operation_version=spec.operation_version;
              capture=spec.capture_codec.encode spec.capture;
              capture_tag=tag_of_codec spec.capture_codec;
              request=request;
              input_tag=tag_of_codec spec.input_codec;
              output_tag=tag_of_codec spec.output_codec;
              reservation=spec.maximum_charge;
              reservation_snapshot=ctx.budget;
              attempt=record.attempt + 1;
              status=Prepared
            }]
          else failed "resource budget exhausted after reconciliation"
        | Succeeded output actual ->
          if actual > record.reservation then failed "adapter charged above reservation"
          else (match spec.output_codec.decode output with
                | Some value -> completed value
                | None -> failed "stored operation output failed codec validation")
        | Failed message -> failed ("operation failed: " ^ message)
        | Cancelled message -> failed ("operation cancelled: " ^ message))
}

type route_result (o:Type0) =
  | Return : o -> route_result o
  | Expand : child_ref -> route_result o

noeq type route_code (c:Type0) (i:Type0) (o:Type0) = {
  route_id:string;
  route_version:nat;
  resolver_id:string;
  resolver_version:nat;
  capture_codec:codec c;
  input_codec:codec i;
  output_codec:codec o;
  capture:c;
  choose:c -> i -> budget -> Tot (route_result o);
  resolve:child_ref -> Tot (option (workflow i o))
}

let so (#c #i #o:Type0) (route:route_code c i o) : workflow i o = {
  manifest=MSo
    { code_id=route.route_id; code_version=route.route_version;
      capture_tag=tag_of_codec route.capture_codec;
      capture_data=route.capture_codec.encode route.capture }
    (tag_of_codec route.input_codec) (tag_of_codec route.output_codec)
    route.resolver_id route.resolver_version;
  evaluate=(fun ctx path input ->
    let where = { run_id=ctx.run_id; path=path } in
    let input_wire = route.input_codec.encode input in
    match find_expansion where ctx.expansions with
    | Some record ->
      if record.route_id <> route.route_id || record.route_version <> route.route_version ||
         record.route_capture <> route.capture_codec.encode route.capture ||
         record.route_capture_tag <> tag_of_codec route.capture_codec ||
         record.input_tag <> tag_of_codec route.input_codec ||
         record.output_tag <> tag_of_codec route.output_codec ||
         record.resolver_id <> route.resolver_id ||
         record.resolver_version <> route.resolver_version ||
         record.input <> input_wire || not (valid_budget record.snapshot) then
        failed "stored route does not match code, input, or resource snapshot"
      else (match record.choice with
        | ReturnWire output ->
          if record.child_manifest <> None then failed "direct route has child manifest"
          else (match route.output_codec.decode output with
                | Some value -> completed value
                | None -> failed "stored route output failed codec validation")
        | Child ref ->
          (match record.child_manifest, route.resolve ref with
           | Some expected, Some child ->
             if child.manifest <> expected then failed "resolved child plan changed"
             else child.evaluate ctx (path_append path (ExpandChild ref.child_id)) input
           | _, None -> failed "stored child code or capability unavailable"
           | None, Some _ -> failed "child route has no persisted plan manifest")
      )
    | None ->
      let snapshot = ctx.budget in
      (match route.choose route.capture input snapshot with
       | Return value ->
         blocked [SaveExpansion {
           occurrence=where; decision_sequence=ctx.event_sequence;
           route_id=route.route_id; route_version=route.route_version;
           route_capture=route.capture_codec.encode route.capture;
           route_capture_tag=tag_of_codec route.capture_codec;
           input_tag=tag_of_codec route.input_codec;
           output_tag=tag_of_codec route.output_codec;
           resolver_id=route.resolver_id; resolver_version=route.resolver_version;
           input=input_wire; snapshot=snapshot;
           choice=ReturnWire (route.output_codec.encode value);
           child_manifest=None
         }]
       | Expand ref ->
         (match route.resolve ref with
          | None -> failed "selected child code or capability unavailable"
          | Some child ->
            blocked [SaveExpansion {
              occurrence=where; decision_sequence=ctx.event_sequence;
              route_id=route.route_id; route_version=route.route_version;
              route_capture=route.capture_codec.encode route.capture;
              route_capture_tag=tag_of_codec route.capture_codec;
              input_tag=tag_of_codec route.input_codec;
              output_tag=tag_of_codec route.output_codec;
              resolver_id=route.resolver_id; resolver_version=route.resolver_version;
              input=input_wire; snapshot=snapshot; choice=Child ref;
              child_manifest=Some child.manifest
            }])))
}

let direct_fork_preserves_slots (#i #a #b:Type0)
  (left:workflow i a) (right:workflow i b) (ctx:context) (path:path) (input:i)
  (x:a) (y:b)
  : Lemma (
    (combine_evaluations (completed x) (completed y)).value == Some (x, y) /\
    (combine_evaluations (completed y) (completed x)).value == Some (y, x)) = ()

let lift_empty_list (#a #b:Type0) (w:workflow a b) (ctx:context) (path:path)
  : Lemma (((lift (Lists Id) w).evaluate ctx path []).value == Some []) = ()

let lift_absent_option (#a #b:Type0) (w:workflow a b) (ctx:context) (path:path)
  : Lemma (((lift (Options Id) w).evaluate ctx path None).value == Some None) = ()
