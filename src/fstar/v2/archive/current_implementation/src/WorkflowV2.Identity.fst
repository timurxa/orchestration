module WorkflowV2.Identity
open FStar.List.Tot
open WorkflowV2.Kernel

// Identity comparison and durable work references {{{1
let codec_identity_eq (left right:codec_identity) : bool =
  left.codec_name = right.codec_name &&
  left.codec_version = right.codec_version &&
  left.codec_build = right.codec_build

let codec_identity_eq_sound (left right:codec_identity)
  : Lemma (codec_identity_eq left right == true ==> left == right) = ()

let graph_codec_identity_eq (left right:graph_codec_identity) : bool =
  left.graph_codec_name = right.graph_codec_name &&
  left.graph_codec_version = right.graph_codec_version &&
  left.graph_codec_build = right.graph_codec_build

let code_identity_eq (left right:code_identity) : bool =
  left.code_name = right.code_name &&
  left.code_version = right.code_version &&
  left.code_build = right.code_build

let operation_identity_eq (left right:operation_identity) : bool =
  left.operation_name = right.operation_name &&
  left.operation_version = right.operation_version &&
  left.operation_build = right.operation_build

let generator_identity_eq (left right:generator_identity) : bool =
  left.generator_name = right.generator_name &&
  left.generator_version = right.generator_version &&
  left.generator_build = right.generator_build

let work_identity_eq (left right:work_identity) : bool =
  match left, right with
  | CodeWorkIdentity l, CodeWorkIdentity r -> code_identity_eq l r
  | OperationWorkIdentity l, OperationWorkIdentity r ->
      operation_identity_eq l r
  | GeneratorWorkIdentity l, GeneratorWorkIdentity r ->
      generator_identity_eq l r
  | _, _ -> false

let output_identity_eq (left right:output_identity) : bool =
  match left, right with
  | ValueOutputIdentity l, ValueOutputIdentity r -> codec_identity_eq l r
  | GeneratedGraphCodecIdentity l, GeneratedGraphCodecIdentity r ->
      graph_codec_identity_eq l r
  | _, _ -> false

