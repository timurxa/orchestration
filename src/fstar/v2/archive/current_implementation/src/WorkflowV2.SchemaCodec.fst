module WorkflowV2.SchemaCodec

open FStar.List.Tot
open FStar.List.Tot.Properties
open WorkflowV2.Kernel

// Tags are local to each AST sort. Variable-size byte strings reuse Kernel's
// length-prefixed sequence codec; schema argument lists prefix the number of
// AST arguments, then concatenate their self-delimiting encodings.
let enc_bool (b:bool) : bytes =
  if b then [1] else [0]

let dec_bool (input:bytes) : option (bool & bytes) =
  match input with
  | 0::tail -> Some (false, tail)
  | 1::tail -> Some (true, tail)
  | _ -> None

// Signed integers use sign then magnitude. Reject the only duplicate form,
// negative zero. F* integers are mathematical integers, so negation is total.
let enc_int (z:int) : bytes =
  if z < 0 then 1 :: [-z] else 0 :: [z]

let dec_int (input:bytes) : option (int & bytes) =
  match input with
  | 0::magnitude::tail -> Some (magnitude, tail)
  | 1::magnitude::tail ->
      if magnitude = 0 then None else Some (-magnitude, tail)
  | _ -> None

// Value lists occur in constructor and index-call applications. Their count
// is the number of AST arguments, not the number of wire naturals.
let rec enc_schema_values (values:list schema_value_expr) : bytes =
  match values with
  | [] -> []
  | value::tail -> enc_schema_value value @ enc_schema_values tail

and enc_schema_value (value:schema_value_expr) : bytes =
  match value with
  | SchemaBound index -> 0 :: [index]
  | SchemaRoot -> [1]
  | SchemaPort key -> 2 :: [key]
  | SchemaConstant identity payload ->
      [3] @ enc_codec_identity identity @ enc_seq payload
  | SchemaUnitValue -> [4]
  | SchemaBoolValue boolean -> [5] @ enc_bool boolean
  | SchemaNatValue number -> 6 :: [number]
  | SchemaIntValue number -> [7] @ enc_int number
  | SchemaPairValue left right ->
      [8] @ enc_schema_value left @ enc_schema_value right
  | SchemaFstValue pair -> [9] @ enc_schema_value pair
  | SchemaSndValue pair -> [10] @ enc_schema_value pair
  | SchemaConstructorValue identity arguments ->
      [11] @ enc_schema_identity identity @ [length arguments]
        @ enc_schema_values arguments
  | SchemaIndexCallValue identity arguments ->
      [12] @ enc_schema_identity identity @ [length arguments]
        @ enc_schema_values arguments

let rec enc_schema_pred (predicate:schema_predicate_expr) : bytes =
  match predicate with
  | SchemaTrue -> [0]
  | SchemaFalse -> [1]
  | SchemaEqual left right ->
      [2] @ enc_schema_value left @ enc_schema_value right
  | SchemaAnd left right ->
      [3] @ enc_schema_pred left @ enc_schema_pred right

let rec enc_schema_type (schema_type:schema_type_expr) : bytes =
  match schema_type with
  | SchemaAtom identity -> [0] @ enc_schema_identity identity
  | SchemaUnit -> [1]
  | SchemaBool -> [2]
  | SchemaNat -> [3]
  | SchemaInt -> [4]
  | SchemaProduct left right ->
      [5] @ enc_schema_type left @ enc_schema_type right
  | SchemaSum left right ->
      [6] @ enc_schema_type left @ enc_schema_type right
  | SchemaList element -> [7] @ enc_schema_type element
  | SchemaOption element -> [8] @ enc_schema_type element
  | SchemaSigma base family ->
      [9] @ enc_schema_type base @ enc_schema_type family
  | SchemaFamily identity arguments ->
      [10] @ enc_schema_identity identity @ [length arguments]
        @ enc_schema_values arguments
  | SchemaRefine base predicate ->
      [11] @ enc_schema_type base @ enc_schema_pred predicate

