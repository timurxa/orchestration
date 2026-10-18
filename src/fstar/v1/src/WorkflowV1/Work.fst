module WorkflowV1.Work
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol
open WorkflowV1.Operations

noeq type child_descriptor (i:Type0) (j:i -> Type0) (x:i) = {
  source_plan_id:plan_id;
  argument:j x
}

noeq type expansion_decision (i:Type0) (j:i -> Type0)
    (o:i -> Type0) (x:i) =
  | ReturnValue : o x -> expansion_decision i j o x
  | Spawn : list (child_descriptor i j x) -> expansion_decision i j o x

noeq type dlist (#a:Type0) (b:a -> Type0) : list a -> Type0 =
  | DNil : dlist b []
  | DCons : #x:a -> #xs:list a -> b x -> dlist b xs
      -> dlist b (x :: xs)

noeq type expand_spec (c cj i:Type0) (j:i -> Type0)
    (o:i -> Type0) (p:(x:i) -> j x -> Type0)
    (allowed:(x:i) -> list (child_descriptor i j x) -> prop) = {
  expand_id:code_id;
  expand_version:nat;
  expand_build:digest;
  capture:c;
  capture_codec:codec c (fun _ -> True);
  registry_id:code_id;
  registry_version:nat;
  registry_build:digest;
  checker_id:code_id;
  checker_version:nat;
  checker_build:digest;
  join_id:code_id;
  join_version:nat;
  join_build:digest;
  join_capture:cj;
  join_capture_codec:codec cj (fun _ -> True);
  decision_codec_id:code_id;
  decision_codec_version:nat;
  choose:c -> (x:i) -> (snapshot:bytes)
    -> Tot (expansion_decision i j o x);
  encode_decision:(x:i) -> expansion_decision i j o x -> Tot bytes;
  decode_decision:(x:i) -> bytes
    -> Tot (option (expansion_decision i j o x));
  decision_roundtrip:(x:i) -> (d:expansion_decision i j o x)
    -> Lemma (decode_decision x (encode_decision x d) == Some d);
  check_allowed:(x:i) -> (ds:list (child_descriptor i j x)) -> Tot bool;
  check_sound:(x:i) -> (ds:list (child_descriptor i j x))
    -> Lemma (check_allowed x ds == true ==> allowed x ds);
  check_complete:(x:i) -> (ds:list (child_descriptor i j x))
    -> Lemma (allowed x ds ==> check_allowed x ds == true);
  output_codec:indexed_codec i o (fun _ _ -> True);
  maximum_children:nat;
  join:cj -> (x:i) -> (ds:list (child_descriptor i j x))
    -> allowed x ds
    -> dlist (fun d -> p x d.argument) ds
    -> Tot (o x)
}

noeq type work : i:Type0 -> (i -> Type0) -> Type =
  | WLocal : #i:Type0 -> #o:(i -> Type0) -> #c:Type0
      -> #valid:(x:i -> o x -> prop)
      -> code_ref c i o valid -> work i o
  | WExternal : #b:Type0 -> #i:Type0 -> #o:(i -> Type0)
      -> #c:Type0 -> #raw:Type0
      -> #valid:(x:i -> operation_context -> o x -> prop)
      -> bound_operation b c i raw o valid
      -> work i (fun x -> terminal i o valid x)
  | WSeq : #i:Type0 -> #m:(i -> Type0)
      -> #n:(x:i -> m x -> Type0)
      -> work i m
      -> work (ctx i m) (fun xy -> n xy._1 xy._2)
      -> work i (fun x -> (y:m x & n x y))
  | WExpand : #i:Type0 -> #o:(i -> Type0) -> #c:Type0 -> #cj:Type0
      -> #j:(i -> Type0)
      -> #p:(x:i -> j x -> Type0)
      -> #allowed:(x:i -> list (child_descriptor i j x) -> prop)
      -> expand_spec c cj i j o p allowed
      -> work i o

// Kernel constructors are deliberately limited to local code, external
// operations, dependent sequencing, and Expand as the only dynamic graph
// generator. Identity, products, cases, fan, and lift are libraries/lowerings.

noeq type typed_work_package = {
  packed_input_type:Type0;
  packed_output_family:packed_input_type -> Type0;
  packed_work:work packed_input_type packed_output_family;
  packed_plan_id:plan_id;
  packed_plan_fields:canonical_plan_fields
}

noeq type typed_work_registry_contract = {
  code_registry:code_registry_contract;
  work_matches_canonical_fields:typed_work_package -> prop;
  resolve_work:plan_id -> Tot (option typed_work_package);
  resolve_work_sound:(id:plan_id) -> (plan:typed_work_package) -> Lemma
    (resolve_work id == Some plan ==>
       plan.packed_plan_id == id /\
       code_registry.resolve_plan id == Some plan.packed_plan_fields /\
       id == canonical_plan_id code_registry.plan_identity
         plan.packed_plan_fields /\
       plan_fields_codes_pinned code_registry.code_is_pinned
         plan.packed_plan_fields /\
       work_matches_canonical_fields plan)
}

let seq (#i:Type0) (#m:(i -> Type0))
    (#n:(x:i -> m x -> Type0))
    (first:work i m)
    (second:work (ctx i m) (fun xy -> n xy._1 xy._2))
  : work i (fun x -> (y:m x & n x y)) =
  WSeq first second
