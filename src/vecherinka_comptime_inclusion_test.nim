## Issue report: artifact_tree coverage
##
## Environment
## - Nim 2.3.1, macOS arm64.
## - Source under test: vecherinka_comptime.nim.
## - Probes used semantic `typedesc` macro inputs, then compiled generated
##   materializers. Bare parseExpr AST is not valid evidence for this code.
## - This file textually includes vecherinka. It checks a second source copy,
##   not import/export API behavior; included private symbols share namespace.
##
## Executive verdict
##
## Original suspicion is false for artifact_tree itself. Object variants work.
## artifact_tree identifies them as ank_variant, preserves common fields, emits
## one branch per tag, accepts `else`, accepts multi-label branches, and accepts
## empty `discard` branches. Generated materializer code compiled and executed
## for tagged and else branches.
##
## Historical probes found integration limits after artifact_tree. Current
## executable suite separates those from walker behavior; simple variants now
## round-trip, while Schematic `else`/nested-variant limits remain distinct.
##
## Positive proof
##
## Probe types:
##
##   type
##     Kind = enum ka, kb
##     Variant = object
##       common: string
##       case kind: Kind
##       of ka: value: int
##       of kb: path: Location
##     VariantElse = object
##       case kind: Kind
##       of ka: value: int
##       else: text: string
##     VariantMulti = object
##       case kind: Kind
##       of ka, kb: value: int
##
## Compile-time output:
##
##   artifact_tree Variant: ank_variant fields=1 branches=2
##   artifact_tree VariantElse: ank_variant fields=0 branches=2
##   artifact_tree VariantMulti: ank_variant fields=0 branches=2
##
## Generated materializer output:
##
##   input.common: string = c
##   input.value: int = 7
##   input.text: string = fallback
##
## Source proof: artifact_variant_tree handles nnkOfBranch and nnkElse at
## lines 682-718. ank_variant walker emits common fields and a runtime case at
## lines 830-859. Main dispatch detects nnkRecCase at lines 757-760.
##
## Baseline failures, now regression targets
##
## These failed before contract fixes. Current suite proves required supported
## forms, while compile-fail probes prove required forbidden forms.
##
##   RefPlain    = ref Plain
##   Fixed       = array[2, int]
##   Pointer     = ptr int
##   CharSet     = set[char]
##   SmallRange  = range[0..3]
##   Callback    = proc(value: int): int
##   Natural     = Natural
##   Positive    = Positive
##
## Original dispatch reached final error for these shapes. Fixed arrays,
## constrained ranges, ordinal bounds, and transparent distinct wrappers now
## have explicit regression coverage.
##
## Baseline composite defects, now regression targets
##
## 1. Named tuple aliases recurse.
##
##   type NamedTuple = tuple[a: int, b: string]
##
## Result before fix: repeated artifact_tree/artifact_fields calls, then:
## `maximum call depth for the VM exceeded`. Current named-tuple tests pass.
##
## Positional tuple alias `(int, string)` passed. Failure is named tuple AST
## handling: nnkTupleTy fields are nnkIdentDefs, but artifact_fields only treats
## nnkExprColonExpr as named tuple fields. It otherwise feeds the IdentDefs back
## into artifact_tree at lines 649-660.
##
## 2. Distinct object/variant values record casts but do not apply them.
##
##   type DistinctPlain = distinct Plain
##   type DistinctVariant = distinct Variant
##
## Generated materializer compilation errors before fix:
##
##   undeclared field: 'value' for type DistinctPlain
##   undeclared field: 'kind' for type DistinctVariant
##
## artifact_tree sets needs_runtime_cast at lines 699-700 and 762-763.
## artifact_runtime_value exists at lines 802-805, but object/tuple/variant
## descent uses raw value at lines 821-858. Only seq and Option descent applies
## artifact_runtime_value at lines 860-877. Distinct seq passed; distinct tuple
## recursed until VM call-depth failure.
##
## 3. Option alias loses wrapper recognition.
##
## Direct `Option[int]` passed. `type Alias = Option[int]` previously failed:
## `artifact walker only supports plain fields`; alias tests now pass.
##
## Cause: direct bracket AST is recognized at lines 729-739. Alias resolves to
## Option's object representation on Nim 2.3.1, then object-field walking runs
## instead of Option handling. Same pattern can affect generic aliases whose
## type identity is no longer a bracket expression.
##
## Remaining end-to-end variant limits outside artifact_tree
##
## model_output_contract correctly routes ank_variant to discriminated at
## lines 1011-1020. Current Schematic dependency then adds separate limits:
##
## - Top-level variant with `else`: exact compile error
##   `discriminated(T): \`else\` branches are not supported`.
## - Nested variant field: Schematic calls structural nodeOf and exact error is
##   `cannot derive a structural schema for a variant object; use discriminated`.
## - Simple top-level variant now round-trips in this suite after Schematic's
##   extraction fix; `else` and nested structural variants remain unsupported.
##
## These limits do not disprove artifact_tree. They are Schematic integration
## concerns and must not be mislabeled walker failures.
##
## Formalized artifact-type contract
##
## These rules are user requirements. Inclusion tests must exercise comptime
## parsing plus generated materialization and Location-verification code.
##
## Allowed:
##
## - Scalars, enums, plain objects, tuples, seq, Option, object variants.
## - Fixed arrays. Treat as seq for paths and element traversal, but preserve
##   fixed length in generated validation/schema behavior.
## - Constrained types when Schematic can serialize and extract them without
##   losing their constraint. Range/Natural/Positive are not blanket rejects.
## - Distinct types. Transparent wrapper: recurse through base representation,
##   cast generated field access when Nim requires it.
## - Location as custom artifact leaf. Preserve existing copy and verification
##   semantics; Location is exception to generic Schematic-only policy.
## - Explicit fixed-array handling is second custom exception: general
##   Schematic rejection does not override the fixed-array requirement below.
##
## Rejected:
##
## - ref objects, including recursive/cyclic object graphs.
## - pointers and proc values.
## - sets. Diagnostic must recommend `seq`.
## - JsonNode, Table, char, cstring. Diagnostic must recommend Location or seq.
## - Anything Schematic cannot schema, serialize, extract, and round-trip,
##   except custom Location and explicitly custom fixed-array handling.
## - void as any FlowSpec return type. FlowSpec output must never be void.
##
## Rejection must happen during comptime type parsing, before generated runtime
## code exists. Diagnostics must name offending type and recommendation.
##
## Test obligations: successful cases
##
## For every allowed shape, test all three layers:
##
## 1. artifact_tree classification and child/branch metadata at comptime.
## 2. Generated materializer and verifier compile successfully.
## 3. Generated code executes with expected instructions, paths, copied
##    Location payloads, active variant branch, Option some/none, sequence
##    indices, fixed-array length, and constrained-value round trip.
##
## Required positive matrix:
##
## - Plain scalar, enum, object, positional and named tuple.
## - Direct and aliased seq/Option; nested seq/Option combinations.
## - Variant common fields, multi-label branch, else branch, empty branch.
## - Variant nested in object, seq, Option, tuple, and fixed array.
## - Location at root, common field, active variant branch, seq element, and
##   present Option.
## - Distinct scalar, object, tuple, variant, seq, Option, and Location.
## - Constrained integer/float types accepted by Schematic.
## - Fixed arrays at length zero, one, and full declared length; wrong length
##   rejected by generated validation.
##
## Test obligations: rejection cases
##
## Compile-fail probes must assert exact diagnostic class and recommendation:
##
## - ref object and recursive/cyclic shape: artifact types forbid refs.
## - pointer/proc: unsupported artifact leaf.
## - set: use seq.
## - JsonNode/Table/char/cstring: use Location or seq.
## - Schematic-rejected types: reject at comptime with Schematic reason.
## - void codomain FlowSpec endpoints: reject across every construction path.
##   void domain remains allowed for no-input flows such as pure/model calls.
##
## User decisions still required before exact tests can be frozen
##
## - Fixed-array schema encoding: exact-length JSON array presumed. Confirm
##   whether JSON Schema minItems/maxItems are required, especially for arrays
##   with nonzero Nim lower bounds. “Treated like seq” implies human paths
##   remain one-based; confirm if native lower-bound indices should appear.
## - Schematic gate: acceptance means schema construction only, or full
##   toJsonSchema, valid tryParse, invalid tryParse, toJson, parse-after-toJson
##   round-trip. Current contract wording assumes full round-trip.
## - Custom Schematic schemas: only automatic schemaOf/discriminated accepted,
##   or user-supplied custom Schema also valid? Default formalization assumes
##   automatic Schematic support, plus Location/fixed-array custom exceptions.
## - Diagnostic wording: exact stable strings, or required recommendation
##   substrings only. Required guidance currently: sets say “use seq”; JSON
##   nodes/tables/chars/cstrings say “use Location or seq”.
## - Cycle error precedence: immediate ref rejection is presumed. Confirm
##   whether recursive/cyclic probes should report “ref forbidden” or a distinct
##   cycle diagnostic. Both must avoid VM recursion failure.
##
## Obvious implementation defects; no product decision needed
##
## Resolved by current implementation/tests: named tuple AST recursion,
## distinct composite casts, Option aliases, fixed arrays, constrained scalar
## leaves, forbidden-shape diagnostics, simple variant extraction, and void
## codomain acceptance. Void domains remain allowed for no-input operations.
##
## Keep direct artifact_tree tests separate from full vecherinka/Schematic tests.
## A passing walker test must not mask schema rejection; a Schematic rejection
## must not be reported as artifact_tree failure.

