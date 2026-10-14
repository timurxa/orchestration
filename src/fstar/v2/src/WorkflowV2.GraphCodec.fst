module WorkflowV2.GraphCodec

open FStar.List.Tot
open FStar.List.Tot.Properties
open FStar.String
open FStar.Char
open WorkflowV2.Kernel

// Fixed format over Kernel.bytes (a list of mathematical naturals). Every
// variable-size field is length-prefixed; the public parser requires EOF.
let enc_nat (n:nat) : bytes = [n]
let enc_seq (xs:bytes) : bytes = FStar.List.Tot.length xs :: xs

let rec dec_seq (n:nat) (input:bytes) : Tot (option (bytes & bytes))
  (decreases n) =
  if n = 0 then Some ([], input)
  else match input with
       | [] -> None
       | b::tail ->
           match dec_seq (n - 1) tail with
           | None -> None
           | Some (front, rest) -> Some (b::front, rest)

let dec_nat (input:bytes) : option (nat & bytes) =
  match input with | [] -> None | n::tail -> Some (n, tail)

let dec_len_seq (input:bytes) : option (bytes & bytes) =
  match dec_nat input with
  | None -> None
  | Some (n, tail) -> dec_seq n tail

let rec enc_chars (cs:list char) : bytes =
  match cs with | [] -> [] | c::tail -> int_of_char c :: enc_chars tail

let rec enc_chars_length (cs:list char)
    : Lemma (ensures (FStar.List.Tot.length (enc_chars cs) ==
                      FStar.List.Tot.length cs)) (decreases cs) =
  match cs with
  | [] -> ()
  | _::tail -> enc_chars_length tail

let enc_string (s:string) : bytes =
  enc_seq (enc_chars (list_of_string s))

let rec dec_chars (n:nat) (input:bytes) : Tot (option (list char & bytes))
  (decreases n) =
  if n = 0 then Some ([], input)
  else match input with
       | [] -> None
       | code::tail ->
           // FStar.Char's char_code invariant excludes 0xd7ff as well as the
           // surrogate range, so mirror its exact bound before char_of_int.
           if code < 0xd7ff then
             match dec_chars (n - 1) tail with
             | None -> None
             | Some (cs, rest) -> Some (char_of_int code :: cs, rest)
           else if code >= 0xe000 && code <= 0x10ffff then
             match dec_chars (n - 1) tail with
             | None -> None
             | Some (cs, rest) -> Some (char_of_int code :: cs, rest)
           else None

let dec_string (input:bytes) : option (string & bytes) =
  match dec_nat input with
  | None -> None
  | Some (n, tail) ->
      match dec_chars n tail with
      | None -> None
      | Some (cs, rest) -> Some (string_of_list cs, rest)

let char_int_roundtrip (c:char)
    : Lemma (char_of_int (int_of_char c) == c) = ()

let rec dec_chars_encoding (cs:list char) (suffix:bytes)
    : Lemma (ensures (dec_chars (FStar.List.Tot.length cs)
       (enc_chars cs @ suffix) == Some (cs, suffix))) (decreases cs) =
  match cs with
  | [] -> ()
  | c::tail ->
      char_int_roundtrip c;
      dec_chars_encoding tail suffix

let rec seq_items_decode_encoding (bs:bytes) (suffix:bytes)
    : Lemma (ensures (dec_seq (FStar.List.Tot.length bs) (bs @ suffix) ==
                      Some (bs, suffix))) (decreases bs) =
  match bs with
  | [] -> ()
  | _::tail -> seq_items_decode_encoding tail suffix

let sequence_decode_encoding_suffix (bs suffix:bytes)
    : Lemma (dec_len_seq (enc_seq bs @ suffix) == Some (bs, suffix)) =
  seq_items_decode_encoding bs suffix

let sequence_decode_encoding (bs:bytes)
    : Lemma (dec_len_seq (enc_seq bs) == Some (bs, [])) =
  sequence_decode_encoding_suffix bs []