let durable_ref_of_work (#i:Type0) (#o:i -> Type0)
    (w:work i o) : durable_work_ref =
  match w with
  | LocalWork r -> {
      durable_kind = CodeWorkIdentity r.code_ref_id;
      durable_input_codec = r.input_codec.codec_id;
      durable_output = ValueOutputIdentity r.output_codec.indexed_codec_id
    }
  | ExternalWork r -> {
      durable_kind = OperationWorkIdentity r.operation_ref_id;
      durable_input_codec = r.request_codec.codec_id;
      durable_output = ValueOutputIdentity
        r.operation_output_codec.indexed_codec_id
    }
  | GenerateWork r -> {
      durable_kind = GeneratorWorkIdentity r.generator_ref_id;
      durable_input_codec = r.generator_input_codec.codec_id;
      durable_output = GeneratedGraphCodecIdentity
        r.generator_output_codec.graph_codec_id
    }

let durable_work_ref_eq (left right:durable_work_ref) : bool =
  work_identity_eq left.durable_kind right.durable_kind &&
  codec_identity_eq left.durable_input_codec right.durable_input_codec &&
  output_identity_eq left.durable_output right.durable_output

let durable_work_ref_eq_sound (left right:durable_work_ref)
  : Lemma (durable_work_ref_eq left right == true ==> left == right) = ()

// Work graphs are heterogeneous: every node may have different input and
// dependent output types. One pinned global registry existentially packages
// typed entries while lookup keys remain first-order durable references. This
// is the resolver needed after decoding, not a per-work wrapper or second
// source of a node's executable identity.
noeq type packed_work : Type =
  | PackedWork: #i:Type0 -> #o:(i -> Type0)
      -> work i o -> packed_work

let packed_work_ref (package:packed_work) : durable_work_ref =
  match package with
  | PackedWork w -> durable_ref_of_work w

let rec durable_ref_occurrences (key:durable_work_ref)
    (entries:list packed_work) : nat =
  match entries with
  | [] -> 0
  | entry::tail ->
      (if durable_work_ref_eq key (packed_work_ref entry) then 1 else 0) +
      durable_ref_occurrences key tail

noeq type global_work_registry = {
  global_work_entries:list packed_work;
  global_registry_unique:(key:durable_work_ref) ->
    Lemma (durable_ref_occurrences key global_work_entries <= 1)
}

// This witness keeps the exact selected package attached to a lookup result;
// identity equality alone cannot relate two noeq existential packages.
noeq type packed_work_membership : target:packed_work
    -> entries:list packed_work -> Type =
  | PackedWorkMemberHead:#target:packed_work -> #tail:list packed_work
      -> packed_work_membership target (target::tail)
  | PackedWorkMemberTail:#target:packed_work -> #head:packed_work
      -> #tail:list packed_work
      -> packed_work_membership target tail
      -> packed_work_membership target (head::tail)

let rec resolve_packed_work_member (key:durable_work_ref)
    (entries:list packed_work)
  : Tot (option (package:packed_work{
      durable_work_ref_eq key (packed_work_ref package) == true} &
      packed_work_membership package entries)) (decreases entries) =
  match entries with
  | [] -> None
  | head::tail ->
      if durable_work_ref_eq key (packed_work_ref head) then
        Some (Mkdtuple2 head (PackedWorkMemberHead #head #tail))
      else
        match resolve_packed_work_member key tail with
        | None -> None
        | Some (Mkdtuple2 package member) ->
            Some (Mkdtuple2 package
              (PackedWorkMemberTail #package #head #tail member))

let resolve_global_work_member (registry:global_work_registry)
    (key:durable_work_ref)
  : option (package:packed_work{
      durable_work_ref_eq key (packed_work_ref package) == true} &
      packed_work_membership package registry.global_work_entries) =
  resolve_packed_work_member key registry.global_work_entries

let rec resolve_packed_work_member_key_exact (key:durable_work_ref)
    (entries:list packed_work)
  : Lemma (match resolve_packed_work_member key entries with
      | None -> True
      | Some (Mkdtuple2 package _) -> key == packed_work_ref package) =
  match entries with
  | [] -> ()
  | head::tail ->
      if durable_work_ref_eq key (packed_work_ref head)
      then durable_work_ref_eq_sound key (packed_work_ref head)
      else resolve_packed_work_member_key_exact key tail

let global_work_member_exact (registry:global_work_registry)
    (key:durable_work_ref)
  : Lemma (match resolve_global_work_member registry key with
      | None -> True
      | Some (Mkdtuple2 package _) ->
          durable_ref_occurrences key registry.global_work_entries <= 1 /\
          key == packed_work_ref package) =
  match resolve_global_work_member registry key with
  | None -> ()
  | Some _ ->
      registry.global_registry_unique key;
      resolve_packed_work_member_key_exact key registry.global_work_entries

let resolve_global_work (registry:global_work_registry)
    (key:durable_work_ref) : option packed_work =
  match resolve_global_work_member registry key with
  | None -> None
  | Some (Mkdtuple2 package _) -> Some package

// Global work registry and exact resolution {{{1
// global_identity_resolution_exact: resolved keys identify one exact package {{{2
let global_identity_resolution_exact (registry:global_work_registry)
    (key:durable_work_ref)
  : Lemma
      (match resolve_global_work_member registry key with
       | None -> True
       | Some (Mkdtuple2 package _) ->
           durable_ref_occurrences key registry.global_work_entries <= 1 /\
           key == packed_work_ref package) =
  global_work_member_exact registry key

// Global codec registry and exact resolution {{{1
noeq type packed_codec : Type =
  | PlainCodec: #a:Type0 -> codec a -> packed_codec
  | IndexedCodec: #i:Type0 -> #o:(i -> Type0)
      -> indexed_codec i o -> packed_codec

let packed_codec_identity (package:packed_codec) : codec_identity =
  match package with
  | PlainCodec c -> c.codec_id
  | IndexedCodec c -> c.indexed_codec_id

let rec codec_identity_occurrences (key:codec_identity)
    (entries:list packed_codec) : nat =
  match entries with
  | [] -> 0
  | entry::tail ->
      (if codec_identity_eq key (packed_codec_identity entry) then 1 else 0) +
      codec_identity_occurrences key tail

noeq type global_codec_registry = {
  global_codec_entries:list packed_codec;
  global_codec_unique:(key:codec_identity) ->
    Lemma (codec_identity_occurrences key global_codec_entries <= 1)
}

noeq type packed_codec_membership : target:packed_codec
    -> entries:list packed_codec -> Type =
  | PackedCodecMemberHead:#target:packed_codec -> #tail:list packed_codec
      -> packed_codec_membership target (target::tail)
  | PackedCodecMemberTail:#target:packed_codec -> #head:packed_codec
      -> #tail:list packed_codec
      -> packed_codec_membership target tail
      -> packed_codec_membership target (head::tail)

let rec resolve_packed_codec_member (key:codec_identity)
    (entries:list packed_codec)
  : Tot (option (package:packed_codec{
      codec_identity_eq key (packed_codec_identity package) == true} &
      packed_codec_membership package entries)) (decreases entries) =
  match entries with
  | [] -> None
  | head::tail ->
      if codec_identity_eq key (packed_codec_identity head) then
        Some (Mkdtuple2 head (PackedCodecMemberHead #head #tail))
      else
        match resolve_packed_codec_member key tail with
        | None -> None
        | Some (Mkdtuple2 package member) ->
            Some (Mkdtuple2 package
              (PackedCodecMemberTail #package #head #tail member))

let resolve_global_codec_member (registry:global_codec_registry)
    (key:codec_identity)
  : option (package:packed_codec{
      codec_identity_eq key (packed_codec_identity package) == true} &
      packed_codec_membership package registry.global_codec_entries) =
  resolve_packed_codec_member key registry.global_codec_entries

let rec resolve_packed_codec_member_key_exact (key:codec_identity)
    (entries:list packed_codec)
  : Lemma (match resolve_packed_codec_member key entries with
      | None -> True
      | Some (Mkdtuple2 package _) -> key == packed_codec_identity package) =
  match entries with
  | [] -> ()
  | head::tail ->
      if codec_identity_eq key (packed_codec_identity head)
      then codec_identity_eq_sound key (packed_codec_identity head)
      else resolve_packed_codec_member_key_exact key tail

let global_codec_member_exact (registry:global_codec_registry)
    (key:codec_identity)
  : Lemma (match resolve_global_codec_member registry key with
      | None -> True
      | Some (Mkdtuple2 package _) ->
          codec_identity_occurrences key registry.global_codec_entries <= 1 /\
          key == packed_codec_identity package) =
  match resolve_global_codec_member registry key with
  | None -> ()
  | Some _ ->
      registry.global_codec_unique key;
      resolve_packed_codec_member_key_exact key registry.global_codec_entries

let resolve_global_codec (registry:global_codec_registry)
    (key:codec_identity) : option packed_codec =
  match resolve_global_codec_member registry key with
  | None -> None
  | Some (Mkdtuple2 package _) -> Some package

// global_codec_resolution_exact: resolved keys identify one exact codec {{{2
let global_codec_resolution_exact (registry:global_codec_registry)
    (key:codec_identity)
  : Lemma
      (match resolve_global_codec_member registry key with
       | None -> True
       | Some (Mkdtuple2 package _) ->
           codec_identity_occurrences key registry.global_codec_entries <= 1 /\
           key == packed_codec_identity package) =
  global_codec_member_exact registry key

// Pinned registry snapshot and work codec access {{{1
// RunStarted names one registry bundle. This declaration does not yet prove
// that bundle_identity is derived from or bound to the registry contents;
// P0 must add that manifest relation and the host reload refinement.
noeq type pinned_registry_bundle = {
  bundle_identity:registry_identity;
  bundle_work_registry:global_work_registry;
  bundle_codec_registry:global_codec_registry
}

let work_input_encode (#i:Type0) (#o:i -> Type0)
    (w:work i o) (x:i) : bytes =
  match w with
  | LocalWork r -> r.input_codec.encode x
  | ExternalWork r -> r.request_codec.encode x
  | GenerateWork r -> r.generator_input_codec.encode x

let work_input_decode (#i:Type0) (#o:i -> Type0)
    (w:work i o) (wire:bytes) : option i =
  match w with
  | LocalWork r -> r.input_codec.decode wire
  | ExternalWork r -> r.request_codec.decode wire
  | GenerateWork r -> r.generator_input_codec.decode wire

// These are derived by selecting the codec stored in the exact work value.
// Later journal replay first resolves a durable reference to this value, then
// uses these functions at the reconstructed input index.
let work_input_decode_canonical (#i:Type0) (#o:i -> Type0)
    (w:work i o) (wire:bytes) (x:i)
  : Lemma (work_input_decode w wire == Some x ==>
           wire == work_input_encode w x) =
  match w with
  | LocalWork r -> r.input_codec.canonical wire x
  | ExternalWork r -> r.request_codec.canonical wire x
  | GenerateWork r -> r.generator_input_codec.canonical wire x

// `GenerateWork` completes through its committed child graph, not a
// `NodeCompleted` value. Its GraphCodec encodes the descriptor; ordinary
// completion codecs apply only to LocalWork and ExternalWork.