{.experimental: "callOperator".}

import std/[os, osproc, strutils, unittest, json, options, paths]

include vecherinka

type
  TestKind = enum
    tkText, tkFile
  TestLeaf = object
    text: string
    count: int
  TestVariant = object
    common: string
    case kind: TestKind
    of tkText:
      text: string
    of tkFile:
      file: Location
  TestVariantElse = object
    case kind: TestKind
    of tkText:
      text: string
    else:
      fallback: string
  TestOutput = object
    text: string
    count: int
  TestLocatedOutput = object
    note: string
    artifact: Location
  TestConstrainedOutput = object
    note: string
    count: SmallCount
  TestTwoLocatedOutput = object
    first: Location
    second: Location
  NamedTuple = tuple[a: int, b: string]
  PositionalTuple = (int, string)
  Fixed = array[3, int]
  FixedLower = array[-1 .. 1, int]
  FixedLocation = array[2, Location]
  EmptyFixed = array[0, int]
  BoolFixed = array[bool, int]
  EnumFixed = array[TestKind, int]
  NestedFixed = array[2, array[2, int]]
  AliasFixed = Fixed
  AliasSeq = seq[TestLeaf]
  ObjectWithFixed = object
    values: Fixed
  OptionOutput = Option[TestLeaf]
  DistinctOutput = distinct TestLeaf
  SmallCount = range[0 .. 5]
  DistinctInt = distinct int
  DistinctLeaf = distinct TestLeaf
  DistinctTuple = distinct NamedTuple
  DistinctVariant = distinct TestVariant
  DistinctLocation = distinct Location
  AliasOption = Option[TestLeaf]
  MultiField = object
    left, right: int
  NestedContainer = object
    items: seq[Option[TestVariant]]
  VariantMulti = object
    case kind: TestKind
    of tkText, tkFile:
      text: string
  VariantEmpty = object
    case kind: TestKind
    of tkText:
      discard
    else:
      fallback: string
  TwoLocations = object
    first: Location
    second: Location

