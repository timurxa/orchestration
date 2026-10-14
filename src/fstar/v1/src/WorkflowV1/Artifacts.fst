module WorkflowV1.Artifacts
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Protocol

type artifact_policy = {
  permitted_artifact_schemas:list artifact_schema;
  maximum_artifact_bytes:nat;
  maximum_artifact_count:nat;
  maximum_artifact_bundle_bytes:nat
}

type artifact_candidate = {
  candidate_ref:artifact_ref;
  candidate_bytes:bytes
}

let rec artifact_schema_allowed (schema:artifact_schema)
    (allowed:list artifact_schema) : bool =
  match allowed with
  | [] -> false
  | entry::rest -> entry = schema || artifact_schema_allowed schema rest

let artifact_candidate_valid (hash_bytes:bytes -> Tot digest)
    (check_schema:code_id -> nat -> bytes -> Tot bool)
    (policy:artifact_policy) (call:call_id)
    (expected_parents:list digest) (candidate:artifact_candidate) : bool =
  let reference = candidate.candidate_ref in
  reference.artifact_digest = hash_bytes candidate.candidate_bytes &&
  reference.artifact_size = length candidate.candidate_bytes &&
  reference.artifact_size <= policy.maximum_artifact_bytes &&
  artifact_schema_allowed
    (reference.artifact_schema, reference.artifact_schema_version)
    policy.permitted_artifact_schemas &&
  check_schema reference.artifact_schema reference.artifact_schema_version
    candidate.candidate_bytes &&
  reference.artifact_source_call = Some call &&
  occurrence_eq reference.artifact_source call.call_key.key_occurrence &&
  reference.artifact_parents = expected_parents

// A journal stores artifact descriptors only. Bytes are staged in the
// artifact store and checked before the descriptor is admitted.
let artifact_descriptor_valid (policy:artifact_policy) (call:call_id)
    (expected_parents:list digest) (reference:artifact_ref) : bool =
  reference.artifact_size <= policy.maximum_artifact_bytes &&
  artifact_schema_allowed
    (reference.artifact_schema, reference.artifact_schema_version)
    policy.permitted_artifact_schemas &&
  reference.artifact_source_call = Some call &&
  occurrence_eq reference.artifact_source call.call_key.key_occurrence &&
  reference.artifact_parents = expected_parents

let rec artifact_descriptors_valid (policy:artifact_policy) (call:call_id)
    (expected_parents:list digest) (references:list artifact_ref) : bool =
  length references <= policy.maximum_artifact_count &&
  (match references with
   | [] -> true
   | reference::rest ->
       artifact_descriptor_valid policy call expected_parents reference &&
       artifact_descriptors_valid policy call expected_parents rest)

let rec artifact_descriptors_size (references:list artifact_ref) : nat =
  match references with
  | [] -> 0
  | reference::rest -> reference.artifact_size +
      artifact_descriptors_size rest

let rec artifact_ref_member (reference:artifact_ref)
    (references:list artifact_ref) : bool =
  match references with
  | [] -> false
  | candidate::rest -> candidate = reference ||
      artifact_ref_member reference rest

type staged_artifact_matches (hash_bytes:bytes -> Tot digest)
    (check_schema:code_id -> nat -> bytes -> Tot bool)
    (reference:artifact_ref) =
  exists wire. length wire == reference.artifact_size /\
    hash_bytes wire == reference.artifact_digest /\
    check_schema reference.artifact_schema
      reference.artifact_schema_version wire == true

let rec artifact_bundle_size (objects:list artifact_candidate) : nat =
  match objects with
  | [] -> 0
  | object::rest -> length object.candidate_bytes + artifact_bundle_size rest

let rec artifact_bundle_candidates_valid (hash_bytes:bytes -> Tot digest)
    (check_schema:code_id -> nat -> bytes -> Tot bool)
    (policy:artifact_policy) (call:call_id)
    (expected_parents:list digest)
    (objects:list artifact_candidate) : bool =
  match objects with
  | [] -> true
  | object::rest ->
      artifact_candidate_valid hash_bytes check_schema policy call
        expected_parents object &&
      artifact_bundle_candidates_valid hash_bytes check_schema policy call
        expected_parents rest

let artifact_bundle_valid (hash_bytes:bytes -> Tot digest)
    (check_schema:code_id -> nat -> bytes -> Tot bool)
    (policy:artifact_policy) (call:call_id) (expected_parents:list digest)
    (objects:list artifact_candidate) : bool =
  length objects <= policy.maximum_artifact_count &&
  artifact_bundle_size objects <= policy.maximum_artifact_bundle_bytes &&
  artifact_bundle_candidates_valid hash_bytes check_schema policy call
    expected_parents objects

// Resource types are application data interpreted by adapters. The kernel
// contains no Blob, path, socket, process, cursor, or native-handle value.
