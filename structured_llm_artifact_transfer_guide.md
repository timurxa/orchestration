# Structured LLM calls with schemas, `Location`, and artifact transfer

This is the historical design for making one model operation consume a typed
value, materialize it for an agent, provide the output JSON schema, and return
the result as the next typed artifact.

## Historical implementation

The working versions are in these commits:

- `6a0b75c` (`init`) — the first synchronous `perform[T]` call.
- `bd1e2f5` (`>>>` operator and first sorta-working system) — the async
  `magic_api.submit[A, B]` version.
- `163a0f6` — adds the explicit agent goal and improves the completion
  instructions.
- `f2ad7bc` (`feat: artifact management`) — adds `Location` materialization,
  per-call artifact directories, output validation, and artifact transfer.
- `3b19b3a` (`remove unnecessary stuff`) — removes this implementation.

Useful commands for recovering the exact old sources:

    git show 6a0b75c:src/orchestration_api.nim
    git show bd1e2f5:src/magic_api.nim
    git show f2ad7bc:src/bezkonza_impl.nim
    git show f2ad7bc:src/main.nim

The most complete implementation is `f2ad7bc:src/bezkonza_impl.nim`,
especially its `submit`, `materialize`, `output_schema`, `location_contract`,
and `verify_locations` sections.

## The call boundary

The model call has four distinct inputs or outputs:

    typed input artifact
            |
            | materialize inline fields and copy Location payloads
            v
    agent working directory + textual instructions + finish_work schema
            |
            | model writes files and calls finish_work once
            v
    validated typed output artifact

The model does not receive a Nim value or an `ArtifactData` object. It receives
human-readable instructions for ordinary fields, a directory containing the
materialized files, and a dynamic tool whose arguments are constrained by the
output schema.

## 1. Build the output schema from the result type

The original synchronous implementation starts with the output type:

    let schema = schemaOf(BackedValue[T])

Then it exposes that schema as the input schema of a dynamic `finish_work`
tool:

    tools.register_dynamic_tool(
      "finish_work",
      "Submit final structured result. Call exactly once when task is complete.",
      toJsonSchema(schema),
      nil,
      proc(data: pointer; context: ToolCallContext) =
        completion = some(context)
    )

The tool callback is only a notification that a candidate result arrived. The
actual typed conversion happens afterward with:

    let parsed = schema.tryParse(done.params.arguments)
    if parsed.ok:
      result = ok(parsed.value)
    else:
      result = err(ModelError(error: $parsed.issues.len))

For the artifact-aware version, the equivalent steps are:

1. `output_schema(B)` returns `schemaOf(B)` for ordinary output types.
2. For a generated tagged artifact variant, it uses a discriminator-aware
   schema (`discriminated(B, kind_field)`).
3. `toJsonSchema(output_contract)` becomes the `finish_work` input schema.
4. The callback first runs `output_contract.tryParse(arguments)`.
5. Only a successfully parsed value can become an output artifact.

The JSON schema handles structure and types. It does not prove that a returned
`Location` points to a real file. That is a separate semantic validation step.

## 2. Send instructions after the thread exists

`create_agent` queues a thread start and installs the dynamic tool. The old
runtime waits until the app-server response gives the new thread its ID, then
sends the actual user prompt with `send_agent_message`.

The original `perform` loop was:

    discard codex.create_agent(
      agent_id = agent_id,
      model = model_name(r.profile.model),
      tools = tools,
      developer_instructions = """
        Complete user task.
        Call finish_work exactly once after completion.
        Put final result in finish_work arguments.
      """
    )

    while output.readLine(line):
      discard codex.accept_json(parseJson(line))

      if not sent_initial_message and codex.agents[agent_id].thread_id.has_value:
        discard codex.send_agent_message(agent_id, r.prompt)
        sent_initial_message = true

      if completion.isSome:
        # acknowledge the server-side tool request, parse its arguments, and stop
        break