proc artifact_kind_value(type_node: NimNode): ArtifactNodeKind =
  artifact_tree(type_node).kind

macro artifact_kind(type_node: typedesc): untyped =
  newLit(artifact_kind_value(type_node))

macro artifact_child_kind(type_node: typedesc): untyped =
  let node = artifact_tree(type_node)
  doAssert not node.element.isNil
  newLit(node.element.kind)

macro artifact_field_count(type_node: typedesc): untyped =
  newLit(artifact_tree(type_node).fields.len)

macro artifact_branch_count(type_node: typedesc): untyped =
  newLit(artifact_tree(type_node).branches.len)

macro artifact_branch_field_count(type_node: typedesc;
    branch_index: static[int]): untyped =
  newLit(artifact_tree(type_node).branches[branch_index].fields.len)

macro input_materializer(type_node: typedesc): untyped =
  emit_input_materializer(type_node)

macro output_contract(type_node: typedesc): untyped =
  model_output_contract(type_node)

macro declare_model_materializer(type_node: typedesc; name: untyped): untyped =
  var registry: ArtifactRegistry
  let artifact_type = make_vecherinka_artifact_type(@[type_node], registry)
  let inner_name = genSym(nskLet, "test_inner_materializer")
  let output = genSym(nskParam, "test_output")
  let decoded = genSym(nskLet, "test_decoded")
  let unpacked = registry.emit_artifact_unpack(
    type_node, newDotExpr(decoded, ident("value")))
  let materializer = registry.emit_model_materializer(type_node, newLit(0))
  result = newStmtList(
    artifact_type,
      quote do:
      let `inner_name` = `materializer`
      proc `name`(kind: int; `output`: LlmOutput):
          ModelMaterialization[`type_node`] =
        let `decoded` = `inner_name`(kind, `output`)
        if not `decoded`.ok:
          return ModelMaterialization[`type_node`](
            ok: false, error: `decoded`.error)
        ModelMaterialization[`type_node`](
          ok: true, value: `unpacked`))

