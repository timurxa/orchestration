# Vecherinka DSL: actual scope

This is an audit of source currently in this repository, not a proposed API.
Source and passing tests are authoritative. "Proven" means an implementation
path or test demonstrates it. "Source-only" means lowering/type code supports
it but no current end-to-end surface test covers it. "Inference" means behavior
follows from generated code but is not pinned by a test.

Primary sources: vecherinka.nim, vecherinka_comptime.nim,
vecherinka_runtime.nim, vecherinka_manual_test.nim, and
vecherinka_comptime_inclusion_test.nim. The it and lift grammar claims also
come from it_projection.nim / its tests and lift_pattern_typed.nim / its
tests. Schematic claims refer to installed schematic 0.6.0, resolved by
nimble path schematic.

## Surface entry point

Importing vecherinka includes runtime and compile-time layers. The façade also
enables Nim's callOperator experiment:

~~~nim
import vecherinka

const profile = "model-name".medium

expandMacros: vecherinka(solve):
  > start Input ~> Output {.entry.}:
    profile[Input, Output]("Do task")
~~~

Exact flow declaration shape:

    > flow_name Domain ~> Codomain {.entry.}:
      flow expression(s)

vecherinka accepts either vecherinka(solve): ... or
vecherinka(solve, prompt_templates): .... solve must be an identifier, symbol,
or acc-quoted name; generated procedure has that name. The body must contain
declarations in this > form at its direct level. The macro turns each
declaration into a FlowSpec reference plus a hidden flow proc, then lowers it
to one generated solve procedure.

Source: src/vecherinka_comptime.nim:2412-2459.

expandMacros: is Nim's expansion directive, not a Vecherinka construct. The
active manual example uses it at src/vecherinka_manual_test.nim:41-43.

## Flow types and model calls

A ~> B is a template for FlowSpec[A, B]. A FlowSpec has a domain and a
codomain. Every FlowSpec codomain must be non-void; a void domain is valid for
no-input values and callbacks.

Source: src/vecherinka_comptime.nim:27-49 and 401-414. Rejection test:
src/vecherinka_comptime_inclusion_test.nim:654-662.

Model call syntax:

~~~nim
profile[Input, Output]("prompt")
~~~

The profile expression must type as ProfileSpec; both bracket arguments are
typedescs; final argument must type as string. Result type is exactly
FlowSpec[Input, Output]. Output is registered for generated structured output.
Output = void is rejected at compile time.

Source: src/vecherinka_comptime.nim:39-45, 416-459, 1579-1594,
1811-1823.

Active source-grounded example:

~~~nim
type Simple = object
  message: string

const cheap = "gpt-5.6-luna".medium

expandMacros: vecherinka(solve):
  > basic Simple ~> Simple {.entry.}:
    cheap[Simple, Simple]("Write a welcome message into 'message' field.")
~~~

This exact shape is in src/vecherinka_manual_test.nim:19-43 and is executed by
that manual test.

## Composition

Two overloads exist:

~~~nim
left_flow >>> right_flow       # FlowSpec[A, B] >>> FlowSpec[B, C]
raw_value >>> right_flow        # A >>> FlowSpec[A, B]
~~~

Types are exact Nim generic endpoints. First form yields FlowSpec[A, C].
Second form yields FlowSpec[void, B] and seeds the chain with the raw value.
No implicit conversion, mapping, tuple flattening, or name-based matching is
added. Lowering recognizes both infix and call-shaped >>> ASTs.

Source: src/vecherinka_comptime.nim:42-45 and 1725-1788.

Inside a generated flow, named flow declarations are FlowSpec values, not
callable procedures. A recursive reference is structurally supported because
all references are emitted before hidden flow procs and runtime roots resolve
by name; this is source-only/inference, not an active integration test.

The public FlowSpec constructors return placeholder IR outside the Vecherinka
lowering pass (firk_empty for ordinary composition/model/pure helpers). They
are surface syntax when used inside vecherinka, not a separate standalone
executor API.

Source: src/vecherinka_comptime.nim:39-49.

## pure

~~~nim
pure(value)
~~~

Type is FlowSpec[void, typeof(value)]. It emits a raw artifact value and no
model request. Its codomain still cannot be void. It is valid as a no-input
branch, as a so result, or as the left side of >>> when followed by a
FlowSpec whose domain matches its value type.

