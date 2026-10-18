module WorkflowV2.Kernel

// Durable identities and work references {{{1
// Durable bytes and their identities are made concrete here only as simple
// values. Their canonicality and registry resolution laws are V2-01 proof
// obligations; graph structure and well-formedness are defined in V2-02.
type bytes = list nat
// Identity names are values in the abstract wire alphabet, with no text
// semantics or host conversion inside the formal kernel.
type identity_token = bytes
type digest = bytes

type codec_identity = {
  codec_name:identity_token;
  codec_version:nat;
  codec_build:digest
}

type code_identity = {
  code_name:identity_token;
  code_version:nat;
  code_build:digest
}

type operation_identity = {
  operation_name:identity_token;
  operation_version:nat;
  operation_build:digest
}

type generator_identity = {
  generator_name:identity_token;
  generator_version:nat;
  generator_build:digest
}

type graph_codec_identity = {
  graph_codec_name:identity_token;
  graph_codec_version:nat;
  graph_codec_build:digest
}

type schema_identity = {
  schema_name:identity_token;
  schema_version:nat;
  schema_build:digest
}

type charge_metric_identity = {
  charge_metric_name:identity_token;
  charge_metric_version:nat;
  charge_metric_build:digest
}

type artifact_type_identity = {
  artifact_type_name:identity_token;
  artifact_type_version:nat;
  artifact_type_build:digest
}

type artifact_store_identity = {
  artifact_store_name:identity_token;
  artifact_store_version:nat;
  artifact_store_build:digest
}

// These tokens identify replay-context and root-resolution packages. Their
// exact package projection is established with the pinned bundle in A04/P0.
type resolver_identity = {
  resolver_name:identity_token;
  resolver_version:nat;
  resolver_build:digest
}

type root_entry_identity = {
  root_entry_name:identity_token;
  root_entry_version:nat;
  root_entry_build:digest
}

type journal_codec_identity = {
  journal_codec_name:identity_token;
  journal_codec_version:nat;
  journal_codec_build:digest
}

// Contract tokens (validator, adapter/configuration, allocation, codec
// version, denotation law, and artifact interpretation/projection law) are
// selected by their typed field position inside a manifest entry. A04 binds
// those positions to their exact proof-bearing package contracts.
type contract_identity = {
  contract_name:identity_token;
  contract_version:nat;
  contract_build:digest
}

type output_identity =
  | ValueOutputIdentity:codec_identity -> output_identity
  | GeneratedGraphCodecIdentity:graph_codec_identity -> output_identity

// Registry identity is the exact canonical manifest byte sequence. Names and
// digests may index it, but are not logical equality evidence.
type registry_identity = {
  registry_manifest_bytes:bytes
}

let registry_identity_of_bytes (wire:bytes) : registry_identity =
  {registry_manifest_bytes=wire}

let registry_identity_bytes (id:registry_identity) : bytes =
  id.registry_manifest_bytes

let registry_identity_of_bytes_injective (left right:bytes)
    (h:registry_identity_of_bytes left == registry_identity_of_bytes right)
    : Lemma (left == right) = ()

let registry_identity_bytes_injective (left right:registry_identity)
    (h:registry_identity_bytes left == registry_identity_bytes right)
    : Lemma (left == right) = ()

type work_identity =
  | CodeWorkIdentity:code_identity -> work_identity
  | OperationWorkIdentity:operation_identity -> work_identity
  | GeneratorWorkIdentity:generator_identity -> work_identity

// First-order journal and graph form; dependent type indices are recovered by
// resolving this exact identity in the pinned registry.
type durable_work_ref = {
  durable_kind:work_identity;
  durable_input_codec:codec_identity;
  durable_output:output_identity
}

// Shared canonical byte and identity codecs.
open FStar.List.Tot
open FStar.List.Tot.Properties

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

// Identity tokens have no FStar.String conversion here. Their framing and
// inverse use only the local sequence codec.
let enc_identity_token (token:identity_token) : bytes = enc_seq token
let dec_identity_token (input:bytes) : option (identity_token & bytes) =
  dec_len_seq input

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

let identity_token_decode_encoding_suffix
    (token:identity_token) (suffix:bytes)
    : Lemma (dec_identity_token (enc_identity_token token @ suffix) ==
             Some (token, suffix)) =
  sequence_decode_encoding_suffix token suffix