static:
  doAssert artifact_kind(string) == ank_inline
  doAssert artifact_kind(TestKind) == ank_inline
  doAssert artifact_kind(Location) == ank_location
  doAssert artifact_kind(TestLeaf) == ank_object
  doAssert artifact_kind(TestVariant) == ank_variant
  doAssert artifact_field_count(TestVariant) == 1
  doAssert artifact_kind((int, string)) == ank_tuple
  doAssert artifact_kind(seq[TestLeaf]) == ank_seq
  doAssert artifact_kind(AliasSeq) == ank_seq
  doAssert artifact_child_kind(seq[TestLeaf]) == ank_object
  doAssert artifact_kind(Option[TestLeaf]) == ank_option
  doAssert artifact_child_kind(Option[TestLeaf]) == ank_object
  doAssert artifact_kind(AliasOption) == ank_option
  doAssert artifact_kind(NamedTuple) == ank_tuple
  doAssert artifact_kind(Fixed) == ank_seq
  doAssert artifact_kind(FixedLower) == ank_seq
  doAssert artifact_kind(FixedLocation) == ank_seq
  doAssert artifact_kind(EmptyFixed) == ank_seq
  doAssert artifact_kind(BoolFixed) == ank_seq
  doAssert artifact_kind(EnumFixed) == ank_seq
  doAssert artifact_kind(NestedFixed) == ank_seq
  doAssert artifact_child_kind(NestedFixed) == ank_seq
  doAssert artifact_kind(AliasFixed) == ank_seq
  doAssert artifact_kind(SmallCount) == ank_inline
  doAssert artifact_kind(Natural) == ank_inline
  doAssert artifact_kind(Positive) == ank_inline
  doAssert artifact_kind(DistinctInt) == ank_inline
  doAssert artifact_kind(DistinctLeaf) == ank_object
  doAssert artifact_kind(DistinctTuple) == ank_tuple
  doAssert artifact_kind(DistinctVariant) == ank_variant
  doAssert artifact_kind(DistinctLocation) == ank_location
  doAssert artifact_kind(VariantMulti) == ank_variant
  # Walker expands each label into one case branch; both labels retain fields.
  doAssert artifact_branch_count(VariantMulti) == 2
  doAssert artifact_kind(VariantEmpty) == ank_variant
  doAssert artifact_branch_count(VariantEmpty) == 2
  doAssert artifact_branch_field_count(VariantEmpty, 0) == 0
  doAssert artifact_kind(NestedContainer) == ank_object
  doAssert artifact_field_count(ObjectWithFixed) == 1

declare_model_materializer(TestOutput, test_output_materializer)
declare_model_materializer(TestLocatedOutput, test_located_output_materializer)
declare_model_materializer(TestConstrainedOutput, test_constrained_output_materializer)
declare_model_materializer(TestVariant, test_variant_output_materializer)
declare_model_materializer(Fixed, test_fixed_output_materializer)
declare_model_materializer(FixedLower, test_fixed_lower_output_materializer)
declare_model_materializer(FixedLocation, test_fixed_location_output_materializer)
declare_model_materializer(EmptyFixed, test_empty_fixed_output_materializer)
declare_model_materializer(NamedTuple, test_named_tuple_output_materializer)
declare_model_materializer(OptionOutput, test_option_output_materializer)
declare_model_materializer(DistinctOutput, test_distinct_output_materializer)
declare_model_materializer(TestTwoLocatedOutput, test_two_located_output_materializer)