Source: src/vecherinka_comptime.nim:48-49, 542-557, 1763-1770,
1937-1947.

## fan

~~~nim
fan(flow_1, flow_2, ...)
~~~

At least one typed branch is required. Every branch must be a FlowSpec with the
same domain. Result is a FlowSpec whose codomain is an ordered tuple of branch
codomains:

~~~nim
fan(profile[A, B]("b"), profile[A, C]("c"))
# FlowSpec[A, (B, C)]  (type-level result)
~~~

Branch count, branch domains, and branch codomains are checked during
lowering. Runtime opens a fork/join, runs each branch with the same input, then
coalesces results in source order. fan() is rejected.

Source: src/vecherinka_comptime.nim:50-77, 525-540, 1978-2021;
runtime fork/join: src/vecherinka_runtime.nim:1415-1434 and 1056-1062.

`fan` expands to an internal `fanout[A, TupleOfOutputs, TupleOfFlows](...)`
call. `fanout` is exported, but its ordinary proc body emits placeholder IR;
only the lowerer's exact nonempty tuple-shaped call is meaningful. This is
source-only internal form, not a separate documented spelling.

The example and type comment are source-derived; current repository tests do
not execute a surface fan flow.

## so

Exact macro syntax:

~~~nim
so(Domain, Codomain, input) do:
  # body must produce FlowSpec[void, Codomain]
~~~

It creates FlowSpec[Domain, Codomain] around a callback of type
proc(input: Domain): FlowSpec[void, Codomain]. Domain must be non-void;
callback input type must exactly match it. The callback body may use ordinary
Nim statements and return pure(...) or a raw-value-seeded chain:
The exported `so_syntax` proc is the lower-level callback wrapper that `so`
emits; it is source-level helper syntax, not a different runtime node.

~~~nim
so(Domain, Codomain, input) do:
  if condition:
    pure(value)
  else:
    value_for_next_step >>> next_step
~~~

The exact callback signature and lowering are source-proven at
src/vecherinka_comptime.nim:79-88 and 2023-2050. The active repository has no
executed surface so example. The macro reads pattern.strVal; simple identifier
use is the only form with clear support.

Runtime invokes callback only after receiving typed input. A nil child flow
passes the current value onward, but normal generated so bodies produce a flow.

Source: src/vecherinka_runtime.nim:1513-1524.

## it projection

Identity:

~~~nim
it(Domain)
~~~

Selection appends one or more selector groups using a nested bracket shape:

~~~nim
it(Tuple)[[0]]                 # first tuple item
it(Tuple)[[0, 1]]               # tuple of items 0 and 1
it(Object)[[field]]             # object field
it(Nested)[[0], [field]]        # field selection on each item selected by 0
it(Tuple)[[0 .. 2]]             # range, expanded to 0, 1, 2
~~~

The outer brackets are the path; each inner bracket is one group. Selectors
are:

    selector ::= signed integer literal
              | identifier
              | integer-literal .. integer-literal
    path     ::= [ group, ... ]
    group    ::= [ selector, ... ]

Parser rules, proven by src/it_projection_tests.nim:381-428 and 440-506:

- integer, i8/i16/i32/i64, decimal/hex/octal/binary, digit separators, and
  negative literal forms are accepted when Nim creates an accepted integer AST;
  unsigned, float, string, char, expression, and computed bounds are not;
- field selectors are plain identifiers/symbols or valid flat acc-quoted names;
  spelling is preserved by the parser;
- one group cannot mix numeric and field selectors;
- a range must be the only selector in its group and bounds must be
  nondecreasing;
- duplicate indexes and duplicate field names are syntactically retained;
- at least one group and one selector per group are required.

Parser does not resolve selectors against a type. Later typed elaboration uses
value[index], value.field, or tuple expansion. Ranges require the value at that
nesting level to be a tuple; bounds must be 0 <= first <= last < arity. One
selected item collapses to that item; multiple selections form a tuple. Each
later group applies to every selected item and retains tuple nesting.

Source: src/it_projection.nim:70-126 and src/vecherinka_comptime.nim:90-149.