let dec_string_encoding_suffix (s:string) (suffix:bytes)
    : Lemma (dec_string (enc_string s @ suffix) == Some (s, suffix)) =
  let cs = list_of_string s in
  enc_chars_length cs;
  dec_chars_encoding cs suffix;
  FStar.String.string_of_list_of_string s

let dec_string_encoding (s:string)
    : Lemma (dec_string (enc_string s) == Some (s, [])) =
  dec_string_encoding_suffix s []

let rec append_assoc_local (left middle right:bytes)
    : Lemma (ensures ((left @ middle) @ right == left @ (middle @ right)))
      (decreases left) =
  match left with
  | [] -> ()
  | _::tail -> append_assoc_local tail middle right

let enc_codec_identity (x:codec_identity) : bytes =
  enc_string x.codec_name @ enc_nat x.codec_version @ enc_seq x.codec_build

let enc_codec_identity_def (x:codec_identity)
    : Lemma (enc_codec_identity x ==
      enc_string x.codec_name @
        (enc_nat x.codec_version @ enc_seq x.codec_build)) = ()

let dec_codec_identity (input:bytes) : option (codec_identity & bytes) =
  match dec_string input with
  | None -> None
  | Some (name, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (version, tail2) ->
          match dec_len_seq tail2 with
          | None -> None
          | Some (build, rest) ->
              Some ({codec_name=name; codec_version=version;
                     codec_build=build}, rest)

let codec_identity_decode_encoding_suffix (id:codec_identity) (suffix:bytes)
    : Lemma (dec_codec_identity (enc_codec_identity id @ suffix) ==
             Some (id, suffix)) =
  append_assoc_local (enc_string id.codec_name)
    (enc_nat id.codec_version @ enc_seq id.codec_build) suffix;
  append_assoc_local (enc_nat id.codec_version) (enc_seq id.codec_build) suffix;
  enc_codec_identity_def id;
  dec_string_encoding_suffix id.codec_name
    (enc_nat id.codec_version @ enc_seq id.codec_build @ suffix);
  sequence_decode_encoding_suffix id.codec_build suffix

let codec_identity_decode_encoding (id:codec_identity)
    : Lemma (dec_codec_identity (enc_codec_identity id) == Some (id, [])) =
  codec_identity_decode_encoding_suffix id []

let enc_code_identity (x:code_identity) : bytes =
  enc_string x.code_name @ enc_nat x.code_version @ enc_seq x.code_build

let dec_code_identity (input:bytes) : option (code_identity & bytes) =
  match dec_string input with
  | None -> None
  | Some (name, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (version, tail2) ->
          match dec_len_seq tail2 with
          | None -> None
          | Some (build, rest) ->
              Some ({code_name=name; code_version=version;
                     code_build=build}, rest)

let code_identity_decode_encoding_suffix (id:code_identity) (suffix:bytes)
    : Lemma (dec_code_identity (enc_code_identity id @ suffix) ==
             Some (id, suffix)) =
  append_assoc_local (enc_string id.code_name)
    (enc_nat id.code_version @ enc_seq id.code_build) suffix;
  append_assoc_local (enc_nat id.code_version) (enc_seq id.code_build) suffix;
  dec_string_encoding_suffix id.code_name
    (enc_nat id.code_version @ enc_seq id.code_build @ suffix);
  sequence_decode_encoding_suffix id.code_build suffix

let enc_operation_identity (x:operation_identity) : bytes =
  enc_string x.operation_name @ enc_nat x.operation_version @
  enc_seq x.operation_build

let dec_operation_identity (input:bytes)
    : option (operation_identity & bytes) =
  match dec_string input with
  | None -> None
  | Some (name, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (version, tail2) ->
          match dec_len_seq tail2 with
          | None -> None
          | Some (build, rest) ->
              Some ({operation_name=name; operation_version=version;
                     operation_build=build}, rest)

let operation_identity_decode_encoding_suffix
    (id:operation_identity) (suffix:bytes)
    : Lemma (dec_operation_identity (enc_operation_identity id @ suffix) ==
             Some (id, suffix)) =
  append_assoc_local (enc_string id.operation_name)
    (enc_nat id.operation_version @ enc_seq id.operation_build) suffix;
  append_assoc_local (enc_nat id.operation_version)
    (enc_seq id.operation_build) suffix;
  dec_string_encoding_suffix id.operation_name
    (enc_nat id.operation_version @ enc_seq id.operation_build @ suffix);
  sequence_decode_encoding_suffix id.operation_build suffix

let enc_generator_identity (x:generator_identity) : bytes =
  enc_string x.generator_name @ enc_nat x.generator_version @
  enc_seq x.generator_build

let dec_generator_identity (input:bytes)
    : option (generator_identity & bytes) =
  match dec_string input with
  | None -> None
  | Some (name, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (version, tail2) ->
          match dec_len_seq tail2 with
          | None -> None
          | Some (build, rest) ->
              Some ({generator_name=name; generator_version=version;
                     generator_build=build}, rest)

let generator_identity_decode_encoding_suffix
    (id:generator_identity) (suffix:bytes)
    : Lemma (dec_generator_identity (enc_generator_identity id @ suffix) ==
             Some (id, suffix)) =
  append_assoc_local (enc_string id.generator_name)
    (enc_nat id.generator_version @ enc_seq id.generator_build) suffix;
  append_assoc_local (enc_nat id.generator_version)
    (enc_seq id.generator_build) suffix;
  dec_string_encoding_suffix id.generator_name
    (enc_nat id.generator_version @ enc_seq id.generator_build @ suffix);
  sequence_decode_encoding_suffix id.generator_build suffix

let enc_graph_codec_identity (x:graph_codec_identity) : bytes =
  enc_string x.graph_codec_name @ enc_nat x.graph_codec_version @
  enc_seq x.graph_codec_build

let dec_graph_codec_identity (input:bytes)
    : option (graph_codec_identity & bytes) =
  match dec_string input with
  | None -> None
  | Some (name, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (version, tail2) ->
          match dec_len_seq tail2 with
          | None -> None
          | Some (build, rest) ->
              Some ({graph_codec_name=name; graph_codec_version=version;
                     graph_codec_build=build}, rest)

let graph_codec_identity_decode_encoding_suffix
    (id:graph_codec_identity) (suffix:bytes)
    : Lemma (dec_graph_codec_identity
       (enc_graph_codec_identity id @ suffix) == Some (id, suffix)) =
  append_assoc_local (enc_string id.graph_codec_name)
    (enc_nat id.graph_codec_version @ enc_seq id.graph_codec_build) suffix;
  append_assoc_local (enc_nat id.graph_codec_version)
    (enc_seq id.graph_codec_build) suffix;
  dec_string_encoding_suffix id.graph_codec_name
    (enc_nat id.graph_codec_version @ enc_seq id.graph_codec_build @ suffix);
  sequence_decode_encoding_suffix id.graph_codec_build suffix

let enc_work_identity (x:work_identity) : bytes =
  match x with
  | CodeWorkIdentity id -> 0 :: enc_code_identity id
  | OperationWorkIdentity id -> 1 :: enc_operation_identity id
  | GeneratorWorkIdentity id -> 2 :: enc_generator_identity id

let dec_work_identity (input:bytes) : option (work_identity & bytes) =
  match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> (match dec_code_identity tail with
             | None -> None
             | Some (id, rest) -> Some (CodeWorkIdentity id, rest))
      | 1 -> (match dec_operation_identity tail with
             | None -> None
             | Some (id, rest) -> Some (OperationWorkIdentity id, rest))
      | 2 -> (match dec_generator_identity tail with
             | None -> None
             | Some (id, rest) -> Some (GeneratorWorkIdentity id, rest))
      | _ -> None

let work_identity_decode_encoding_suffix (id:work_identity) (suffix:bytes)
    : Lemma (dec_work_identity (enc_work_identity id @ suffix) ==
             Some (id, suffix)) =
  match id with
  | CodeWorkIdentity code_id ->
      code_identity_decode_encoding_suffix code_id suffix
  | OperationWorkIdentity operation_id ->
      operation_identity_decode_encoding_suffix operation_id suffix
  | GeneratorWorkIdentity generator_id ->
      generator_identity_decode_encoding_suffix generator_id suffix

let enc_output_identity (x:output_identity) : bytes =
  match x with
  | ValueOutputIdentity id -> 0 :: enc_codec_identity id
  | GeneratedGraphCodecIdentity id -> 1 :: enc_graph_codec_identity id

let dec_output_identity (input:bytes) : option (output_identity & bytes) =
  match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> (match dec_codec_identity tail with
             | None -> None
             | Some (id, rest) -> Some (ValueOutputIdentity id, rest))
      | 1 -> (match dec_graph_codec_identity tail with
             | None -> None
             | Some (id, rest) -> Some (GeneratedGraphCodecIdentity id, rest))
      | _ -> None

let output_identity_decode_encoding_suffix (id:output_identity) (suffix:bytes)
    : Lemma (dec_output_identity (enc_output_identity id @ suffix) ==
             Some (id, suffix)) =
  match id with
  | ValueOutputIdentity codec_id ->
      codec_identity_decode_encoding_suffix codec_id suffix
  | GeneratedGraphCodecIdentity graph_id ->
      graph_codec_identity_decode_encoding_suffix graph_id suffix

let enc_durable_work_ref (x:durable_work_ref) : bytes =
  enc_work_identity x.durable_kind @ enc_codec_identity x.durable_input_codec @
  enc_output_identity x.durable_output

let dec_durable_work_ref (input:bytes)
    : option (durable_work_ref & bytes) =
  match dec_work_identity input with
  | None -> None
  | Some (kind, tail) ->
      match dec_codec_identity tail with
      | None -> None
      | Some (input_codec, tail2) ->
          match dec_output_identity tail2 with
          | None -> None
          | Some (output, rest) ->
              Some ({durable_kind=kind; durable_input_codec=input_codec;
                     durable_output=output}, rest)

let durable_work_ref_decode_encoding_suffix
    (r:durable_work_ref) (suffix:bytes)
    : Lemma (dec_durable_work_ref (enc_durable_work_ref r @ suffix) ==
             Some (r, suffix)) =
  append_assoc_local (enc_work_identity r.durable_kind)
    (enc_codec_identity r.durable_input_codec @
     enc_output_identity r.durable_output) suffix;
  append_assoc_local (enc_codec_identity r.durable_input_codec)
    (enc_output_identity r.durable_output) suffix;
  work_identity_decode_encoding_suffix r.durable_kind
    (enc_codec_identity r.durable_input_codec @
     enc_output_identity r.durable_output @ suffix);
  codec_identity_decode_encoding_suffix r.durable_input_codec
    (enc_output_identity r.durable_output @ suffix);
  output_identity_decode_encoding_suffix r.durable_output suffix

let rec enc_wire (#i:Type0) (#x:i) (w:wire i x) : bytes =
  match w with
  | RootWire -> [0]
  | OutputWire key -> 1 :: enc_nat key
  | ConstantWire id value -> 2 :: enc_codec_identity id @ enc_seq value
  | PairWire left right ->
      3 :: enc_wire left @ enc_wire right
  | FstWire pair -> 4 :: enc_wire pair
  | SndWire pair -> 5 :: enc_wire pair

let dec_wire_step (#i:Type0) (#x:i)
    (parse_child:bytes -> Tot (option (wire i x & bytes))) (input:bytes)
    : option (wire i x & bytes) =
  match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> Some (RootWire, tail)
      | 1 -> (match dec_nat tail with
             | None -> None
             | Some (key, rest) -> Some (OutputWire key, rest))
      | 2 -> (match dec_codec_identity tail with
             | None -> None
             | Some (id, rest) ->
                 match dec_len_seq rest with
                 | None -> None
                 | Some (value, final) -> Some (ConstantWire id value, final))
      | 3 -> (match parse_child tail with
             | None -> None
             | Some (left, rest2) ->
                 match parse_child rest2 with
                 | None -> None
                 | Some (right, final) ->
                     Some (PairWire left right, final))
      | 4 -> (match parse_child tail with
             | None -> None
             | Some (pair, rest) -> Some (FstWire pair, rest))
      | 5 -> (match parse_child tail with
             | None -> None
             | Some (pair, rest) -> Some (SndWire pair, rest))
      | _ -> None

let rec dec_wire_fuel (#i:Type0) (#x:i) (fuel:nat) (input:bytes)
    : Tot (option (wire i x & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else dec_wire_step (dec_wire_fuel (fuel - 1)) input

let no_wire (#i:Type0) (#x:i) : option (wire i x & bytes) = None

let dec_wire_fuel_equation (#i:Type0) (#x:i) (fuel:nat) (input:bytes)
    : Lemma (dec_wire_fuel fuel input ==
             (if fuel = 0 then no_wire #i #x
              else dec_wire_step #i #x
                (dec_wire_fuel #i #x (fuel - 1)) input)) = ()

let dec_wire (#i:Type0) (#x:i) (input:bytes)
    : Tot (option (wire i x & bytes)) =
  dec_wire_fuel (FStar.List.Tot.length input) input

let enc_graph_node (#i:Type0) (#x:i) (n:graph_node i x) : bytes =
  enc_nat n.graph_node_key @ enc_durable_work_ref n.graph_node_work @
  enc_wire n.graph_node_input

let dec_graph_node (#i:Type0) (#x:i) (input:bytes)
    : option (graph_node i x & bytes) =
  match dec_nat input with
  | None -> None
  | Some (key, tail) ->
      match dec_durable_work_ref tail with
      | None -> None
      | Some (work, tail2) ->
          match dec_wire tail2 with
          | None -> None
          | Some (wiring, rest) ->
              Some ({graph_node_key=key; graph_node_work=work;
                     graph_node_input=wiring}, rest)

let rec enc_nodes (#i:Type0) (#x:i) (nodes:list (graph_node i x)) : bytes =
  match nodes with | [] -> [] | node::tail ->
    enc_graph_node node @ enc_nodes tail

let rec dec_nodes (#i:Type0) (#x:i) (count:nat) (input:bytes)
    : Tot (option (list (graph_node i x) & bytes)) (decreases count) =
  if count = 0 then Some ([], input)
  else match dec_graph_node input with
       | None -> None
       | Some (node, rest) ->
           match dec_nodes (count - 1) rest with
           | None -> None
           | Some (tail, final) -> Some (node::tail, final)

let graph_magic : nat = 0x47524150

let encode_graph_syntax (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x) : bytes =
  [graph_magic] @ enc_nat (FStar.List.Tot.length g.graph_nodes) @
  enc_nodes g.graph_nodes @
  enc_wire g.graph_output_wire

let parse_graph_syntax (#i:Type0) (#o:i -> Type0) (x:i) (input:bytes)
    : Tot (option (graph_desc i o x)) =
  match input with
  | graph_magic::tail ->
      (match dec_nat tail with
       | None -> None
       | Some (count, rest) ->
           match dec_nodes count rest with
           | None -> None
           | Some (nodes, after_nodes) ->
               match dec_wire after_nodes with
               | Some (output, []) ->
                   Some ({graph_nodes=nodes; graph_output_wire=output})
               | _ -> None)
  | _ -> None

let decode_graph_syntax (#i:Type0) (#o:i -> Type0) (x:i) (input:bytes)
    : Tot (option (graph_desc i o x)) =
  match parse_graph_syntax x input with
  | None -> None
  | Some g ->
      if input = encode_graph_syntax x g then Some g else None

// Structural induction follows syntax trees; list fields follow their
// declared lengths. Exact EOF makes every accepted byte string canonical.
let max_nat (a b:nat) : nat = if a < b then b else a

let rec wire_depth (#i:Type0) (#x:i) (w:wire i x) : nat =
  match w with
  | RootWire -> 0
  | OutputWire _ -> 0
  | ConstantWire _ _ -> 0
  | PairWire left right ->
      1 + max_nat (wire_depth left) (wire_depth right)
  | FstWire pair -> 1 + wire_depth pair
  | SndWire pair -> 1 + wire_depth pair

let rec wire_depth_fits (#i:Type0) (#x:i) (w:wire i x)
    : Lemma (ensures
        (wire_depth w < FStar.List.Tot.length (enc_wire w)))
      (decreases w) =
  match w with
  | RootWire -> ()
  | OutputWire _ -> ()
  | ConstantWire _ _ -> ()
  | PairWire left right ->
      wire_depth_fits left;
      wire_depth_fits right;
      FStar.List.Tot.Properties.append_length [3]
        (enc_wire left @ enc_wire right);
      FStar.List.Tot.Properties.append_length (enc_wire left) (enc_wire right);
      assert (wire_depth w < FStar.List.Tot.length (enc_wire w))
  | FstWire pair ->
      wire_depth_fits pair;
      FStar.List.Tot.Properties.append_length [4] (enc_wire pair);
      assert (wire_depth w < FStar.List.Tot.length (enc_wire w))
  | SndWire pair ->
      wire_depth_fits pair;
      FStar.List.Tot.Properties.append_length [5] (enc_wire pair);
      assert (wire_depth w < FStar.List.Tot.length (enc_wire w))

let rec wire_decode_encoding_fuel (#i:Type0) (#x:i) (w:wire i x)
    (fuel:nat) (suffix:bytes)
    : Lemma (requires (fuel > 0 /\ wire_depth w < fuel))
      (ensures (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix)))
      (decreases w) =
  dec_wire_fuel_equation #i #x fuel (enc_wire w @ suffix);
  match w with
  | RootWire ->
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))
  | OutputWire key ->
      let out:wire i x = OutputWire key in
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (1 :: (enc_nat key @ suffix)) == Some (out, suffix));
      assert (dec_wire_fuel fuel (enc_wire out @ suffix) == Some (out, suffix))
  | ConstantWire id value ->
      let constant:wire i x = ConstantWire id value in
      append_assoc_local (enc_codec_identity id) (enc_seq value) suffix;
      codec_identity_decode_encoding_suffix id (enc_seq value @ suffix);
      sequence_decode_encoding_suffix value suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (2 :: (enc_codec_identity id @ (enc_seq value @ suffix))) ==
        Some (constant, suffix));
      assert (dec_wire_fuel fuel (enc_wire constant @ suffix) ==
              Some (constant, suffix))
  | PairWire left right ->
      append_assoc_local [3] (enc_wire left) (enc_wire right @ suffix);
      append_assoc_local (enc_wire left) (enc_wire right) suffix;
      assert (fuel - 1 > 0);
      assert (wire_depth left < fuel - 1);
      assert (wire_depth right < fuel - 1);
      wire_decode_encoding_fuel left (fuel - 1) (enc_wire right @ suffix);
      wire_decode_encoding_fuel right (fuel - 1) suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))
  | FstWire pair ->
      assert (fuel - 1 > 0);
      assert (wire_depth pair < fuel - 1);
      wire_decode_encoding_fuel pair (fuel - 1) suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))
  | SndWire pair ->
      assert (fuel - 1 > 0);
      assert (wire_depth pair < fuel - 1);
      wire_decode_encoding_fuel pair (fuel - 1) suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))

let wire_decode_encoding (#i:Type0) (#x:i) (w:wire i x)
    : Lemma (dec_wire (enc_wire w) == Some (w, [])) =
  wire_depth_fits w;
  wire_decode_encoding_fuel w (FStar.List.Tot.length (enc_wire w)) []

let wire_decode_encoding_suffix (#i:Type0) (#x:i) (w:wire i x)
    (suffix:bytes)
    : Lemma (dec_wire (enc_wire w @ suffix) == Some (w, suffix)) =
  FStar.List.Tot.Properties.append_length (enc_wire w) suffix;
  wire_depth_fits w;
  wire_decode_encoding_fuel w
    (FStar.List.Tot.length (enc_wire w @ suffix)) suffix

let durable_ref_decode_encoding (r:durable_work_ref)
    : Lemma (dec_durable_work_ref (enc_durable_work_ref r) == Some (r, [])) =
  durable_work_ref_decode_encoding_suffix r []

let node_decode_encoding_suffix (#i:Type0) (#x:i) (n:graph_node i x)
    (suffix:bytes)
    : Lemma (dec_graph_node (enc_graph_node n @ suffix) ==
             Some (n, suffix)) =
  let rest = enc_durable_work_ref n.graph_node_work @
             (enc_wire n.graph_node_input @ suffix) in
  append_assoc_local (enc_nat n.graph_node_key)
    (enc_durable_work_ref n.graph_node_work @ enc_wire n.graph_node_input)
    suffix;
  append_assoc_local (enc_durable_work_ref n.graph_node_work)
    (enc_wire n.graph_node_input) suffix;
  assert (enc_graph_node n @ suffix == enc_nat n.graph_node_key @ rest);
  assert (dec_nat (enc_nat n.graph_node_key @ rest) ==
          Some (n.graph_node_key, rest));
  wire_decode_encoding_suffix n.graph_node_input suffix;
  durable_work_ref_decode_encoding_suffix n.graph_node_work
    (enc_wire n.graph_node_input @ suffix);
  assert (dec_graph_node (enc_graph_node n @ suffix) == Some (n, suffix))

let node_decode_encoding (#i:Type0) (#x:i) (n:graph_node i x)
    : Lemma (dec_graph_node (enc_graph_node n) == Some (n, [])) =
  node_decode_encoding_suffix n []

let rec nodes_decode_encoding_suffix (#i:Type0) (#x:i)
    (nodes:list (graph_node i x)) (suffix:bytes)
    : Lemma (ensures
        (dec_nodes (FStar.List.Tot.length nodes)
           (enc_nodes nodes @ suffix) == Some (nodes, suffix)))
    (decreases nodes) =
  match nodes with
  | [] -> ()
  | node::tail ->
      append_assoc_local (enc_graph_node node) (enc_nodes tail) suffix;
      node_decode_encoding_suffix node (enc_nodes tail @ suffix);
      nodes_decode_encoding_suffix tail suffix

let rec nodes_decode_encoding (#i:Type0) (#x:i)
    (nodes:list (graph_node i x))
    : Lemma (ensures
        (dec_nodes (FStar.List.Tot.length nodes) (enc_nodes nodes) ==
         Some (nodes, [])))
    (decreases nodes) =
  nodes_decode_encoding_suffix nodes []

let graph_decode_encoding (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
    : Lemma (decode_graph_syntax x (encode_graph_syntax x g) == Some g) =
  nodes_decode_encoding_suffix g.graph_nodes (enc_wire g.graph_output_wire);
  wire_decode_encoding g.graph_output_wire;
  assert (parse_graph_syntax x (encode_graph_syntax x g) == Some g)

let graph_decode_canonical (#i:Type0) (#o:i -> Type0) (x:i) (input:bytes)
    (g:graph_desc i o x)
    : Lemma (decode_graph_syntax x input == Some g ==>
             input == encode_graph_syntax x g) = ()