suite "artifact_tree generated input walkers":
  test "nested object, sequence, option, variant, Location":
    let root = getTempDir() / "vecherinka-artifact-tree-input-test"
    let runtime_dir = root / "runtime"
    let artifact_dir = root / "artifact"
    if fileExists(runtime_dir / "payload.txt"):
      removeFile(runtime_dir / "payload.txt")
    if fileExists(artifact_dir / "payload.txt"):
      removeFile(artifact_dir / "payload.txt")
    if fileExists(artifact_dir / "payload-1.txt"):
      removeFile(artifact_dir / "payload-1.txt")
    if dirExists(runtime_dir): removeDir(runtime_dir)
    if dirExists(artifact_dir): removeDir(artifact_dir)
    if dirExists(root): removeDir(root)
    createDir(runtime_dir)
    createDir(artifact_dir)
    writeFile(runtime_dir / "payload.txt", "payload")
    let value = TestVariant(common: "common", kind: tkFile,
      file: Location("payload.txt"))
    let instructions = input_materializer(TestVariant)(value,
      Path(runtime_dir), Path(artifact_dir), "")
    check "input.common: string = common\n" in instructions
    check "input.file: location = payload.txt" in instructions
    check fileExists(artifact_dir / "payload.txt")

  test "absent Option emits none; present sequence uses one-based paths":
    let materialize = input_materializer(Option[seq[int]])
    check materialize(none(seq[int]), Path(getTempDir()), Path(getTempDir()), "") ==
      "input: Option:none\n"
    let values = some(@[3, 5])
    let instructions = materialize(values, Path(getTempDir()), Path(getTempDir()), "")
    check "input[1]: int = 3\n" in instructions
    check "input[2]: int = 5\n" in instructions

  test "deterministic value mutations preserve sequence path invariant":
    let materialize = input_materializer(Option[seq[int]])
    let cases: seq[seq[int]] = @[@[], @[-3], @[0, 7, 11]]
    for values in cases:
      var expected = "seed\n"
      for index, value in values:
        expected.add("input[" & $(index + 1) & "]: int = " & $value & "\n")
      check materialize(some(values), Path(getTempDir()), Path(getTempDir()),
        "seed\n") == expected

  test "variant tags select only active fields":
    let root = getTempDir() / "vecherinka-artifact-tree-variant-test"
    let runtime_dir = root / "runtime"
    let artifact_dir = root / "artifact"
    createDir(runtime_dir)
    createDir(artifact_dir)
    writeFile(runtime_dir / "payload.txt", "payload")
    let materialize = input_materializer(TestVariant)
    let text = materialize(TestVariant(common: "c", kind: tkText, text: "hello"),
      Path(getTempDir()), Path(getTempDir()), "")
    check "input.text: string = hello\n" in text
    check "input.file" notin text
    let file = materialize(TestVariant(common: "c", kind: tkFile,
      file: Location("payload.txt")), Path(runtime_dir), Path(artifact_dir), "")
    check "input.file: location = payload.txt" in file
    check "input.text" notin file

  test "else branch, named tuple, fixed array, distinct, constrained":
    let else_materialize = input_materializer(TestVariantElse)
    check "input.text: string = known\n" in else_materialize(
      TestVariantElse(kind: tkText, text: "known"), Path(getTempDir()),
      Path(getTempDir()), "")
    check "input.fallback: string = fallback\n" in else_materialize(
      TestVariantElse(kind: tkFile, fallback: "fallback"), Path(getTempDir()),
      Path(getTempDir()), "")
    check input_materializer(NamedTuple)((a: 9, b: "nine"), Path(getTempDir()),
      Path(getTempDir()), "") == "input.a: int = 9\ninput.b: string = nine\n"
    check input_materializer(Fixed)([2, 4, 6], Path(getTempDir()),
      Path(getTempDir()), "") == "input[1]: int = 2\ninput[2]: int = 4\ninput[3]: int = 6\n"
    check input_materializer(EmptyFixed)([], Path(getTempDir()),
      Path(getTempDir()), "") == ""
    check input_materializer(BoolFixed)([10, 20], Path(getTempDir()),
      Path(getTempDir()), "") == "input[1]: int = 10\ninput[2]: int = 20\n"
    check input_materializer(EnumFixed)([30, 40], Path(getTempDir()),
      Path(getTempDir()), "") == "input[1]: int = 30\ninput[2]: int = 40\n"
    check input_materializer(NestedFixed)([[1, 2], [3, 4]], Path(getTempDir()),
      Path(getTempDir()), "") == "input[1][1]: int = 1\n" &
      "input[1][2]: int = 2\ninput[2][1]: int = 3\n" &
      "input[2][2]: int = 4\n"
    check input_materializer(AliasFixed)([7, 8, 9], Path(getTempDir()),
      Path(getTempDir()), "") == "input[1]: int = 7\ninput[2]: int = 8\n" &
      "input[3]: int = 9\n"
    let wrapped = DistinctLeaf(TestLeaf(text: "wrapped", count: 8))
    let distinct_text = input_materializer(DistinctLeaf)(wrapped,
      Path(getTempDir()), Path(getTempDir()), "")
    check "input.text: string = wrapped\n" in distinct_text
    check "input.count: int = 8\n" in distinct_text
    check "= 5\n" in input_materializer(SmallCount)(SmallCount(5),
      Path(getTempDir()), Path(getTempDir()), "")
    check "= 7\n" in input_materializer(Natural)(Natural(7),
      Path(getTempDir()), Path(getTempDir()), "")
    check "= 8\n" in input_materializer(Positive)(Positive(8),
      Path(getTempDir()), Path(getTempDir()), "")
    check "= 11\n" in input_materializer(DistinctInt)(DistinctInt(11),
      Path(getTempDir()), Path(getTempDir()), "")
    let alias_seq_text = input_materializer(AliasSeq)(@[TestLeaf(
      text: "aliased", count: 2)], Path(getTempDir()), Path(getTempDir()), "")
    check "input[1].text: string = aliased\n" in alias_seq_text
    let nested_fixed_text = input_materializer(ObjectWithFixed)(
      ObjectWithFixed(values: [1, 2, 3]), Path(getTempDir()),
      Path(getTempDir()), "")
    check "input.values[3]: int = 3\n" in nested_fixed_text

    let alias_text = input_materializer(AliasOption)(
      some(TestLeaf(text: "alias", count: 12)), Path(getTempDir()),
      Path(getTempDir()), "")
    check "input.text: string = alias\n" in alias_text
    check "input.count: int = 12\n" in alias_text

    let variant_text = input_materializer(DistinctVariant)(
      DistinctVariant(TestVariant(common: "wrapped", kind: tkText,
        text: "variant")), Path(getTempDir()), Path(getTempDir()), "")
    check "input.common: string = wrapped\n" in variant_text
    check "input.text: string = variant\n" in variant_text

    let multi_materialize = input_materializer(VariantMulti)
    check multi_materialize(VariantMulti(kind: tkText, text: "multi"),
      Path(getTempDir()), Path(getTempDir()), "") ==
      "input.text: string = multi\n"
    check multi_materialize(VariantMulti(kind: tkFile, text: "multi-file"),
      Path(getTempDir()), Path(getTempDir()), "") ==
      "input.text: string = multi-file\n"

    let empty_materialize = input_materializer(VariantEmpty)
    check empty_materialize(VariantEmpty(kind: tkText), Path(getTempDir()),
      Path(getTempDir()), "") == ""

  test "nested containers preserve branch paths":
    let root = getTempDir() / "vecherinka-artifact-tree-nested-test"
    let runtime_dir = root / "runtime"
    let artifact_dir = root / "artifact"
    createDir(runtime_dir)
    createDir(artifact_dir)
    writeFile(runtime_dir / "nested.txt", "nested")
    let value = NestedContainer(items: @[
      some(TestVariant(common: "a", kind: tkText, text: "one")),
      none(TestVariant),
      some(TestVariant(common: "b", kind: tkFile, file: Location("nested.txt")))])
    let instructions = input_materializer(NestedContainer)(value,
      Path(runtime_dir), Path(artifact_dir), "")
    check "input.items[1].text: string = one\n" in instructions
    check "input.items[2]: Option:none\n" in instructions
    check "input.items[3].file: location = nested.txt" in instructions

  test "fixed-array Location elements and distinct Location are walked":
    let root = getTempDir() / "vecherinka-artifact-tree-fixed-location-test"
    let runtime_dir = root / "runtime"
    let artifact_dir = root / "artifact"
    createDir(runtime_dir)
    createDir(artifact_dir)
    writeFile(runtime_dir / "payload.txt", "payload")
    let fixed_text = input_materializer(FixedLocation)(
      [Location("payload.txt"), Location("payload.txt")], Path(runtime_dir),
      Path(artifact_dir), "")
    check "input[1]: location = payload.txt" in fixed_text
    check "input[2]: location = payload.txt" in fixed_text
    let distinct_text = input_materializer(DistinctLocation)(
      DistinctLocation(Location("payload.txt")), Path(runtime_dir),
      Path(artifact_dir), "")
    check "input: location = payload.txt" in distinct_text

  test "Location materialization disambiguates repeated basenames":
    let root = getTempDir() / "vecherinka-artifact-tree-location-collision-test"
    let runtime_dir = root / "runtime"
    let artifact_dir = root / "artifact"
    for name in ["payload.txt", "payload-1.txt", "payload-2.txt",
        "payload-3.txt"]:
      if fileExists(artifact_dir / name):
        removeFile(artifact_dir / name)
    createDir(runtime_dir / "left")
    createDir(runtime_dir / "right")
    createDir(artifact_dir)
    writeFile(runtime_dir / "left" / "payload.txt", "left")
    writeFile(runtime_dir / "right" / "payload.txt", "right")
    let instructions = input_materializer(TwoLocations)(TwoLocations(
      first: Location("left/payload.txt"),
      second: Location("right/payload.txt")), Path(runtime_dir),
      Path(artifact_dir), "")
    check "materialized as payload.txt" in instructions
    check "materialized as payload-1.txt" in instructions
    check fileExists(artifact_dir / "payload.txt")
    check fileExists(artifact_dir / "payload-1.txt")