it(Domain)[0] is not the supported spelling: selectors must be inside a
group, so use it(Domain)[[0]]. The parser is syntax-only; a syntactically valid
path can still fail later if the domain has no such index/field.
Applying the selector brackets to a non-it FlowSpec is not projection syntax;
the extension macro requires the underlying it IR.

it flow endpoints are non-void, and result codomain is inferred with typeof
from the projection. This is source-only for surface runtime use; current
it_projection tests directly test the parser, not a generated Vecherinka run.

## lift and here

Exact composition syntax:

~~~nim
lift(pattern)[inner_flow]
~~~

inner_flow must be a FlowSpec[InnerDomain, InnerCodomain] with both endpoints
non-void. lift derives outer endpoints by replacing every plain here with those
inner endpoints:

~~~nim
lift(here)[flow]                       # X ~> Y
lift(seq[here])[flow]                  # seq[X] ~> seq[Y]
lift(Option[here])[flow]               # Option[X] ~> Option[Y]
lift((FixedType, here))[flow]          # (FixedType, X) ~> (FixedType, Y)
lift((left: here, right: FixedType))[flow]
~~~

These endpoint rules are compile-time tested in
src/lift_pattern_typed_tests.nim:581-606. Object pattern endpoints are the
object type itself even when members contain here; member structure is opaque
to endpoint derivation, while runtime traversal still visits members.

Accepted pattern grammar:

    pattern ::= type-expression
              | here
              | seq[pattern]
              | Option[pattern]
              | [](seq, pattern)
              | [](Option, pattern)
              | (pattern, ...)
              | (name: pattern, ...)
              | Type(name: pattern, ...)

Pattern parentheses may wrap one pattern and are stripped. Tuple and object
patterns must be nonempty. Tuple entries must be all named or all unnamed;
duplicate tuple labels and duplicate object fields are rejected
case/style-insensitively. Names in tuple/object label positions may be here,
_, seq, or Option; these are labels there, not special syntax.

Pattern-level here is exactly a plain identifier/symbol spelled here.
Acc-quoted here is a type name, not a placeholder. Plain _ is rejected;
acc-quoted _ is a type name. seq and Option are wrapper heads only when plain
and used at a pattern node; inside a type expression they are ordinary type
names.

Source: src/lift_pattern_typed.nim:41-161 and 225-312; formal grammar/tests:
src/lift_pattern_typed_tests.nim:14-115 and 419-579.

Type-expression parsing is deliberately syntactic. It accepts names,
acc-quoted names, dotted names, bracket expressions with valid type arguments,
and bracket-operator call forms. Valid type arguments include supported
literals, signed numeric literals, .. ranges, nonempty tuple constructions,
and parenthesized type arguments. It does not resolve a type symbol at parser
time; generated artifact/type checking does that later.

Runtime lift cardinality is structural:

- each here contributes one inner invocation;
- seq contributes one per element;
- present Option contributes one subtree, absent Option contributes none;
- tuple and object members concatenate work in source order;
- type-only leaves contribute no work and are retained unchanged.

Results are put back using the original outer shape. Objects begin as the
original object; fields with no here remain unchanged. Dynamic sequence and
Option counts are checked through contiguous result indexes at runtime.

Source: src/vecherinka_comptime.nim:2088-2104, 2115-2249, 2252-2323, and
src/vecherinka_runtime.nim:1436-1473.

The commented manual loop is the clearest source example:
src/vecherinka_manual_test.nim:50-56. It is not an active passing test. Pattern
lift(int)[flow] is syntactically accepted but creates zero inner work; this is
source-derived, not a tested useful idiom.

## Entry markers and roots

Only a codomain pragma spelling exactly like this is recognized as an entry
marker:

~~~nim
> start Input ~> Output {.entry.}:
~~~

The macro records the marker in FlowIR.entry. Lowering requires exactly one
entry flow and requires its domain to be non-void; runtime independently
rejects missing or multiple entry roots. Root names are runtime table keys, so
duplicate names fail at runtime plan initialization.

Source: src/vecherinka_comptime.nim:2420-2451 and 2325-2355; runtime:
src/vecherinka_runtime.nim:901-928.

Other pragma spellings are not entry markers. Multiple pragmas are not a
documented extension of the flow header. entry belongs after codomain, not
after flow name or domain.