let identity_token_decode_encoding (token:identity_token)
    : Lemma (dec_identity_token (enc_identity_token token) ==
             Some (token, [])) =
  identity_token_decode_encoding_suffix token []

let rec append_assoc_local (left middle right:bytes)
    : Lemma (ensures ((left @ middle) @ right == left @ (middle @ right)))
      (decreases left) =
  match left with
  | [] -> ()
  | _::tail -> append_assoc_local tail middle right

// Common typed token framing used by manifest-only identity domains.
type identity_fields = {
  fields_name:identity_token;
  fields_version:nat;
  fields_build:digest
}

let enc_identity_fields (x:identity_fields) : bytes =
  enc_identity_token x.fields_name @ enc_nat x.fields_version @ enc_seq x.fields_build

let dec_identity_fields (input:bytes)
    : option (identity_fields & bytes) =
  match dec_identity_token input with
  | None -> None
  | Some (name, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (version, tail2) ->
          match dec_len_seq tail2 with
          | None -> None
          | Some (build, rest) ->
              Some ({fields_name=name; fields_version=version;
                     fields_build=build}, rest)

let identity_fields_decode_encoding_suffix
    (id:identity_fields) (suffix:bytes)
    : Lemma (dec_identity_fields (enc_identity_fields id @ suffix) ==
             Some (id, suffix)) =
  append_assoc_local (enc_identity_token id.fields_name)
    (enc_nat id.fields_version @ enc_seq id.fields_build) suffix;
  append_assoc_local (enc_nat id.fields_version)
    (enc_seq id.fields_build) suffix;
  identity_token_decode_encoding_suffix id.fields_name
    (enc_nat id.fields_version @ enc_seq id.fields_build @ suffix);
  sequence_decode_encoding_suffix id.fields_build suffix

let schema_identity_fields (id:schema_identity) : identity_fields =
  {fields_name=id.schema_name; fields_version=id.schema_version;
   fields_build=id.schema_build}

let enc_schema_identity (id:schema_identity) : bytes =
  enc_identity_fields (schema_identity_fields id)

let dec_schema_identity (input:bytes)
    : option (schema_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({schema_name=f.fields_name; schema_version=f.fields_version;
             schema_build=f.fields_build}, rest)

let schema_identity_decode_encoding_suffix
    (id:schema_identity) (suffix:bytes)
    : Lemma (dec_schema_identity (enc_schema_identity id @ suffix) ==
             Some (id, suffix)) =
  identity_fields_decode_encoding_suffix (schema_identity_fields id) suffix

let charge_metric_identity_fields (id:charge_metric_identity)
    : identity_fields =
  {fields_name=id.charge_metric_name;
   fields_version=id.charge_metric_version;
   fields_build=id.charge_metric_build}

let enc_charge_metric_identity (id:charge_metric_identity) : bytes =
  enc_identity_fields (charge_metric_identity_fields id)

let dec_charge_metric_identity (input:bytes)
    : option (charge_metric_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({charge_metric_name=f.fields_name;
             charge_metric_version=f.fields_version;
             charge_metric_build=f.fields_build}, rest)

let charge_metric_identity_decode_encoding_suffix
    (id:charge_metric_identity) (suffix:bytes)
    : Lemma (dec_charge_metric_identity
      (enc_charge_metric_identity id @ suffix) == Some (id, suffix)) =
  identity_fields_decode_encoding_suffix
    (charge_metric_identity_fields id) suffix

let artifact_type_identity_fields (id:artifact_type_identity)
    : identity_fields =
  {fields_name=id.artifact_type_name;
   fields_version=id.artifact_type_version;
   fields_build=id.artifact_type_build}

let enc_artifact_type_identity (id:artifact_type_identity) : bytes =
  enc_identity_fields (artifact_type_identity_fields id)

let dec_artifact_type_identity (input:bytes)
    : option (artifact_type_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({artifact_type_name=f.fields_name;
             artifact_type_version=f.fields_version;
             artifact_type_build=f.fields_build}, rest)

let artifact_type_identity_decode_encoding_suffix
    (id:artifact_type_identity) (suffix:bytes)
    : Lemma (dec_artifact_type_identity
      (enc_artifact_type_identity id @ suffix) == Some (id, suffix)) =
  identity_fields_decode_encoding_suffix
    (artifact_type_identity_fields id) suffix

let artifact_store_identity_fields (id:artifact_store_identity)
    : identity_fields =
  {fields_name=id.artifact_store_name;
   fields_version=id.artifact_store_version;
   fields_build=id.artifact_store_build}

let enc_artifact_store_identity (id:artifact_store_identity) : bytes =
  enc_identity_fields (artifact_store_identity_fields id)

let dec_artifact_store_identity (input:bytes)
    : option (artifact_store_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({artifact_store_name=f.fields_name;
             artifact_store_version=f.fields_version;
             artifact_store_build=f.fields_build}, rest)

let artifact_store_identity_decode_encoding_suffix
    (id:artifact_store_identity) (suffix:bytes)
    : Lemma (dec_artifact_store_identity
      (enc_artifact_store_identity id @ suffix) == Some (id, suffix)) =
  identity_fields_decode_encoding_suffix
    (artifact_store_identity_fields id) suffix

let contract_identity_fields (id:contract_identity) : identity_fields =
  {fields_name=id.contract_name; fields_version=id.contract_version;
   fields_build=id.contract_build}

let enc_contract_identity (id:contract_identity) : bytes =
  enc_identity_fields (contract_identity_fields id)

let dec_contract_identity (input:bytes)
    : option (contract_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({contract_name=f.fields_name; contract_version=f.fields_version;
             contract_build=f.fields_build}, rest)

let contract_identity_decode_encoding_suffix
    (id:contract_identity) (suffix:bytes)
    : Lemma (dec_contract_identity (enc_contract_identity id @ suffix) ==
             Some (id, suffix)) =
  identity_fields_decode_encoding_suffix (contract_identity_fields id) suffix

let resolver_identity_fields (id:resolver_identity) : identity_fields =
  {fields_name=id.resolver_name; fields_version=id.resolver_version;
   fields_build=id.resolver_build}

let enc_resolver_identity (id:resolver_identity) : bytes =
  enc_identity_fields (resolver_identity_fields id)

let dec_resolver_identity (input:bytes)
    : option (resolver_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({resolver_name=f.fields_name; resolver_version=f.fields_version;
             resolver_build=f.fields_build}, rest)

let resolver_identity_decode_encoding_suffix
    (id:resolver_identity) (suffix:bytes)
    : Lemma (dec_resolver_identity (enc_resolver_identity id @ suffix) ==
             Some (id, suffix)) =
  identity_fields_decode_encoding_suffix (resolver_identity_fields id) suffix

let root_entry_identity_fields (id:root_entry_identity) : identity_fields =
  {fields_name=id.root_entry_name; fields_version=id.root_entry_version;
   fields_build=id.root_entry_build}

let enc_root_entry_identity (id:root_entry_identity) : bytes =
  enc_identity_fields (root_entry_identity_fields id)

let dec_root_entry_identity (input:bytes)
    : option (root_entry_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({root_entry_name=f.fields_name;
             root_entry_version=f.fields_version;
             root_entry_build=f.fields_build}, rest)

let root_entry_identity_decode_encoding_suffix
    (id:root_entry_identity) (suffix:bytes)
    : Lemma (dec_root_entry_identity
      (enc_root_entry_identity id @ suffix) == Some (id, suffix)) =
  identity_fields_decode_encoding_suffix (root_entry_identity_fields id) suffix

let journal_codec_identity_fields (id:journal_codec_identity)
    : identity_fields =
  {fields_name=id.journal_codec_name;
   fields_version=id.journal_codec_version;
   fields_build=id.journal_codec_build}

let enc_journal_codec_identity (id:journal_codec_identity) : bytes =
  enc_identity_fields (journal_codec_identity_fields id)

let dec_journal_codec_identity (input:bytes)
    : option (journal_codec_identity & bytes) =
  match dec_identity_fields input with
  | None -> None
  | Some (f, rest) ->
      Some ({journal_codec_name=f.fields_name;
             journal_codec_version=f.fields_version;
             journal_codec_build=f.fields_build}, rest)

let journal_codec_identity_decode_encoding_suffix
    (id:journal_codec_identity) (suffix:bytes)
    : Lemma (dec_journal_codec_identity
      (enc_journal_codec_identity id @ suffix) == Some (id, suffix)) =
  identity_fields_decode_encoding_suffix
    (journal_codec_identity_fields id) suffix

let schema_identity_encode_injective (left right:schema_identity)
    (h:enc_schema_identity left == enc_schema_identity right)
    : Lemma (left == right) =
  schema_identity_decode_encoding_suffix left [];
  schema_identity_decode_encoding_suffix right [];
  ()

let charge_metric_identity_encode_injective
    (left right:charge_metric_identity)
    (h:enc_charge_metric_identity left == enc_charge_metric_identity right)
    : Lemma (left == right) =
  charge_metric_identity_decode_encoding_suffix left [];
  charge_metric_identity_decode_encoding_suffix right [];
  ()

let artifact_type_identity_encode_injective
    (left right:artifact_type_identity)
    (h:enc_artifact_type_identity left == enc_artifact_type_identity right)
    : Lemma (left == right) =
  artifact_type_identity_decode_encoding_suffix left [];
  artifact_type_identity_decode_encoding_suffix right [];
  ()

let artifact_store_identity_encode_injective
    (left right:artifact_store_identity)
    (h:enc_artifact_store_identity left == enc_artifact_store_identity right)
    : Lemma (left == right) =
  artifact_store_identity_decode_encoding_suffix left [];
  artifact_store_identity_decode_encoding_suffix right [];
  ()

let contract_identity_encode_injective (left right:contract_identity)
    (h:enc_contract_identity left == enc_contract_identity right)
    : Lemma (left == right) =
  contract_identity_decode_encoding_suffix left [];
  contract_identity_decode_encoding_suffix right [];
  ()

let resolver_identity_encode_injective (left right:resolver_identity)
    (h:enc_resolver_identity left == enc_resolver_identity right)
    : Lemma (left == right) =
  resolver_identity_decode_encoding_suffix left [];
  resolver_identity_decode_encoding_suffix right [];
  ()

let root_entry_identity_encode_injective
    (left right:root_entry_identity)
    (h:enc_root_entry_identity left == enc_root_entry_identity right)
    : Lemma (left == right) =
  root_entry_identity_decode_encoding_suffix left [];
  root_entry_identity_decode_encoding_suffix right [];
  ()

let journal_codec_identity_encode_injective
    (left right:journal_codec_identity)
    (h:enc_journal_codec_identity left == enc_journal_codec_identity right)
    : Lemma (left == right) =
  journal_codec_identity_decode_encoding_suffix left [];
  journal_codec_identity_decode_encoding_suffix right [];
  ()

let enc_codec_identity (x:codec_identity) : bytes =
  enc_identity_token x.codec_name @ enc_nat x.codec_version @ enc_seq x.codec_build

let enc_codec_identity_def (x:codec_identity)
    : Lemma (enc_codec_identity x ==
      enc_identity_token x.codec_name @
        (enc_nat x.codec_version @ enc_seq x.codec_build)) = ()

let dec_codec_identity (input:bytes) : option (codec_identity & bytes) =
  match dec_identity_token input with
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
  append_assoc_local (enc_identity_token id.codec_name)
    (enc_nat id.codec_version @ enc_seq id.codec_build) suffix;
  append_assoc_local (enc_nat id.codec_version) (enc_seq id.codec_build) suffix;
  enc_codec_identity_def id;
  identity_token_decode_encoding_suffix id.codec_name
    (enc_nat id.codec_version @ enc_seq id.codec_build @ suffix);
  sequence_decode_encoding_suffix id.codec_build suffix

let codec_identity_decode_encoding (id:codec_identity)
    : Lemma (dec_codec_identity (enc_codec_identity id) == Some (id, [])) =
  codec_identity_decode_encoding_suffix id []

let enc_code_identity (x:code_identity) : bytes =
  enc_identity_token x.code_name @ enc_nat x.code_version @ enc_seq x.code_build

let dec_code_identity (input:bytes) : option (code_identity & bytes) =
  match dec_identity_token input with
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
  append_assoc_local (enc_identity_token id.code_name)
    (enc_nat id.code_version @ enc_seq id.code_build) suffix;
  append_assoc_local (enc_nat id.code_version) (enc_seq id.code_build) suffix;
  identity_token_decode_encoding_suffix id.code_name
    (enc_nat id.code_version @ enc_seq id.code_build @ suffix);
  sequence_decode_encoding_suffix id.code_build suffix

let enc_operation_identity (x:operation_identity) : bytes =
  enc_identity_token x.operation_name @ enc_nat x.operation_version @
  enc_seq x.operation_build

let dec_operation_identity (input:bytes)
    : option (operation_identity & bytes) =
  match dec_identity_token input with
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
  append_assoc_local (enc_identity_token id.operation_name)
    (enc_nat id.operation_version @ enc_seq id.operation_build) suffix;
  append_assoc_local (enc_nat id.operation_version)
    (enc_seq id.operation_build) suffix;
  identity_token_decode_encoding_suffix id.operation_name
    (enc_nat id.operation_version @ enc_seq id.operation_build @ suffix);
  sequence_decode_encoding_suffix id.operation_build suffix

let enc_generator_identity (x:generator_identity) : bytes =
  enc_identity_token x.generator_name @ enc_nat x.generator_version @
  enc_seq x.generator_build

let dec_generator_identity (input:bytes)
    : option (generator_identity & bytes) =
  match dec_identity_token input with
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
  append_assoc_local (enc_identity_token id.generator_name)
    (enc_nat id.generator_version @ enc_seq id.generator_build) suffix;
  append_assoc_local (enc_nat id.generator_version)
    (enc_seq id.generator_build) suffix;
  identity_token_decode_encoding_suffix id.generator_name
    (enc_nat id.generator_version @ enc_seq id.generator_build @ suffix);
  sequence_decode_encoding_suffix id.generator_build suffix

let enc_graph_codec_identity (x:graph_codec_identity) : bytes =
  enc_identity_token x.graph_codec_name @ enc_nat x.graph_codec_version @
  enc_seq x.graph_codec_build

let dec_graph_codec_identity (input:bytes)
    : option (graph_codec_identity & bytes) =
  match dec_identity_token input with
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
  append_assoc_local (enc_identity_token id.graph_codec_name)
    (enc_nat id.graph_codec_version @ enc_seq id.graph_codec_build) suffix;
  append_assoc_local (enc_nat id.graph_codec_version)
    (enc_seq id.graph_codec_build) suffix;
  identity_token_decode_encoding_suffix id.graph_codec_name
    (enc_nat id.graph_codec_version @ enc_seq id.graph_codec_build @ suffix);
  sequence_decode_encoding_suffix id.graph_codec_build suffix

// Injectivity is derived from the typed decoder left inverse, not assumed
// from human-readable names or digest equality.
let codec_identity_encode_injective (left right:codec_identity)
    (h:enc_codec_identity left == enc_codec_identity right)
    : Lemma (left == right) =
  codec_identity_decode_encoding left;
  codec_identity_decode_encoding right;
  ()

let code_identity_encode_injective (left right:code_identity)
    (h:enc_code_identity left == enc_code_identity right)
    : Lemma (left == right) =
  code_identity_decode_encoding_suffix left [];
  code_identity_decode_encoding_suffix right [];
  ()

let operation_identity_encode_injective
    (left right:operation_identity)
    (h:enc_operation_identity left == enc_operation_identity right)
    : Lemma (left == right) =
  operation_identity_decode_encoding_suffix left [];
  operation_identity_decode_encoding_suffix right [];
  ()

let generator_identity_encode_injective
    (left right:generator_identity)
    (h:enc_generator_identity left == enc_generator_identity right)
    : Lemma (left == right) =
  generator_identity_decode_encoding_suffix left [];
  generator_identity_decode_encoding_suffix right [];
  ()

let graph_codec_identity_encode_injective
    (left right:graph_codec_identity)
    (h:enc_graph_codec_identity left == enc_graph_codec_identity right)
    : Lemma (left == right) =
  graph_codec_identity_decode_encoding_suffix left [];
  graph_codec_identity_decode_encoding_suffix right [];
  ()

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

let work_identity_encode_injective (left right:work_identity)
    (h:enc_work_identity left == enc_work_identity right)
    : Lemma (left == right) =
  work_identity_decode_encoding_suffix left [];
  work_identity_decode_encoding_suffix right [];
  ()

let output_identity_encode_injective (left right:output_identity)
    (h:enc_output_identity left == enc_output_identity right)
    : Lemma (left == right) =
  output_identity_decode_encoding_suffix left [];
  output_identity_decode_encoding_suffix right [];
  ()

let durable_work_ref_encode_injective
    (left right:durable_work_ref)
    (h:enc_durable_work_ref left == enc_durable_work_ref right)
    : Lemma (left == right) =
  durable_work_ref_decode_encoding_suffix left [];
  durable_work_ref_decode_encoding_suffix right [];
  ()


// Graph and wire syntax {{{1
type node_key = nat

// First-order wire syntax. Constant typing is recovered from the pinned codec
// identity at this graph's exact root input.
type wire (input:Type0) (x:input) =
  | RootWire:wire input x
  | OutputWire:node_key -> wire input x
  | ConstantWire:codec_identity -> bytes -> wire input x
  | PairWire:wire input x -> wire input x -> wire input x
  | FstWire:wire input x -> wire input x
  | SndWire:wire input x -> wire input x

type graph_node (input:Type0) (x:input) = {
  graph_node_key:node_key;
  graph_node_work:durable_work_ref;
  graph_node_input:wire input x
}

// Nodes are stored topologically. The descriptor contains references and wire
// syntax, never executable closures or runtime values.
type graph_desc (input:Type0) (output:input -> Type0) (x:input) = {
  graph_nodes:list (graph_node input x);
  graph_output_wire:wire input x
}

// Restricted first-order schema syntax. In SchemaSigma's second component,
// SchemaBound 0 denotes the nearest binder. Binder scope and denotation are
// checked by WorkflowV2.Schema; this AST contains no F* closures or proofs.
type schema_value_expr =
  | SchemaBound : nat -> schema_value_expr
  | SchemaRoot : schema_value_expr
  | SchemaPort : node_key -> schema_value_expr
  | SchemaConstant : codec_identity -> bytes -> schema_value_expr
  | SchemaUnitValue : schema_value_expr
  | SchemaBoolValue : bool -> schema_value_expr
  | SchemaNatValue : nat -> schema_value_expr
  | SchemaIntValue : int -> schema_value_expr
  | SchemaPairValue : schema_value_expr -> schema_value_expr
      -> schema_value_expr
  | SchemaFstValue : schema_value_expr -> schema_value_expr
  | SchemaSndValue : schema_value_expr -> schema_value_expr
  | SchemaConstructorValue : schema_identity -> list schema_value_expr
      -> schema_value_expr
  | SchemaIndexCallValue : schema_identity -> list schema_value_expr
      -> schema_value_expr

type schema_predicate_expr =
  | SchemaTrue : schema_predicate_expr
  | SchemaFalse : schema_predicate_expr
  | SchemaEqual : schema_value_expr -> schema_value_expr
      -> schema_predicate_expr
  | SchemaAnd : schema_predicate_expr -> schema_predicate_expr
      -> schema_predicate_expr

type schema_type_expr =
  | SchemaAtom : schema_identity -> schema_type_expr
  | SchemaUnit : schema_type_expr
  | SchemaBool : schema_type_expr
  | SchemaNat : schema_type_expr
  | SchemaInt : schema_type_expr
  | SchemaProduct : schema_type_expr -> schema_type_expr
      -> schema_type_expr
  | SchemaSum : schema_type_expr -> schema_type_expr -> schema_type_expr
  | SchemaList : schema_type_expr -> schema_type_expr
  | SchemaOption : schema_type_expr -> schema_type_expr
  | SchemaSigma : schema_type_expr -> schema_type_expr -> schema_type_expr
  | SchemaFamily : schema_identity -> list schema_value_expr
      -> schema_type_expr
  | SchemaRefine : schema_type_expr -> schema_predicate_expr
      -> schema_type_expr

// An artifact reference is a typed, uninterpreted token at this layer. Its
// bytes are not file contents, a path, network state, or a host handle; only
// the manifest-selected artifact package interprets them. PackedArtifactRef
// is candidate syntax: its runtime identity is not intrinsically related to
// its phantom carrier `a`. The artifact-package membership proof must establish
// that exact identity/carrier link before canonical encoding or commit.
noeq type artifact_ref (a:Type0) = {
  artifact_reference_token:bytes
}

noeq type packed_artifact_ref =
  | PackedArtifactRef : #a:Type0 -> artifact_type_identity
      -> artifact_ref a -> packed_artifact_ref

// Codec and executable work contracts {{{1
noeq type codec (a:Type0) = {
  codec_id:codec_identity;
  encode:a -> Tot bytes;
  decode:bytes -> Tot (option a);
  roundtrip:(x:a) -> Lemma (decode (encode x) == Some x);
  canonical:(wire:bytes) -> (x:a)
    -> Lemma (decode wire == Some x ==> wire == encode x)
}

noeq type indexed_codec (i:Type0) (o:i -> Type0) = {
  indexed_codec_id:codec_identity;
  encode_indexed:(x:i) -> o x -> Tot bytes;
  decode_indexed:(x:i) -> bytes -> Tot (option (o x));
  roundtrip_indexed:(x:i) -> (y:o x)
    -> Lemma (decode_indexed x (encode_indexed x y) == Some y);
  canonical_indexed:(x:i) -> (wire:bytes) -> (y:o x)
    -> Lemma
      (decode_indexed x wire == Some y ==> wire == encode_indexed x y)
}

noeq type code_ref (input:Type0) (output:input -> Type0) = {
  code_ref_id:code_identity;
  input_codec:codec input;
  output_codec:indexed_codec input output;
  run:(x:input) -> Tot (output x)
}

noeq type op_ref (input:Type0) (output:input -> Type0) = {
  operation_ref_id:operation_identity;
  request_codec:codec input;
  operation_output_codec:indexed_codec input output;
  validate_reply:(x:input) -> (reply:bytes)
    -> Tot (option (output x));
  charge_metric:charge_metric_identity;
  maximum_charge:nat
}

noeq type graph_codec (input:Type0) (output:input -> Type0) = {
  graph_codec_id:graph_codec_identity;
  encode_graph:(x:input) -> graph_desc input output x -> Tot bytes;
  decode_graph:(x:input) -> bytes
    -> Tot (option (graph_desc input output x));
  graph_roundtrip:(x:input) -> (g:graph_desc input output x) -> Lemma
    (decode_graph x (encode_graph x g) == Some g);
  graph_canonical:(x:input) -> (wire:bytes)
    -> (g:graph_desc input output x)
    -> Lemma (decode_graph x wire == Some g ==> wire == encode_graph x g)
}

// One per-occurrence allocation is the source for both generation fuel and
// reserved charge. Graph size and encoded size are measured from the finite
// descriptor; they are not duplicated as API bounds.
type generation_allocation = {
  expansion_fuel:nat;
  charge_allocation:nat
}

// A generated descriptor carries one allocation per graph-local key. The
// occurrence path is not known until commit, so lifting into the journal's
// occurrence-keyed plan happens at that boundary.
type node_allocation = {
  allocated_key:node_key;
  allocated_values:generation_allocation
}

type graph_allocation_plan = list node_allocation

noeq type generated_graph (input:Type0) (output:input -> Type0)
    (x:input) (parent:generation_allocation) = {
  generated_descriptor:graph_desc input output x;
  generated_child_plan:graph_allocation_plan
}

type run_budget = {
  charge_metric:charge_metric_identity;
  total_expansion_fuel:nat;
  total_charge:nat
}

noeq type generator_ref (input:Type0)
    (output:input -> Type0) = {
  generator_ref_id:generator_identity;
  generator_input_codec:codec input;
  generator_output_codec:graph_codec input output;
  generate_graph:(x:input) -> (metric:charge_metric_identity)
    -> (allocation:generation_allocation)
    -> Tot (generated_graph input output x allocation)
}

noeq type work : input:Type0 -> (input -> Type0) -> Type =
  | LocalWork : #input:Type0 -> #output:(input -> Type0)
      -> code_ref input output
      -> work input output
  | ExternalWork : #input:Type0 -> #output:(input -> Type0)
      -> op_ref input output
      -> work input output
  | GenerateWork : #input:Type0 -> #output:(input -> Type0)
      -> generator_ref input output
      -> work input output