proc compile_reject(source, expected: string): bool =
  let probe = getTempDir() / "vecherinka_artifact_tree_negative_probe.nim"
  let binary = getTempDir() / "vecherinka-artifact-tree-negative-probe"
  let full_source = if "force_artifact_tree" in source:
    source & "\nstatic:\n  discard force_artifact_tree(Bad)\n"
  else:
    source
  writeFile(probe, full_source)
  let command = "nim c --hints:off --warnings:off --path:" &
    quoteShell(os.getCurrentDir() / "src") & " -o:" & quoteShell(binary) &
    " " & quoteShell(probe)
  let (output, code) = execCmdEx(command)
  if fileExists(probe): removeFile(probe)
  if fileExists(binary): removeFile(binary)
  code != 0 and expected in output

const negative_probe_prefix = """
import std/macros
include vecherinka
macro force_artifact_tree(T: typedesc): untyped =
  newLit(artifact_tree(T).kind)
"""

suite "artifact_tree rejection contract":
  test "forbidden shapes reject with recommendation":
    check compile_reject(negative_probe_prefix & """
type Bad = ref object
  value: int
""", "ref")
    check compile_reject(negative_probe_prefix & """
type Bad = ptr int
""", "pointer")
    check compile_reject(negative_probe_prefix & """
type Bad = proc(value: int): int
""", "proc")
    check compile_reject(negative_probe_prefix & """
type Bad = set[char]
""", "use seq")
    check compile_reject(negative_probe_prefix & """
import std/json
type Bad = JsonNode
""", "use Location or seq")
    check compile_reject(negative_probe_prefix & """
import std/tables
type Bad = Table[string, int]
""", "use Location or seq")
    check compile_reject(negative_probe_prefix & """
type Bad = char
""", "use Location or seq")
    check compile_reject(negative_probe_prefix & """
type Bad = cstring
""", "use Location or seq")

  test "recursive refs reject cleanly":
    check compile_reject(negative_probe_prefix & """
type Bad = ref object
  next: Bad
""", "ref")

  test "FlowSpec model output cannot be void":
    check compile_reject("""
import std/macros
include vecherinka
const cheap = "test".minimal
expandMacros: vecherinka(bad):
  > start int ~> void {.entry.}:
    cheap[int, void]("return nothing")
""", "void")

  test "prompt templates reject missing and unknown substitutions at comptime":
    check compile_reject("""
import std/macros
include vecherinka
const bad = checked_prompt("$task", "input")
""", "missing required substitution")
    check compile_reject("""
import std/macros
include vecherinka
const bad = checked_prompt("$unknown")
""", "unknown checked_prompt substitution")
    check compile_reject("""
import std/macros
include vecherinka
const bad = checked_prompt("$#", "task")
""", "expected named placeholder")

  test "Schematic else-branch rejection stays outside artifact_tree":
    check compile_reject("""
import std/macros
include vecherinka
type
  Kind = enum kKnown, kOther
  Bad = object
    case kind: Kind
    of kKnown:
      value: int
    else:
      fallback: string
macro force_contract(T: typedesc): untyped =
  model_output_contract(T)
static:
  discard force_contract(Bad)
""", "else` branches are not supported")