## Profile syntax

ProfileSpec contains model: string and effort: ReasoningEffort. Exported
UFCS-friendly constructors are:

~~~nim
"model".none       # re_none
"model".minimal    # compatibility alias for re_none
"model".low        # re_low
"model".medium     # re_medium
"model".high       # re_high
"model".xhigh      # re_xhigh
"model".max        # re_max
~~~

The same procs can be called normally, for example medium("model").
Explicit ProfileSpec(model: "model", effort: re_low) is also a valid Nim value.
The effort enum and wire spellings are none, low, medium, high, xhigh, max.

Source: src/vecherinka_runtime.nim:23-25 and 718-732, and
src/codex_json.nim:52-58 and 546-553.

At runtime the selected model and effort are sent during thread creation and
the effort is sent again for the turn. Source:
src/vecherinka_runtime.nim:1146-1161 and 1238-1247.

## Prompt templates and checked placeholders

Custom template syntax:

~~~nim
const templates = AgentPromptTemplates(
  developer_instructions: checked_prompt("Developer text"),
  goal: checked_prompt("Goal: $task", "task"),
  turn_prompt: checked_prompt(
    "$task\n\nDir: $working_dir\nInput: $input",
    "task", "working_dir", "input"),
  finish_work_description: checked_prompt("Submit result once"))

vecherinka(solve, templates):
  ...
~~~

checked_prompt(text, required...) requires text to be a normal, raw, or
triple-quoted string literal. It recognizes only named placeholders whose
names start with letter/underscore and continue with letters, digits, or
underscore. Allowed names, case/style-insensitively, are:
$task, $input, $working_dir, $runtime_dir, $model, $effort.
$$ is accepted as an escaped dollar pair. Unknown names, $#, trailing $,
nonliteral text, nonliteral required names, and missing required placeholders
fail at compile time.

Source: src/vecherinka_comptime.nim:461-523. Rejection tests:
src/vecherinka_comptime_inclusion_test.nim:664-679.

Required names are an extra check; a template need not mention every allowed
name unless listed in required.

Runtime replacement values:

    $task         model-call prompt
    $input        "\n\ninput:\n" + materialized input, or empty string
    $working_dir  current model call artifact directory
    $runtime_dir  run's runtime directory
    $model        ProfileSpec.model
    $effort       enum spelling, e.g. re_low

developer_instructions, goal, and turn_prompt are formatted at their
respective runtime stages. finish_work_description is passed as the dynamic
tool description without a format_agent_prompt call. A direct model prompt only
needs to type as string; it is not automatically checked by checked_prompt.

Source: src/vecherinka_runtime.nim:301-310 and 1163-1181, and
src/vecherinka_comptime.nim:1453-1539.

Without a custom template, default_agent_prompt_templates supplies task,
working-directory, runtime-directory, Location, and input instructions. Exact
text is at src/vecherinka_runtime.nim:301-310.

## Artifact type scope

Vecherinka creates a private generated tagged artifact type with one case per
unique non-void flow domain/codomain. Artifact walking is used for input
materialization and Location verification; Schematic is used for model output
JSON contracts. These are different proof boundaries.

### Proven artifact-tree classifications

| Type shape | Actual handling |
|---|---|
| bool, strings, integer/float scalars | inline leaf |
| enums | inline leaf; Schematic JSON is enum string |
| Location and distinct wrappers over Location | Location leaf |
| plain objects | named-field descent |
| object variants | common fields plus active branch descent |
| positional/named tuples | tuple descent; named slots use fields |
| seq[T] and aliases | sequence descent |
| Option[T] and aliases | present value or explicit none branch |
| fixed array[...] and aliases | sequence-like descent with fixed cardinality retained |
| distinct scalar/composite wrappers | base representation with generated casts where needed |
| constrained integer/range types | inline leaf when represented by supported Schematic/scalar shape |

The inclusion suite proves these classifications and many generated walkers:
src/vecherinka_comptime_inclusion_test.nim:354-393 and 408-571. It also
executes nested object/sequence/Option/variant/Location paths, named tuples,
fixed arrays, distinct values, aliases, and constrained values.

### Paths and materialization

