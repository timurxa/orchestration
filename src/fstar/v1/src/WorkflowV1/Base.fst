module WorkflowV1.Base
open FStar.List.Tot

type bytes = list nat
type code_id = string
type run_id = string
// Digests are represented abstractly as bytes here. Any collision-resistance
// claim belongs to the concrete hash/identity refinement, not this alias.
type digest = bytes
type plan_id = digest

type slot =
  | SeqFirst
  | SeqSecond
  | ExpandChild : nat -> plan_id -> plan_id -> slot

type occurrence = {
  run_id:run_id;
  plan_id:plan_id;
  path:list slot
}

type run_header = {
  header_run_id:run_id;
  header_root_plan:plan_id;
  header_root_input:bytes;
  header_root_input_digest:digest;
  header_root_schema:code_id;
  header_root_schema_version:nat;
  header_registry_id:code_id;
  header_registry_version:nat;
  header_registry_build:digest;
  header_admission_id:code_id;
  header_admission_version:nat;
  header_admission_build:digest;
  header_budget_limit:nat;
  header_initial_depth:nat;
  header_initial_nodes:nat
}

let run_header_eq (left:run_header) (right:run_header) : bool =
  left.header_run_id = right.header_run_id &&
  left.header_root_plan = right.header_root_plan &&
  left.header_root_input = right.header_root_input &&
  left.header_root_input_digest = right.header_root_input_digest &&
  left.header_root_schema = right.header_root_schema &&
  left.header_root_schema_version = right.header_root_schema_version &&
  left.header_registry_id = right.header_registry_id &&
  left.header_registry_version = right.header_registry_version &&
  left.header_registry_build = right.header_registry_build &&
  left.header_admission_id = right.header_admission_id &&
  left.header_admission_version = right.header_admission_version &&
  left.header_admission_build = right.header_admission_build &&
  left.header_budget_limit = right.header_budget_limit &&
  left.header_initial_depth = right.header_initial_depth &&
  left.header_initial_nodes = right.header_initial_nodes

let slot_eq (left:slot) (right:slot) : bool =
  match left, right with
  | SeqFirst, SeqFirst -> true
  | SeqSecond, SeqSecond -> true
  | ExpandChild li ls lr, ExpandChild ri rs rr ->
      li = ri && ls = rs && lr = rr
  | _, _ -> false

let rec path_eq (left:list slot) (right:list slot) : bool =
  match left, right with
  | [], [] -> true
  | l::lt, r::rt -> slot_eq l r && path_eq lt rt
  | _, _ -> false

let occurrence_eq (left:occurrence) (right:occurrence) : bool =
  left.run_id = right.run_id && left.plan_id = right.plan_id &&
  path_eq left.path right.path

type ctx (i:Type0) (m:i -> Type0) = (x:i & m x)

noeq type codec (a:Type0) (valid:a -> prop) = {
  codec_id:code_id;
  codec_version:nat;
  codec_build:digest;
  encode:a -> Tot bytes;
  decode:bytes -> Tot (option a);
  roundtrip:(x:a) -> Lemma (decode (encode x) == Some x);
  decode_sound:(wire:bytes) -> (x:a) -> Lemma
    (decode wire == Some x ==> valid x);
  canonical:(wire:bytes) -> (x:a) -> Lemma
    (decode wire == Some x ==> wire == encode x)
}

noeq type indexed_codec (i:Type0) (o:i -> Type0)
    (valid:(x:i) -> o x -> prop) = {
  codec_id:code_id;
  codec_version:nat;
  codec_build:digest;
  encode:(x:i) -> o x -> Tot bytes;
  decode:(x:i) -> bytes -> Tot (option (o x));
  roundtrip:(x:i) -> (y:o x) -> Lemma
    (decode x (encode x y) == Some y);
  decode_sound:(x:i) -> (wire:bytes) -> (y:o x) -> Lemma
    (decode x wire == Some y ==> valid x y);
  canonical:(x:i) -> (wire:bytes) -> (y:o x) -> Lemma
    (decode x wire == Some y ==> wire == encode x y)
}

noeq type code_ref (c i:Type0) (o:i -> Type0)
    (valid:(x:i) -> o x -> prop) = {
  code_id:code_id;
  code_version:nat;
  build_id:digest;
  capture:c;
  capture_codec:codec c (fun _ -> True);
  input_codec:codec i (fun _ -> True);
  output_codec:indexed_codec i o valid;
  run:c -> (x:i) -> Tot (o x)
}

type code_identity = {
  identity_id:code_id;
  identity_version:nat;
  identity_build:digest
}

type canonical_plan_fields = {
  plan_constructor:code_identity;
  plan_code_dependencies:list code_identity;
  plan_codec_dependencies:list code_identity;
  plan_ordered_children:list plan_id;
  plan_capture_bytes:list bytes;
  plan_input_schema:code_identity;
  plan_output_schema:code_identity;
  plan_policy_bytes:bytes
}

noeq type plan_identity_contract = {
  encode_plan_fields:canonical_plan_fields -> Tot bytes;
  decode_plan_fields:bytes -> Tot (option canonical_plan_fields);
  hash_plan_bytes:bytes -> Tot plan_id;
  plan_roundtrip:(fields:canonical_plan_fields) -> Lemma
    (decode_plan_fields (encode_plan_fields fields) == Some fields);
  plan_decode_sound:(wire:bytes) -> (fields:canonical_plan_fields) -> Lemma
    (decode_plan_fields wire == Some fields ==>
       encode_plan_fields fields == wire)
}

let canonical_plan_id (identity:plan_identity_contract)
    (fields:canonical_plan_fields) : plan_id =
  identity.hash_plan_bytes (identity.encode_plan_fields fields)

let rec all_codes_pinned (is_pinned:code_identity -> Tot bool)
    (identities:list code_identity) : prop =
  match identities with
  | [] -> True
  | identity::rest -> is_pinned identity == true /\
      all_codes_pinned is_pinned rest

let plan_fields_codes_pinned (is_pinned:code_identity -> Tot bool)
    (fields:canonical_plan_fields) : prop =
  is_pinned fields.plan_constructor == true /\
  all_codes_pinned is_pinned fields.plan_code_dependencies /\
  all_codes_pinned is_pinned fields.plan_codec_dependencies /\
  is_pinned fields.plan_input_schema == true /\
  is_pinned fields.plan_output_schema == true

noeq type code_registry_contract = {
  registry_id:code_id;
  registry_version:nat;
  registry_build:digest;
  plan_identity:plan_identity_contract;
  code_behavior:code_identity -> prop;
  code_is_pinned:code_identity -> Tot bool;
  code_pin_sound:(identity:code_identity) -> Lemma
    (code_is_pinned identity == true ==>
       code_behavior identity);
  resolve_plan:plan_id -> Tot (option canonical_plan_fields);
  resolve_plan_sound:(id:plan_id) -> (fields:canonical_plan_fields)
    -> Lemma (resolve_plan id == Some fields ==>
       id == canonical_plan_id plan_identity fields /\
       plan_fields_codes_pinned code_is_pinned fields)
}