// First-order parser core: no higher-order parser callbacks. Every recursive
// edge spends one unit of fuel, including value/step/list transitions.
let rec dec_schema_value_fuel (fuel:nat) (input:bytes)
  : Tot (option (schema_value_expr & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else dec_schema_value_step_fuel (fuel - 1) input
and dec_schema_value_step_fuel (fuel:nat) (input:bytes)
  : Tot (option (schema_value_expr & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> (match dec_nat tail with None -> None | Some (n,r) -> Some (SchemaBound n,r))
      | 1 -> Some (SchemaRoot,tail)
      | 2 -> (match dec_nat tail with None -> None | Some (n,r) -> Some (SchemaPort n,r))
      | 3 -> (match dec_codec_identity tail with None -> None | Some (id,r) ->
                match dec_len_seq r with None -> None | Some (payload,r2) -> Some (SchemaConstant id payload,r2))
      | 4 -> Some (SchemaUnitValue,tail)
      | 5 -> (match dec_bool tail with None -> None | Some (b,r) -> Some (SchemaBoolValue b,r))
      | 6 -> (match dec_nat tail with None -> None | Some (n,r) -> Some (SchemaNatValue n,r))
      | 7 -> (match dec_int tail with None -> None | Some (n,r) -> Some (SchemaIntValue n,r))
      | 8 -> (match dec_schema_value_fuel (fuel - 1) tail with None -> None | Some (x,r) ->
                match dec_schema_value_fuel (fuel - 1) r with None -> None | Some (y,r2) -> Some (SchemaPairValue x y,r2))
      | 9 -> (match dec_schema_value_fuel (fuel - 1) tail with None -> None | Some (x,r) -> Some (SchemaFstValue x,r))
      | 10 -> (match dec_schema_value_fuel (fuel - 1) tail with None -> None | Some (x,r) -> Some (SchemaSndValue x,r))
      | 11 -> (match dec_schema_identity tail with None -> None | Some (id,r) ->
                 match dec_nat r with None -> None | Some (count,payload) ->
                   match dec_schema_values_fuel (fuel - 1) count payload with None -> None | Some (xs,r2) -> Some (SchemaConstructorValue id xs,r2))
      | 12 -> (match dec_schema_identity tail with None -> None | Some (id,r) ->
                 match dec_nat r with None -> None | Some (count,payload) ->
                   match dec_schema_values_fuel (fuel - 1) count payload with None -> None | Some (xs,r2) -> Some (SchemaIndexCallValue id xs,r2))
      | _ -> None
and dec_schema_values_fuel (fuel count:nat) (input:bytes)
  : Tot (option (list schema_value_expr & bytes)) (decreases fuel) =
  if count = 0 then Some ([],input)
  else if fuel = 0 then None
  else match dec_schema_value_fuel (fuel - 1) input with
       | None -> None
       | Some (x,tail) ->
           match dec_schema_values_fuel (fuel - 1) (count - 1) tail with
           | None -> None
           | Some (xs,rest) -> Some (x::xs,rest)

let dec_schema_values_fuel_equation (fuel count:nat) (input:bytes)
  : Lemma (dec_schema_values_fuel fuel count input ==
      (if count = 0 then Some ([], input)
       else if fuel = 0 then None
       else match dec_schema_value_fuel (fuel - 1) input with
            | None -> None
            | Some (x, tail) ->
                match dec_schema_values_fuel (fuel - 1) (count - 1) tail with
                | None -> None
                | Some (xs, rest) -> Some (x::xs, rest))) = ()

let parser_fuel (input:bytes) =
  length input + length input + length input + length input +
  length input + length input + length input + length input + 8

let dec_schema_value (input:bytes)
  : Tot (option (schema_value_expr & bytes)) =
  dec_schema_value_fuel (parser_fuel input) input

let rec dec_schema_pred_fuel (fuel:nat) (input:bytes)
  : Tot (option (schema_predicate_expr & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else dec_schema_pred_step_fuel (fuel - 1) input
and dec_schema_pred_step_fuel (fuel:nat) (input:bytes)
  : Tot (option (schema_predicate_expr & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> Some (SchemaTrue,tail)
      | 1 -> Some (SchemaFalse,tail)
      | 2 -> (match dec_schema_value_fuel (fuel - 1) tail with None -> None | Some (x,r) ->
                match dec_schema_value_fuel (fuel - 1) r with None -> None | Some (y,r2) -> Some (SchemaEqual x y,r2))
      | 3 -> (match dec_schema_pred_fuel (fuel - 1) tail with None -> None | Some (x,r) ->
                match dec_schema_pred_fuel (fuel - 1) r with None -> None | Some (y,r2) -> Some (SchemaAnd x y,r2))
      | _ -> None

let dec_schema_pred (input:bytes)
  : Tot (option (schema_predicate_expr & bytes)) =
  dec_schema_pred_fuel (parser_fuel input) input

let rec dec_schema_type_fuel (fuel:nat) (input:bytes)
  : Tot (option (schema_type_expr & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else dec_schema_type_step_fuel (fuel - 1) input
and dec_schema_type_step_fuel (fuel:nat) (input:bytes)
  : Tot (option (schema_type_expr & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> (match dec_schema_identity tail with None -> None | Some (id,r) -> Some (SchemaAtom id,r))
      | 1 -> Some (SchemaUnit,tail)
      | 2 -> Some (SchemaBool,tail)
      | 3 -> Some (SchemaNat,tail)
      | 4 -> Some (SchemaInt,tail)
      | 5 -> (match dec_schema_type_fuel (fuel - 1) tail with None -> None | Some (x,r) -> match dec_schema_type_fuel (fuel - 1) r with None -> None | Some (y,r2) -> Some (SchemaProduct x y,r2))
      | 6 -> (match dec_schema_type_fuel (fuel - 1) tail with None -> None | Some (x,r) -> match dec_schema_type_fuel (fuel - 1) r with None -> None | Some (y,r2) -> Some (SchemaSum x y,r2))
      | 7 -> (match dec_schema_type_fuel (fuel - 1) tail with None -> None | Some (x,r) -> Some (SchemaList x,r))
      | 8 -> (match dec_schema_type_fuel (fuel - 1) tail with None -> None | Some (x,r) -> Some (SchemaOption x,r))
      | 9 -> (match dec_schema_type_fuel (fuel - 1) tail with None -> None | Some (x,r) -> match dec_schema_type_fuel (fuel - 1) r with None -> None | Some (y,r2) -> Some (SchemaSigma x y,r2))
      | 10 -> (match dec_schema_identity tail with None -> None | Some (id,r) -> match dec_nat r with None -> None | Some (count,payload) -> match dec_schema_values_fuel (fuel - 1) count payload with None -> None | Some (xs,r2) -> Some (SchemaFamily id xs,r2))
      | 11 -> (match dec_schema_type_fuel (fuel - 1) tail with None -> None | Some (x,r) -> match dec_schema_pred_fuel (fuel - 1) r with None -> None | Some (p,r2) -> Some (SchemaRefine x p,r2))
      | _ -> None

let dec_schema_type (input:bytes)
  : Tot (option (schema_type_expr & bytes)) =
  dec_schema_type_fuel (parser_fuel input) input

// Public decoders require complete input and exact re-encoding. Unknown tags,
// truncated fields, noncanonical signed integers, and trailing bytes reject.
let decode_schema_value (input:bytes) : option schema_value_expr =
  match dec_schema_value input with
  | None -> None
  | Some (_, _::_) -> None
  | Some (value, []) ->
      if enc_schema_value value = input then Some value else None

let decode_schema_pred (input:bytes) : option schema_predicate_expr =
  match dec_schema_pred input with
  | None -> None
  | Some (_, _::_) -> None
  | Some (predicate, []) ->
      if enc_schema_pred predicate = input then Some predicate else None

let decode_schema_type (input:bytes) : option schema_type_expr =
  match dec_schema_type input with
  | None -> None
  | Some (_, _::_) -> None
  | Some (schema_type, []) ->
      if enc_schema_type schema_type = input then Some schema_type else None

let accepted_value_canonical (input:bytes) (value:schema_value_expr)
    (h:decode_schema_value input == Some value)
  : Lemma (input == enc_schema_value value) = ()

let accepted_pred_canonical (input:bytes) (predicate:schema_predicate_expr)
    (h:decode_schema_pred input == Some predicate)
  : Lemma (input == enc_schema_pred predicate) = ()

let accepted_type_canonical (input:bytes) (schema_type:schema_type_expr)
    (h:decode_schema_type input == Some schema_type)
  : Lemma (input == enc_schema_type schema_type) = ()

// Checked examples only: these do not establish the general recursive
// encode/decode theorem or encoder injectivity.
let root_suffix (suffix:bytes)
  : Lemma
      (dec_schema_value_fuel (length (enc_schema_value SchemaRoot) + length (enc_schema_value SchemaRoot) + length (enc_schema_value SchemaRoot) + 1)
         (enc_schema_value SchemaRoot @ suffix) == Some (SchemaRoot, suffix)) =
  ()

let bound_suffix (index:nat) (suffix:bytes)
  : Lemma
      (dec_schema_value_fuel
         (length (enc_schema_value (SchemaBound index)) + length (enc_schema_value (SchemaBound index)) + length (enc_schema_value (SchemaBound index)) + 1)
         (enc_schema_value (SchemaBound index) @ suffix) ==
         Some (SchemaBound index, suffix)) =
  ()

let int_suffix (number:int) (suffix:bytes)
  : Lemma
      (dec_schema_value_fuel
         (length (enc_schema_value (SchemaIntValue number)) + length (enc_schema_value (SchemaIntValue number)) + length (enc_schema_value (SchemaIntValue number)) + 1)
         (enc_schema_value (SchemaIntValue number) @ suffix) ==
         Some (SchemaIntValue number, suffix)) =
  ()

let refine_int_roundtrip ()
  : Lemma
      (decode_schema_type
         (enc_schema_type
            (SchemaRefine SchemaUnit
               (SchemaEqual (SchemaIntValue (-3)) (SchemaIntValue 2)))) ==
       Some
         (SchemaRefine SchemaUnit
            (SchemaEqual (SchemaIntValue (-3)) (SchemaIntValue 2)))) =
  ()

let family_empty_roundtrip ()
  : Lemma
      (decode_schema_type
         (enc_schema_type
            (SchemaFamily
               {schema_name=[]; schema_version=0; schema_build=[]} [])) ==
       Some
         (SchemaFamily
            {schema_name=[]; schema_version=0; schema_build=[]} [])) =
  ()

let int_parse ()
  : Lemma (dec_schema_value [7;1;2] == Some (SchemaIntValue (-2), [])) =
  ()

let umax (x y:nat) = if x > y then x else y
let rec vneed (v:schema_value_expr) : nat =
  match v with
  | SchemaBound _ | SchemaRoot | SchemaPort _ | SchemaConstant _ _
  | SchemaUnitValue | SchemaBoolValue _ | SchemaNatValue _ | SchemaIntValue _ -> 2
  | SchemaPairValue x y -> 2 + umax (vneed x) (vneed y)
  | SchemaFstValue x | SchemaSndValue x -> 2 + vneed x
  | SchemaConstructorValue _ xs | SchemaIndexCallValue _ xs -> 2 + xsneed xs
and xsneed (xs:list schema_value_expr) : nat =
  match xs with
  | [] -> 0
  | x::tail -> umax (1 + vneed x) (1 + xsneed tail)

let enc_values_unfold (x:schema_value_expr) (tail:list schema_value_expr)
  : Lemma (enc_schema_values (x::tail) == enc_schema_value x @ enc_schema_values tail) = ()

let enc_constructor_equation (id:schema_identity) (xs:list schema_value_expr)
  : Lemma (enc_schema_value (SchemaConstructorValue id xs) ==
      [11] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs) =
  FStar.List.Tot.Properties.append_length [11]
    (enc_schema_identity id @ [length xs] @ enc_schema_values xs);
  FStar.List.Tot.Properties.append_length (enc_schema_identity id)
    ([length xs] @ enc_schema_values xs);
  FStar.List.Tot.Properties.append_length [length xs] (enc_schema_values xs);
  ()

let enc_index_call_equation (id:schema_identity) (xs:list schema_value_expr)
  : Lemma (enc_schema_value (SchemaIndexCallValue id xs) ==
      [12] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs) = ()

let rec vneed_bound (v:schema_value_expr)
  : Lemma (ensures (vneed v <= length (enc_schema_value v) + length (enc_schema_value v) + length (enc_schema_value v) + 1)) (decreases v) =
  match v with
  | SchemaBound _ | SchemaRoot | SchemaPort _ | SchemaConstant _ _
  | SchemaUnitValue | SchemaBoolValue _ | SchemaNatValue _ | SchemaIntValue _ -> ()
  | SchemaPairValue x y -> vneed_bound x; vneed_bound y; ()
  | SchemaFstValue x | SchemaSndValue x -> vneed_bound x; ()
  | SchemaConstructorValue id xs ->
      xsneed_bound xs;
      enc_constructor_equation id xs;
      FStar.List.Tot.Properties.append_length [11]
        (enc_schema_identity id @ [length xs] @ enc_schema_values xs);
      FStar.List.Tot.Properties.append_length (enc_schema_identity id)
        ([length xs] @ enc_schema_values xs);
      FStar.List.Tot.Properties.append_length [length xs] (enc_schema_values xs);
      assert (length ([11] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs) == 1 + length (enc_schema_identity id @ [length xs] @ enc_schema_values xs));
      assert (length ([length xs] @ enc_schema_values xs) == 1 + length (enc_schema_values xs));
      assert (length (enc_schema_value (SchemaConstructorValue id xs)) >= length (enc_schema_values xs) + 2);
      ()
  | SchemaIndexCallValue id xs ->
      xsneed_bound xs;
      enc_index_call_equation id xs;
      FStar.List.Tot.Properties.append_length [12]
        (enc_schema_identity id @ [length xs] @ enc_schema_values xs);
      FStar.List.Tot.Properties.append_length (enc_schema_identity id)
        ([length xs] @ enc_schema_values xs);
      FStar.List.Tot.Properties.append_length [length xs] (enc_schema_values xs);
      assert (length (enc_schema_value (SchemaIndexCallValue id xs)) >= length (enc_schema_values xs) + 2);
      ()
and xsneed_bound (xs:list schema_value_expr)
  : Lemma (ensures (xsneed xs <= length (enc_schema_values xs) + length (enc_schema_values xs) + length (enc_schema_values xs) + 3)) (decreases xs) =
  match xs with
  | [] -> ()
  | x::tail ->
      enc_values_unfold x tail;
      vneed_bound x;
      xsneed_bound tail;
      FStar.List.Tot.Properties.append_length
        (enc_schema_value x) (enc_schema_values tail);
      assert (0 < length (enc_schema_value x));
      assert (1 + vneed x <= length (enc_schema_values xs) + length (enc_schema_values xs) + length (enc_schema_values xs) + 3);
      assert (1 + xsneed tail <= length (enc_schema_values xs) + length (enc_schema_values xs) + length (enc_schema_values xs) + 3);
      assert (umax (1 + vneed x) (1 + xsneed tail) <= length (enc_schema_values xs) + length (enc_schema_values xs) + length (enc_schema_values xs) + 3);
      ()

let rec vneed_positive (v:schema_value_expr)
  : Lemma (ensures (2 <= vneed v)) (decreases v) =
  match v with
  | SchemaBound _ | SchemaRoot | SchemaPort _ | SchemaConstant _ _
  | SchemaUnitValue | SchemaBoolValue _ | SchemaNatValue _ | SchemaIntValue _ -> ()
  | SchemaPairValue x y -> vneed_positive x; vneed_positive y; ()
  | SchemaFstValue x | SchemaSndValue x -> vneed_positive x; ()
  | SchemaConstructorValue _ _ | SchemaIndexCallValue _ _ -> ()

let dec_nat_prefix (n:nat) (suffix:bytes)
  : Lemma (dec_nat ([n] @ suffix) == Some (n,suffix)) = ()

let dec_bool_prefix (b:bool) (suffix:bytes)
  : Lemma (dec_bool (enc_bool b @ suffix) == Some (b,suffix)) = ()

let dec_int_prefix (z:int) (suffix:bytes)
  : Lemma (dec_int (enc_int z @ suffix) == Some (z,suffix)) = ()

let constructor_step_from_values (fuel:nat) (id:schema_identity)
    (xs:list schema_value_expr) (suffix:bytes)
  : Lemma
      (requires (fuel > 0 /\
        dec_schema_values_fuel (fuel - 1) (length xs)
          (enc_schema_values xs @ suffix) == Some (xs,suffix)))
      (ensures
        (dec_schema_value_step_fuel fuel
          ([11] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs @ suffix) ==
         Some (SchemaConstructorValue id xs,suffix))) =
  append_assoc_local [11] (enc_schema_identity id)
    ([length xs] @ (enc_schema_values xs @ suffix));
  append_assoc_local (enc_schema_identity id) [length xs]
    (enc_schema_values xs @ suffix);
  append_assoc_local [length xs] (enc_schema_values xs) suffix;
  schema_identity_decode_encoding_suffix id
    ([length xs] @ enc_schema_values xs @ suffix);
  dec_nat_prefix (length xs) (enc_schema_values xs @ suffix);
  assert (dec_schema_identity
    (enc_schema_identity id @ ([length xs] @ (enc_schema_values xs @ suffix))) ==
      Some (id, [length xs] @ (enc_schema_values xs @ suffix)));
  assert (dec_nat ([length xs] @ (enc_schema_values xs @ suffix)) ==
      Some (length xs, enc_schema_values xs @ suffix));
  assert (dec_schema_values_fuel (fuel - 1) (length xs)
    (enc_schema_values xs @ suffix) == Some (xs,suffix));
  FStar.Pervasives.reveal_opaque (`%dec_schema_values_fuel) dec_schema_values_fuel;
  FStar.Pervasives.reveal_opaque (`%dec_schema_value_step_fuel) dec_schema_value_step_fuel;
  enc_constructor_equation id xs;
  ()

let index_call_step_from_values (fuel:nat) (id:schema_identity)
    (xs:list schema_value_expr) (suffix:bytes)
  : Lemma
      (requires (fuel > 0 /\
        dec_schema_values_fuel (fuel - 1) (length xs)
          (enc_schema_values xs @ suffix) == Some (xs,suffix)))
      (ensures
        (dec_schema_value_step_fuel fuel
          ([12] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs @ suffix) ==
         Some (SchemaIndexCallValue id xs,suffix))) =
  append_assoc_local [12] (enc_schema_identity id)
    ([length xs] @ (enc_schema_values xs @ suffix));
  append_assoc_local (enc_schema_identity id) [length xs]
    (enc_schema_values xs @ suffix);
  append_assoc_local [length xs] (enc_schema_values xs) suffix;
  schema_identity_decode_encoding_suffix id
    ([length xs] @ enc_schema_values xs @ suffix);
  dec_nat_prefix (length xs) (enc_schema_values xs @ suffix);
  assert (dec_schema_identity
    (enc_schema_identity id @ ([length xs] @ (enc_schema_values xs @ suffix))) ==
      Some (id, [length xs] @ (enc_schema_values xs @ suffix)));
  assert (dec_nat ([length xs] @ (enc_schema_values xs @ suffix)) ==
      Some (length xs, enc_schema_values xs @ suffix));
  assert (dec_schema_values_fuel (fuel - 1) (length xs)
    (enc_schema_values xs @ suffix) == Some (xs,suffix));
  FStar.Pervasives.reveal_opaque (`%dec_schema_values_fuel) dec_schema_values_fuel;
  FStar.Pervasives.reveal_opaque (`%dec_schema_value_step_fuel) dec_schema_value_step_fuel;
  enc_index_call_equation id xs;
  ()

let values_step_from_parts (fuel:nat) (x:schema_value_expr)
    (tail:list schema_value_expr) (suffix:bytes)
  : Lemma
      (requires (fuel > 0 /\
        dec_schema_value_fuel (fuel - 1)
          (enc_schema_value x @ enc_schema_values tail @ suffix) ==
            Some (x, enc_schema_values tail @ suffix) /\
        dec_schema_values_fuel (fuel - 1) (length tail)
          (enc_schema_values tail @ suffix) == Some (tail,suffix)))
      (ensures
        (dec_schema_values_fuel fuel (length (x::tail))
          (enc_schema_values (x::tail) @ suffix) == Some (x::tail,suffix))) =
  enc_values_unfold x tail;
  assert (length (x::tail) == 1 + length tail);
  assert (0 < length (x::tail));
  assert (length (x::tail) - 1 == length tail);
  assert (enc_schema_values (x::tail) == enc_schema_value x @ enc_schema_values tail);
  append_assoc_local (enc_schema_value x) (enc_schema_values tail) suffix;
  assert ((enc_schema_value x @ enc_schema_values tail) @ suffix ==
    enc_schema_value x @ (enc_schema_values tail @ suffix));
  dec_schema_values_fuel_equation fuel (length (x::tail))
    (enc_schema_value x @ enc_schema_values tail @ suffix);
  assert (dec_schema_values_fuel fuel (length (x::tail))
    (enc_schema_value x @ enc_schema_values tail @ suffix) ==
    (match dec_schema_value_fuel (fuel - 1)
      (enc_schema_value x @ enc_schema_values tail @ suffix) with
     | None -> None
     | Some (head, rest) ->
         match dec_schema_values_fuel (fuel - 1) (length tail) rest with
         | None -> None
         | Some (xs, final) -> Some (head::xs, final)));
  assert (dec_schema_value_fuel (fuel - 1)
    (enc_schema_value x @ enc_schema_values tail @ suffix) ==
      Some (x, enc_schema_values tail @ suffix));
  assert (dec_schema_values_fuel (fuel - 1) (length tail)
    (enc_schema_values tail @ suffix) == Some (tail,suffix));
  ()

let value_wrapper_from_step (fuel:nat) (v:schema_value_expr) (suffix:bytes)
  : Lemma
      (requires (fuel > 0 /\
        dec_schema_value_step_fuel (fuel - 1) (enc_schema_value v @ suffix) ==
          Some (v,suffix)))
      (ensures (dec_schema_value_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix))) = ()

let rec value_fuel_roundtrip (v:schema_value_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (vneed v <= fuel))
      (ensures (dec_schema_value_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix)))
      (decreases fuel) =
  vneed_positive v;
  if fuel = 0 then (assert (False); ())
  else
    value_step_roundtrip v suffix (fuel - 1);
    value_wrapper_from_step fuel v suffix;
    ()
and value_step_roundtrip (v:schema_value_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (fuel > 0 /\ vneed v <= fuel + 1))
      (ensures (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix)))
      (decreases fuel) =
  FStar.Pervasives.reveal_opaque (`%dec_schema_value_step_fuel) dec_schema_value_step_fuel;
  match v with
  | SchemaBound n ->
      dec_nat_prefix n suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaRoot ->
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaPort n ->
      dec_nat_prefix n suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaConstant id payload ->
      append_assoc_local [3] (enc_codec_identity id) (enc_seq payload @ suffix);
      append_assoc_local (enc_codec_identity id) (enc_seq payload) suffix;
      codec_identity_decode_encoding_suffix id (enc_seq payload @ suffix);
      sequence_decode_encoding_suffix payload suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaUnitValue ->
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaBoolValue b ->
      dec_bool_prefix b suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaNatValue n ->
      dec_nat_prefix n suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaIntValue n ->
      dec_int_prefix n suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaPairValue x y ->
      assert (vneed x <= fuel - 1);
      assert (vneed y <= fuel - 1);
      append_assoc_local (enc_schema_value x) (enc_schema_value y) suffix;
      value_fuel_roundtrip x (enc_schema_value y @ suffix) (fuel - 1);
      value_fuel_roundtrip y suffix (fuel - 1);
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaFstValue x | SchemaSndValue x ->
      assert (vneed x <= fuel - 1);
      value_fuel_roundtrip x suffix (fuel - 1);
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) == Some (v,suffix));
      ()
  | SchemaConstructorValue id xs ->
      assert (xsneed xs <= fuel - 1);
      xs_fuel_roundtrip xs suffix (fuel - 1);
      enc_constructor_equation id xs;
      append_assoc_local [11] (enc_schema_identity id)
        ([length xs] @ (enc_schema_values xs @ suffix));
      append_assoc_local (enc_schema_identity id) [length xs]
        (enc_schema_values xs @ suffix);
      append_assoc_local [length xs] (enc_schema_values xs) suffix;
      append_assoc_local [11]
        (enc_schema_identity id @ ([length xs] @ enc_schema_values xs)) suffix;
      append_assoc_local (enc_schema_identity id)
        ([length xs] @ enc_schema_values xs) suffix;
      assert (v == SchemaConstructorValue id xs);
      assert (enc_schema_value v == enc_schema_value (SchemaConstructorValue id xs));
      assert (enc_schema_value v @ suffix ==
        [11] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs @ suffix);
      constructor_step_from_values fuel id xs suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) ==
        Some (v,suffix));
      ()
  | SchemaIndexCallValue id xs ->
      assert (xsneed xs <= fuel - 1);
      xs_fuel_roundtrip xs suffix (fuel - 1);
      enc_index_call_equation id xs;
      append_assoc_local [12] (enc_schema_identity id)
        ([length xs] @ (enc_schema_values xs @ suffix));
      append_assoc_local (enc_schema_identity id) [length xs]
        (enc_schema_values xs @ suffix);
      append_assoc_local [length xs] (enc_schema_values xs) suffix;
      append_assoc_local [12]
        (enc_schema_identity id @ ([length xs] @ enc_schema_values xs)) suffix;
      append_assoc_local (enc_schema_identity id)
        ([length xs] @ enc_schema_values xs) suffix;
      assert (v == SchemaIndexCallValue id xs);
      assert (enc_schema_value v == enc_schema_value (SchemaIndexCallValue id xs));
      assert (enc_schema_value v @ suffix ==
        [12] @ enc_schema_identity id @ [length xs] @ enc_schema_values xs @ suffix);
      index_call_step_from_values fuel id xs suffix;
      assert (dec_schema_value_step_fuel fuel (enc_schema_value v @ suffix) ==
        Some (v,suffix));
      ()
and xs_fuel_roundtrip (xs:list schema_value_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (xsneed xs <= fuel))
      (ensures (dec_schema_values_fuel fuel (length xs) (enc_schema_values xs @ suffix) == Some (xs,suffix)))
      (decreases fuel) =
  match xs with
  | [] -> ()
  | x::tail ->
      assert (vneed x <= fuel - 1);
      assert (xsneed tail <= fuel - 1);
      value_fuel_roundtrip x (enc_schema_values tail @ suffix) (fuel - 1);
      xs_fuel_roundtrip tail suffix (fuel - 1);
      values_step_from_parts fuel x tail suffix;
      ()

let value_roundtrip_all (v:schema_value_expr)
  : Lemma (ensures (decode_schema_value (enc_schema_value v) == Some v)) =
  vneed_bound v;
  value_fuel_roundtrip v [] (parser_fuel (enc_schema_value v));
  ()

let pneed (p:schema_predicate_expr) : nat = parser_fuel (enc_schema_pred p)

let rec pred_fuel_roundtrip (p:schema_predicate_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (pneed p <= fuel))
      (ensures (dec_schema_pred_fuel fuel (enc_schema_pred p @ suffix) == Some (p,suffix)))
      (decreases fuel) =
  FStar.Pervasives.reveal_opaque (`%dec_schema_pred_fuel) dec_schema_pred_fuel;
  if fuel = 0 then (assert (False); ())
  else pred_step_roundtrip p suffix (fuel - 1)
and pred_step_roundtrip (p:schema_predicate_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (fuel > 0 /\ pneed p <= fuel + 1))
      (ensures (dec_schema_pred_step_fuel fuel (enc_schema_pred p @ suffix) == Some (p,suffix)))
      (decreases fuel) =
  FStar.Pervasives.reveal_opaque (`%dec_schema_pred_step_fuel) dec_schema_pred_step_fuel;
  match p with
  | SchemaTrue -> assert (dec_schema_pred_step_fuel fuel (enc_schema_pred p @ suffix) == Some (p,suffix)); ()
  | SchemaFalse -> assert (dec_schema_pred_step_fuel fuel (enc_schema_pred p @ suffix) == Some (p,suffix)); ()
  | SchemaEqual x y ->
      FStar.List.Tot.Properties.append_length [2] (enc_schema_value x @ enc_schema_value y);
      append_assoc_local [2] (enc_schema_value x) (enc_schema_value y @ suffix);
      append_assoc_local (enc_schema_value x) (enc_schema_value y) suffix;
      vneed_bound x;
      vneed_bound y;
      assert (vneed x <= fuel - 1);
      assert (vneed y <= fuel - 1);
      value_fuel_roundtrip x (enc_schema_value y @ suffix) (fuel - 1);
      value_fuel_roundtrip y suffix (fuel - 1);
      assert (dec_schema_pred_step_fuel fuel (enc_schema_pred p @ suffix) == Some (p,suffix));
      ()
  | SchemaAnd left right ->
      FStar.List.Tot.Properties.append_length [3] (enc_schema_pred left @ enc_schema_pred right);
      append_assoc_local [3] (enc_schema_pred left) (enc_schema_pred right @ suffix);
      append_assoc_local (enc_schema_pred left) (enc_schema_pred right) suffix;
      assert (pneed left <= fuel - 1);
      assert (pneed right <= fuel - 1);
      pred_fuel_roundtrip left (enc_schema_pred right @ suffix) (fuel - 1);
      pred_fuel_roundtrip right suffix (fuel - 1);
      assert (dec_schema_pred_step_fuel fuel (enc_schema_pred p @ suffix) == Some (p,suffix));
      ()

let predicate_roundtrip_all (p:schema_predicate_expr)
  : Lemma (ensures (decode_schema_pred (enc_schema_pred p) == Some p)) =
  pred_fuel_roundtrip p [] (parser_fuel (enc_schema_pred p));
  ()

let tneed (t:schema_type_expr) : nat = parser_fuel (enc_schema_type t)

let rec type_fuel_roundtrip (t:schema_type_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (tneed t <= fuel))
      (ensures (dec_schema_type_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)))
      (decreases fuel) =
  FStar.Pervasives.reveal_opaque (`%dec_schema_type_fuel) dec_schema_type_fuel;
  if fuel = 0 then (assert (False); ())
  else type_step_roundtrip t suffix (fuel - 1)
and type_step_roundtrip (t:schema_type_expr) (suffix:bytes) (fuel:nat)
  : Lemma
      (requires (fuel > 0 /\ tneed t <= fuel + 1))
      (ensures (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)))
      (decreases fuel) =
  FStar.Pervasives.reveal_opaque (`%dec_schema_type_step_fuel) dec_schema_type_step_fuel;
  match t with
  | SchemaAtom id ->
      schema_identity_decode_encoding_suffix id suffix;
      append_assoc_local [0] (enc_schema_identity id) suffix;
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaUnit -> assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaBool -> assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaNat -> assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaInt -> assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaProduct left right ->
      FStar.List.Tot.Properties.append_length [5] (enc_schema_type left @ enc_schema_type right);
      append_assoc_local [5] (enc_schema_type left) (enc_schema_type right @ suffix);
      append_assoc_local (enc_schema_type left) (enc_schema_type right) suffix;
      assert (tneed left <= fuel - 1);
      assert (tneed right <= fuel - 1);
      type_fuel_roundtrip left (enc_schema_type right @ suffix) (fuel - 1);
      type_fuel_roundtrip right suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaSum left right ->
      FStar.List.Tot.Properties.append_length [6] (enc_schema_type left @ enc_schema_type right);
      append_assoc_local [6] (enc_schema_type left) (enc_schema_type right @ suffix);
      append_assoc_local (enc_schema_type left) (enc_schema_type right) suffix;
      assert (tneed left <= fuel - 1);
      assert (tneed right <= fuel - 1);
      type_fuel_roundtrip left (enc_schema_type right @ suffix) (fuel - 1);
      type_fuel_roundtrip right suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaList x ->
      FStar.List.Tot.Properties.append_length [7] (enc_schema_type x);
      append_assoc_local [7] (enc_schema_type x) suffix;
      assert (tneed x <= fuel - 1);
      type_fuel_roundtrip x suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaOption x ->
      FStar.List.Tot.Properties.append_length [8] (enc_schema_type x);
      append_assoc_local [8] (enc_schema_type x) suffix;
      assert (tneed x <= fuel - 1);
      type_fuel_roundtrip x suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaSigma left right ->
      FStar.List.Tot.Properties.append_length [9] (enc_schema_type left @ enc_schema_type right);
      append_assoc_local [9] (enc_schema_type left) (enc_schema_type right @ suffix);
      append_assoc_local (enc_schema_type left) (enc_schema_type right) suffix;
      assert (tneed left <= fuel - 1);
      assert (tneed right <= fuel - 1);
      type_fuel_roundtrip left (enc_schema_type right @ suffix) (fuel - 1);
      type_fuel_roundtrip right suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaFamily id xs ->
      xsneed_bound xs;
      FStar.List.Tot.Properties.append_length [10]
        (enc_schema_identity id @ [length xs] @ enc_schema_values xs);
      FStar.List.Tot.Properties.append_length (enc_schema_identity id)
        ([length xs] @ enc_schema_values xs);
      FStar.List.Tot.Properties.append_length [length xs] (enc_schema_values xs);
      append_assoc_local [10] (enc_schema_identity id)
        ([length xs] @ (enc_schema_values xs @ suffix));
      append_assoc_local (enc_schema_identity id) [length xs]
        (enc_schema_values xs @ suffix);
      append_assoc_local [length xs] (enc_schema_values xs) suffix;
      append_assoc_local [10]
        (enc_schema_identity id @ ([length xs] @ enc_schema_values xs)) suffix;
      append_assoc_local (enc_schema_identity id)
        ([length xs] @ enc_schema_values xs) suffix;
      schema_identity_decode_encoding_suffix id ([length xs] @ (enc_schema_values xs @ suffix));
      dec_nat_prefix (length xs) (enc_schema_values xs @ suffix);
      assert (xsneed xs <= fuel - 1);
      xs_fuel_roundtrip xs suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()
  | SchemaRefine base predicate ->
      FStar.List.Tot.Properties.append_length [11] (enc_schema_type base @ enc_schema_pred predicate);
      append_assoc_local [11] (enc_schema_type base) (enc_schema_pred predicate @ suffix);
      append_assoc_local (enc_schema_type base) (enc_schema_pred predicate) suffix;
      assert (tneed base <= fuel - 1);
      assert (pneed predicate <= fuel - 1);
      type_fuel_roundtrip base (enc_schema_pred predicate @ suffix) (fuel - 1);
      pred_fuel_roundtrip predicate suffix (fuel - 1);
      assert (dec_schema_type_step_fuel fuel (enc_schema_type t @ suffix) == Some (t,suffix)); ()

let type_roundtrip_all (t:schema_type_expr)
  : Lemma (ensures (decode_schema_type (enc_schema_type t) == Some t)) =
  type_fuel_roundtrip t [] (parser_fuel (enc_schema_type t));
  ()

let value_encoder_injective (left right:schema_value_expr)
    (same:enc_schema_value left == enc_schema_value right)
  : Lemma (left == right) =
  value_roundtrip_all left;
  value_roundtrip_all right;
  assert (decode_schema_value (enc_schema_value left) == decode_schema_value (enc_schema_value right));
  ()

let predicate_encoder_injective (left right:schema_predicate_expr)
    (same:enc_schema_pred left == enc_schema_pred right)
  : Lemma (left == right) =
  predicate_roundtrip_all left;
  predicate_roundtrip_all right;
  assert (decode_schema_pred (enc_schema_pred left) == decode_schema_pred (enc_schema_pred right));
  ()

let type_encoder_injective (left right:schema_type_expr)
    (same:enc_schema_type left == enc_schema_type right)
  : Lemma (left == right) =
  type_roundtrip_all left;
  type_roundtrip_all right;
  assert (decode_schema_type (enc_schema_type left) == decode_schema_type (enc_schema_type right));
  ()

let value_trailing_rejected (v:schema_value_expr) (head:nat) (tail:bytes)
  : Lemma (decode_schema_value (enc_schema_value v @ (head::tail)) == None) =
  vneed_bound v;
  FStar.List.Tot.Properties.append_length (enc_schema_value v) (head::tail);
  assert (vneed v <= parser_fuel (enc_schema_value v @ (head::tail)));
  value_fuel_roundtrip v (head::tail)
    (parser_fuel (enc_schema_value v @ (head::tail)));
  FStar.Pervasives.reveal_opaque (`%decode_schema_value) decode_schema_value;
  assert (dec_schema_value (enc_schema_value v @ (head::tail)) == Some (v,head::tail));
  ()

let predicate_trailing_rejected (p:schema_predicate_expr) (head:nat) (tail:bytes)
  : Lemma (decode_schema_pred (enc_schema_pred p @ (head::tail)) == None) =
  FStar.List.Tot.Properties.append_length (enc_schema_pred p) (head::tail);
  assert (pneed p <= parser_fuel (enc_schema_pred p @ (head::tail)));
  pred_fuel_roundtrip p (head::tail)
    (parser_fuel (enc_schema_pred p @ (head::tail)));
  FStar.Pervasives.reveal_opaque (`%decode_schema_pred) decode_schema_pred;
  assert (dec_schema_pred (enc_schema_pred p @ (head::tail)) == Some (p,head::tail));
  ()

let type_trailing_rejected (t:schema_type_expr) (head:nat) (tail:bytes)
  : Lemma (decode_schema_type (enc_schema_type t @ (head::tail)) == None) =
  FStar.List.Tot.Properties.append_length (enc_schema_type t) (head::tail);
  assert (tneed t <= parser_fuel (enc_schema_type t @ (head::tail)));
  type_fuel_roundtrip t (head::tail)
    (parser_fuel (enc_schema_type t @ (head::tail)));
  FStar.Pervasives.reveal_opaque (`%decode_schema_type) decode_schema_type;
  assert (dec_schema_type (enc_schema_type t @ (head::tail)) == Some (t,head::tail));
  ()

let root_step_equation (fuel:nat) (suffix:bytes)
  : Lemma (requires (fuel > 0))
      (ensures (dec_schema_value_step_fuel fuel ([1] @ suffix) == Some (SchemaRoot,suffix))) = ()