The location type is exactly `Location = distinct string`; a source value is
written as `Location("relative/path")`. It is a relative runtime artifact
path, not an arbitrary host path or a typed file handle.

Object fields append .field. Sequence and fixed-array elements append one-based
human paths such as items[1]; fixed-array lower bounds are not shown. Unnamed
tuple slots use numeric selectors from the artifact walker; this is
source-derived, not separately asserted by current materializer tests. Named
tuple slots use .name.

Present Option[T] descends into T; absent options emit
path: Option:none. Location leaves emit path: location = value and copy a file
or directory from runtime_dir / value into the call's artifact directory.
Repeated basenames get -1, -2, ... suffixes. Empty, missing,
outside-runtime, and source-containing-destination paths raise I/O errors.

Source: src/vecherinka_comptime.nim:952-1122 and
src/vecherinka_runtime.nim:831-882; tests:
src/vecherinka_comptime_inclusion_test.nim:433-567.

### Output contracts

For ordinary output types the generated contract is schemaOf(T). For a
top-level artifact variant it is discriminated(T, discriminator). If a fixed
array occurs, generated wire types replace fixed arrays with seq and add exact
minItems/maxItems for a top-level fixed array; conversion restores the declared
array and lower bound.
Nested fixed arrays also become seq-shaped wire values, but their nested
bounds are not emitted as nested schema metadata. Do not infer full nested
fixed-array validation from the top-level test.

Source: src/vecherinka_comptime.nim:1212-1389; schema tests:
src/vecherinka_comptime_inclusion_test.nim:753-762 and 806-844.

Schematic's actual boundaries matter:

- top-level plain object output is proven;
- simple top-level variant output is proven and uses oneOf;
- variant else branches fail in discriminated with the message
  "else branches are not supported";
- nested variant fields fail when structural nodeOf reaches the variant;
- artifact-tree walking accepts variant else, multi-label, and empty branches,
  but that does not make those shapes valid model-output contracts;
- fixed arrays nested inside a variant output hit the generated
  discriminated/wire limitation and are not a proven supported output shape;
- named-tuple output round-trip is proven. Schematic derives tuple values via
  its object-style fieldPairs path; positional-tuple model output has no
  current round-trip test and should not be assumed to use an array wire shape.

These Schematic distinctions are documented and tested separately in
src/vecherinka_comptime_inclusion_test.nim:116-129, 681-697, and 846-884,
plus installed schematic.nim:697-739 and 1502-1580.

### Location output verification

Before accepting a structured finish_work result, generated code checks every
active Location under objects, active variant branches, sequences, fixed arrays,
and present Options. It requires a nonempty path naming an existing file or
directory under the model call's working directory. Invalid paths are reported
as materialization failure; tests cover valid, missing, multiple,
fixed-array, and nested cases.

Source: src/vecherinka_comptime.nim:1152-1177 and 1391-1451;
src/vecherinka_runtime.nim:1581-1628.

Important current semantic split: input Location copying resolves
runtime_dir / location, while output verification resolves
working_dir / location. execute_flows sets runtime_dir to the process working
directory and gives each model call a fresh artifact directory. Thus source
does not prove that a Location produced by one model call is resolvable as the
next call's input Location; the two current roots differ.

Source: src/vecherinka_comptime.nim:1482-1487,
src/vecherinka_runtime.nim:1740-1743 and 831-894.

## Compile-time constraints

The current compile-time contract is stricter than ordinary Nim syntax:

- flow expressions must be typed FlowSpec expressions recognizable by the
  lowering pass; arbitrary templates/macros/type syntax are not treated as
  flows;
- fan needs at least one typed branch; so needs a non-void domain and exact
  callback input type; lift needs a non-void inner flow;
- every flow output must be non-void, but no-input pure/model/callback flows may
  have void domains;
- artifact rejection happens while walking types, before runtime execution;
- generated output type must be present in the private artifact registry;
- compiler/dependency behavior is pinned by tests to Nim 2.3.1 arm64 and the
  installed Schematic dependency. vecherinka.nim and inclusion tests both
  require callOperator experimental syntax.

Proven artifact rejection includes ref objects (including recursive refs),
pointers, proc values, sets, JsonNode, Table, char, and cstring, with
diagnostics recommending seq or Location where applicable.