The later async version moves the same actions into the central event loop. It
also sends the input as `prompt & "\n\ninput: " & data.toJson().pretty()`.
This ordering matters: do not call `send_agent_message` before the thread ID
has been received.

The developer instructions and the user message should make completion
unambiguous:

    Complete the task.
    Call finish_work exactly once after completion.
    Put the final result in finish_work arguments.
    Text outside the tool call is not the result.

## 3. Define `Location` as a relative artifact reference

The historical API defines:

    type Location* = distinct string

`Location` is not an absolute filesystem path. It is a reference to a file or
directory below an artifact directory. For an artifact with directory
`artifact-12`, the value `src/main.nim` means:

    artifact-12/src/main.nim

The helper used by the old implementation was conceptually:

    proc location_path(artifact_dir: Path; location: Location): Path =
      artifact_dir / Path(string(location))

This gives the type a runtime meaning while keeping the value portable between
agents and artifact generations. Never put the source machine's absolute path
in the model-facing value.

## 4. Materialize input into a fresh artifact directory

Each model call gets a new directory, historically named `artifact-N`, inside
the run directory. The input artifact has its own `artifact_dir`; materializing
the input copies it into the new directory and generates the textual input
description at the same time.

For ordinary scalar or enum fields, materialization appends a line such as:

    problem.goal: string = Fix the parser

For a `Location` field, it:

1. Interprets the value as a path relative to the source artifact directory.
2. Copies the source file or directory to the same relative path below the
   destination artifact directory.
3. Appends a line identifying the relative location, for example:
   `problem.codebase: location = repo`.
4. Raises an I/O error if the source path does not exist.

The historical materializer recursively handled:

- public object fields;
- tagged object variants;
- `seq[T]`, with one-based human-readable paths such as `items[1]`;
- `Option[T]`, including an explicit `Option:none` line;
- `Location` leaves;
- scalar and enum leaves.

The important invariant is that the agent can see every inline value in the
instructions and can access every `Location` payload in its working directory.
The relative name in the instructions and the copied path must agree.

Example input type:

    type
      Problem* = object
        goal*: string
        codebase*: Location

For `codebase = Location("repo")`, the model receives a prompt describing
`problem.codebase` as `repo`, and `artifact-N/repo` contains the copied
directory. The model is instructed to modify only that destination artifact
directory.

## 5. Tell the model the `Location` output contract

The old implementation separately generated a location contract by walking the
output type. It listed nested paths, including conditions for variants,
sequences, and options. A representative contract is:

    Location fields:
    - response.files[*]
    - response.reviewed_code (when present)
    - response.payload (kind = artifactCode)

The model-facing instructions should state all of the following:

    You may only modify files in <artifact_dir>.
    Location fields are strings containing paths relative to <artifact_dir>.
    Every returned Location must name an existing file or directory below
    <artifact_dir>.
    If a field is an ordinary string rather than a listed Location field, return
    literal text in that field.
    Call finish_work once with an object matching the supplied JSON schema.

This distinction is essential. Because `Location` is represented as a string
in JSON, the model needs explicit instructions to know which strings are path
references and which are ordinary prose.

## 6. Validate and accept the output

The artifact-aware callback in `f2ad7bc` uses two gates:

    let parsed = output_contract.tryParse(tool_context.params.arguments)
    if not parsed.ok:
      accept_tool_response(tool_context, false, @[dynamic_tool_text(parse_error)])
      return

    let res = parsed.value
    let verification_error = verify_locations(res, artifact_dir)
    if verification_error.len != 0:
      accept_tool_response(tool_context, false,
        @[dynamic_tool_text(verification_error)])
      return

    accept_tool_response(tool_context, true,
      @[dynamic_tool_text($tool_context.params.arguments)])

`verify_locations` walks the same structural shape as the materializer. For
each `Location`, it checks that `artifact_dir / relative_location` is an
existing file or directory. It also descends through the active branch of a
variant, every sequence element, and present options.