suite "artifact_tree generated output verifier":
  test "named prompt substitutions render runtime values":
    let spec = LlmCallSpec[TestOutput](
      profile: ProfileSpec(model: "test-model", effort: re_low),
      prompt: "do task",
      prompt_templates: default_agent_prompt_templates,
      materialized_input: "input.text: string = value\n",
      runtime_dir: Path("/runtime"),
      working_dir: Path("/work"),
      tools: @[],
      output_kind: 0,
      materialize: nil)
    check format_agent_prompt(
      "$task|$input|$working_dir|$runtime_dir|$model|$effort", spec) ==
      "do task|\n\ninput:\ninput.text: string = value\n|/work|/runtime|test-model|re_low"

  test "generated contracts emit schemas for verifier and transport":
    let object_schema = toJsonSchema(output_contract(TestOutput))
    check object_schema["type"].getStr == "object"
    check object_schema["properties"].hasKey("text")
    let variant_schema = toJsonSchema(output_contract(TestVariant))
    check variant_schema.hasKey("oneOf")
    let fixed_schema = toJsonSchema(output_contract(Fixed))
    check fixed_schema["type"].getStr == "array"
    check fixed_schema["minItems"].getInt == 3
    check fixed_schema["maxItems"].getInt == 3

  test "materializer parses and rejects real structured output":
    let valid = test_output_materializer(0, LlmOutput(
      tool_name: "finish_work",
      arguments: parseJson("{\"text\":\"done\",\"count\":7}"),
      working_dir: Path(getTempDir())))
    check valid.ok
    check valid.value.text == "done"
    check valid.value.count == 7
    let invalid = test_output_materializer(0, LlmOutput(
      tool_name: "finish_work",
      arguments: parseJson("{\"text\":\"missing count\"}"),
      working_dir: Path(getTempDir())))
    check not invalid.ok
    check "schema issues" in invalid.error
    check "unexpected model output kind" in test_output_materializer(99,
      LlmOutput(arguments: parseJson("{}"), working_dir: Path(getTempDir()))).error

  test "verifier accepts in-tree Location and reports invalid locations":
    let root = getTempDir() / "vecherinka-artifact-tree-output-test"
    createDir(root)
    writeFile(root / "present.txt", "payload")
    let valid = test_located_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"note\":\"ok\",\"artifact\":\"present.txt\"}"),
      working_dir: Path(root)))
    check valid.ok
    let invalid = test_located_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"note\":\"bad\",\"artifact\":\"missing.txt\"}"),
      working_dir: Path(root)))
    check not invalid.ok
    check "output.artifact" in invalid.error
    check "does not exist" in invalid.error

  test "verifier aggregates invalid Location paths":
    let root = getTempDir() / "vecherinka-artifact-tree-multiple-location-output-test"
    createDir(root)
    let invalid = test_two_located_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"first\":\"a.txt\",\"second\":\"b.txt\"}"),
      working_dir: Path(root)))
    check not invalid.ok
    check "output.first" in invalid.error
    check "output.second" in invalid.error

  test "fixed output keeps declared cardinality":
    let valid = test_fixed_output_materializer(0, LlmOutput(
      arguments: parseJson("[1,2,3]"), working_dir: Path(getTempDir())))
    check valid.ok
    check valid.value == [1, 2, 3]
    let wrong_size = test_fixed_output_materializer(0, LlmOutput(
      arguments: parseJson("[1,2]"), working_dir: Path(getTempDir())))
    check not wrong_size.ok
    let empty = test_empty_fixed_output_materializer(0, LlmOutput(
      arguments: parseJson("[]"), working_dir: Path(getTempDir())))
    check empty.ok
    check empty.value == []
    let nonempty = test_empty_fixed_output_materializer(0, LlmOutput(
      arguments: parseJson("[1]"), working_dir: Path(getTempDir())))
    check not nonempty.ok

  test "fixed lower bounds and Location elements preserve type and paths":
    let lower = test_fixed_lower_output_materializer(0, LlmOutput(
      arguments: parseJson("[4,5,6]"), working_dir: Path(getTempDir())))
    check lower.ok
    check lower.value[-1] == 4
    check lower.value[0] == 5
    check lower.value[1] == 6

    let root = getTempDir() / "vecherinka-artifact-tree-fixed-location-output-test"
    createDir(root)
    writeFile(root / "first.txt", "first")
    writeFile(root / "second.txt", "second")
    let locations = test_fixed_location_output_materializer(0, LlmOutput(
      arguments: parseJson("[\"first.txt\",\"second.txt\"]"),
      working_dir: Path(root)))
    check locations.ok
    check cast[string](locations.value[0]) == "first.txt"
    check cast[string](locations.value[1]) == "second.txt"
    let missing = test_fixed_location_output_materializer(0, LlmOutput(
      arguments: parseJson("[\"first.txt\",\"missing.txt\"]"),
      working_dir: Path(root)))
    check not missing.ok
    check "output[2]" in missing.error

  test "tuple, Option alias, and distinct output extraction":
    let parsed_named = test_named_tuple_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"a\":9,\"b\":\"nine\"}"),
      working_dir: Path(getTempDir())))
    check parsed_named.ok
    check parsed_named.value.a == 9
    check parsed_named.value.b == "nine"

    let present = test_option_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"text\":\"some\",\"count\":2}"),
      working_dir: Path(getTempDir())))
    check present.ok
    check present.value.isSome
    check present.value.get.text == "some"
    let absent = test_option_output_materializer(0, LlmOutput(
      arguments: newJNull(), working_dir: Path(getTempDir())))
    check absent.ok
    check absent.value.isNone

    let distinct_result = test_distinct_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"text\":\"distinct\",\"count\":6}"),
      working_dir: Path(getTempDir())))
    check distinct_result.ok
    let plain = cast[TestLeaf](distinct_result.value)
    check plain.text == "distinct"
    check plain.count == 6

  test "variant output and constrained output round-trip":
    let constrained = test_constrained_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"note\":\"bounded\",\"count\":4}"),
      working_dir: Path(getTempDir())))
    check constrained.ok
    check constrained.value.count == 4
    let variant = test_variant_output_materializer(0, LlmOutput(
      arguments: parseJson("{\"common\":\"c\",\"kind\":\"tkText\",\"text\":\"v\"}"),
      working_dir: Path(getTempDir())))
    check variant.ok
    check variant.value.kind == tkText
    check variant.value.text == "v"
