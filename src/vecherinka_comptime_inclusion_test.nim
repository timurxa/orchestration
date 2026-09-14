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
## Practical verdict differs: current vecherinka model-output pipeline still
## fails for several variants after artifact_tree, inside Schematic schema
## generation/extraction. Separate artifact_tree defects also block types below.
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
## Confirmed artifact_tree failures
##
## Each probe called artifact_tree(T) directly. Each failed with exact form:
## `cannot walk artifact type X`.
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
## Reason: dispatch only recognizes Location, listed scalar/enum leaves,
## seq, Option, object, and tuple. All other shapes reach final error at
## artifact_tree line 774.
##
## Confirmed composite defects
##
## 1. Named tuple aliases recurse.
##
##   type NamedTuple = tuple[a: int, b: string]
##
## Result: repeated artifact_tree/artifact_fields calls, then:
## `maximum call depth for the VM exceeded`.
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
## Generated materializer compilation errors:
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
## Direct `Option[int]` passed. `type Alias = Option[int]` failed:
## `artifact walker only supports plain fields`.
##
## Cause: direct bracket AST is recognized at lines 729-739. Alias resolves to
## Option's object representation on Nim 2.3.1, then object-field walking runs
## instead of Option handling. Same pattern can affect generic aliases whose
## type identity is no longer a bracket expression.
##
## End-to-end variant failures outside artifact_tree
##
## model_output_contract correctly routes ank_variant to discriminated at
## lines 1011-1020. Current Schematic dependency then adds separate limits:
##
## - Top-level variant with `else`: exact compile error
##   `discriminated(T): \`else\` branches are not supported`.
## - Nested variant field: Schematic calls structural nodeOf and exact error is
##   `cannot derive a structural schema for a variant object; use discriminated`.
## - Simple top-level variant without else reaches extraction, then Nim 2.3.1
##   reports `undeclared field: 'getStr'` inside Schematic's buildFromJson path.
##
## These failures do not disprove artifact_tree. They prove current
## vecherinka-to-Schematic integration is not variant-complete.
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
## - Named tuple AST recursion.
## - Missing distinct composite casts.
## - Option alias recognition.
## - Schematic `getStr` extraction failure for otherwise valid simple variant.
## - Any FlowSpec void codomain acceptance. Preserve void domains used by
##   no-input operations.
##
## Keep direct artifact_tree tests separate from full vecherinka/Schematic tests.
## A passing walker test must not mask schema rejection; a Schematic rejection
## must not be reported as artifact_tree failure.

{.experimental: "callOperator".}

include vecherinka