Rejecting the tool call (`success = false`) is preferable to silently creating
an invalid artifact: the agent receives the validation message and can repair
the files or submit a corrected relative path. A valid result is then wrapped
with the destination directory and converted into the generated tagged artifact
using the historical `to_artifact` adapter.

## 7. Transfer artifacts between chained model calls

The old runtime's transfer object was:

    type ArtifactData* = object
      id*: ArtifactID
      artifact_dir*: Path
      data*: Artifact

`Artifact` is a generated tagged union containing one branch for each declared
artifact type. The artifact ID identifies the logical value; `artifact_dir`
identifies its materialized filesystem payload; `data` contains the typed,
in-memory fields, including relative `Location` strings.

Composition with `>>>` passes the completed `ArtifactData` to the next
operation. The next operation does not reuse the previous directory directly.
It allocates its own destination directory and materializes the incoming value
there. Consequently, transfer is:

    artifact A / artifact-1
           |
           | copy Location payloads + render inline fields
           v
    model B / artifact-2
           |
           | validate finish_work and retain newly written files
           v
    artifact B / artifact-2

This is copy-on-transfer with immutable logical inputs. It prevents one model
call from mutating another call's view and gives every model a self-contained
working directory. The old code also allows future optimizations such as
hard-links, snapshots, deltas, or content-addressed storage, as long as the
next call still sees the same logical artifact and relative `Location` contract.

The initial problem is seeded as an artifact whose source directory is the
process working directory. Every later model output is assigned a fresh ID and
the directory created for that call. The artifact value—not an absolute path or
an ad-hoc JSON blob—is what travels through the flow.

## Current repository status and restoration plan

The current implementation has the pieces of the newer runtime boundary, but
not the complete historical behavior:

- `src/vecherinka_comptime.nim:9` has compile-time JSON-schema text support.
- `src/vecherinka_comptime.nim:586` lowers a typed model call and creates an
  `LlmCallSpec` with typed context, output kind, tools, and a materializer.
- `src/vecherinka_runtime.nim:798` dispatches that spec through an injectable
  `LlmTransport`.
- `src/codex_runtime.nim:540` installs dynamic tool schemas on a thread, and
  `src/codex_runtime.nim:607` sends the turn after thread creation.
- `src/vecherinka_runtime.nim:765` is still a deterministic debug transport;
  `debug_tool_registry` currently returns an empty schema and the current
  generated path does not yet perform historical `Location` copying or
  `finish_work` decoding.

To restore the old behavior in the current architecture, implement the pieces
in this order:

1. Preserve a generated `ArtifactData`-like boundary containing the tagged
   artifact value and its artifact directory.
2. Generate or centralize a recursive materializer for inline fields,
   `Location`, variants, sequences, and options.
3. Allocate one destination directory per model request and materialize the
   real input there.
4. Generate `output_schema(B)` plus the location contract and register
   `finish_work` with that schema.
5. Send the prompt only after the thread-start response; include the materialized
   input, location rules, output schema, and working-directory restriction.
6. Parse tool arguments, verify every returned location, acknowledge or reject
   the tool request, and construct the typed output artifact.
7. Enqueue the completed artifact as a runtime event so the existing
   continuation, join, and work-node machinery transfers it to the next flow
   operation.

Keep the existing ownership rule while doing this: reader threads should only
frame stdout/stderr and enqueue events. JSON parsing, Codex state changes,
artifact validation, and flow resumption belong to the runtime's central owner.

## Design rules to preserve

- The output schema is derived from the actual typed output, not hand-written
  at each call site.
- `Location` values are relative references, never absolute paths. When
  restoring the design, normalize and validate each path so it cannot escape
  the artifact directory through `..`, an absolute path, or a symlinked
  destination.
- Every model request receives an isolated materialized directory.
- The model must return `Location` paths for files it actually created or kept
  in that directory.
- Schema parsing and filesystem validation are separate required checks.
- A rejected tool call must return a useful validation message to the agent.
- A successful tool call becomes a typed artifact before the next continuation
  runs.
- Artifact transfer copies/materializes payloads; it does not pass mutable
  directory ownership between model calls.