Source/tests: src/vecherinka_comptime.nim:847-950 and
src/vecherinka_comptime_inclusion_test.nim:618-652.

Schematic itself supports more types than Vecherinka's artifact contract. Do
not infer Vecherinka support merely because Schematic has nodeOf, extract, or
serialize code for a type.

## Runtime constraints

Generated solve signature is effectively:

~~~nim
proc solve(
  input: EntryDomain;
  transport: LlmTransport[GeneratedArtifact] = nil;
  logger: StructuredLogger = nil
): EntryCodomain
~~~

The artifact type is generated/private, so callers normally use inferred
arguments rather than naming it. Runtime stores artifacts by ID, evaluates
raw/it/so/fan/lift nodes on the owner thread, suspends at model nodes, and
resumes through runtime events.

Source: src/vecherinka_comptime.nim:2365-2402 and
src/vecherinka_runtime.nim:1475-1536.

execute_flows creates a run directory below the process working directory,
starts or borrows a Codex app-server runtime, starts stdout/stderr readers,
and runs until the entry result or terminal failure. With no custom transport,
the default path requires a working codex app-server; with a custom
LlmTransport, it still must produce the runtime completion event expected by
the plan.

Source: src/vecherinka_runtime.nim:1707-1796.

The generated model call installs one dynamic finish_work tool whose schema is
the output contract. Tool output must decode under that schema and pass
Location verification. Unexpected tool names, invalid JSON/schema values,
missing output, or app-server/runtime failures terminate the plan.

Source: src/vecherinka_comptime.nim:1497-1526 and
src/vecherinka_runtime.nim:1545-1645.

Runtime tool handles require 64-bit pointers. Source:
src/vecherinka_runtime.nim:324-325.

The separate compiler probe in
nim_macro_generic_function_pointer_investigation.md shows a Nim compiler
crash for a generic helper calling flow.execute(default(A)) on the generated
artifact (genFieldObjConstr). It also shows explicit typed input succeeds.
This is not evidence that surface so or all generic callbacks are unsupported;
it is a compiler/evaluator probe boundary.

## Known unsupported or false-looking syntax

These are actual rejection or non-support boundaries, not suggested features:

- it(Domain)[0]: wrong path shape; use it(Domain)[[0]].
- lift(_): _ is not a wildcard. Plain here is the only placeholder.
- lift(`here`) is a type name, not the placeholder.
- lift(Box[here]) is rejected by the restricted type-expression grammar;
  it does not substitute inner endpoints.
- lift(seq[...]) / lift(Option[...]) with zero or multiple pattern args,
  [](seq, p, extra), or [](): rejected wrapper forms.
- empty tuple/object patterns, mixed named/unnamed tuple entries, duplicate
  pattern names, and arbitrary expressions are rejected.
- so without four macro arguments, or with callback input not exactly equal to
  the declared domain, is rejected by lowering/type checks.
- fan() is rejected; mixed-domain branches are rejected.
- ~> is the flow-header arrow. No =>, <~, implicit map, implicit bind, or
  automatic field projection exists in this source.
- .entry. is a single codomain marker. No documented entry keyword, entry
  function call, or multiple-entry behavior exists.
- Output = void is rejected for every FlowSpec construction path discovered by
  the walker.
- char/cstring look scalar but are explicitly rejected as artifact leaves;
  JsonNode, Table, sets, refs, pointers, and proc values likewise are not
  Vecherinka artifact leaves.
- Schematic else variant output and nested structural variant output are not
  equivalent to artifact-tree variant support.
- Schematic DSL forms such as schema:, schemaOf, discriminated, tup,
  namedTuple, and oneOfSchema belong to imported Schematic; they are not
  additional Vecherinka flow constructs. Vecherinka invokes selected Schematic
  operations internally.

## Evidence gaps

Current active tests directly execute the simple manual model flow and execute
artifact materializers/verifiers. They do not execute a complete surface fan,
so, it, or lift graph. Parser, lowering, generated-code, and runtime code
provide source-only/inference evidence for those constructs.

Likewise, input artifact walking is broader than proven model-output
round-tripping. Historical design prose in
structured_llm_artifact_transfer_guide.md describes earlier implementation
states; where it conflicts with current source, current source/tests above win.
