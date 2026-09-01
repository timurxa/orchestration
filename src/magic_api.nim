import std/[os, sugar, atomics, jsonutils, json]
import db_connector/db_sqlite
import results
import schematic
import codex_json
import codex_runtime

# API
type
  Error = object
    message: string
  Outcome*[T] = Result[T, Error]
  Consumer*[T] = (Outcome[T] {.closure.} -> void)

type
  Model* = enum
    luna, terra, sol
  Profile = object
    model: Model
    effort: ReasoningEffort
  Prompt = string
  Start* = object
  AgentCreationTrigger* = object
    agent_id*: string
    then*: proc () {.gcsafe.}
  AppEventKind* = enum
    runtime_work
    on_agent_creation
    codex_output
    codex_error
    terminate
  AppEvent* = object
    case kind*: AppEventKind
    of runtime_work:
      work*: proc () {.gcsafe.}
    of on_agent_creation:
      trigger*: AgentCreationTrigger
    of codex_output, codex_error:
      message*: string
    of terminate: discard
  ReaderState* = object
    output_fd*, error_fd*, stop_fd*: cint
  Context* = object
    agent_id: Atomic[int]
    runtime*: ptr CodexRuntime
    global*: ptr Channel[AppEvent]
    reader_state*: ReaderState
    stop_pipe*: array[0..1, cint]
    pending_on_agent_creation_triggers*: seq[AgentCreationTrigger]
    db*: DbConn
  Contextual*[A, B] =
    (ptr Context {.closure.} -> ((A, Consumer[B]) {.closure.} -> void))

proc `=copy`(dest: var Context; source: Context) {.error.}

template `~>`*(A, B: typedesc): untyped =
  Contextual[A, B]

proc model_name*(model: Model): string =
  case model:
  of luna: "gpt-5.6-luna"
  of terra: "gpt-5.6-terra"
  of sol: "gpt-5.6-sol"

proc submit[A, B](
  context: ptr Context;
  profile: Profile;
  prompt: Prompt;
  data: A;
  callback: Consumer[B]
) =
  let schema = schemaOf(B)
  var tools: DynamicToolRegistry = @[]
  tools.register_dynamic_tool(
    "finish_work",
    "Submit final structured result. Call exactly once when task is complete.",
    toJsonSchema(schema),
    nil,
    proc(data: pointer; tool_context: ToolCallContext) =
      context.global[].send(AppEvent(
        kind: runtime_work,
        work: proc () {.gcsafe.} =
          {.cast(gcsafe).}: 
            context.runtime.accept_tool_response(
              tool_context,
              true,
              @[dynamic_tool_text($tool_context.params.arguments)]
            )

            let parsed = schema.tryParse(tool_context.params.arguments)
            if parsed.ok: callback(Outcome[B].ok(parsed.value))
            else: callback(Outcome[B].err(Error(message: $parsed.issues.len)))
      ))
  )

  let agent_id = $context.agent_id.fetchAdd(1)
  discard context.runtime.create_agent(
    agent_id = agent_id,
    model = model_name(profile.model),
    tools = tools,
    developer_instructions = "Complete task. Submit final result with `finish_work`. None of your responses outside of tool call response is observable.",
  )

  context.global[].send(AppEvent(
    kind: on_agent_creation,
    trigger: AgentCreationTrigger(
      agent_id: agent_id,
      then: proc () {.gcsafe.} =
        {.cast(gcsafe).}:
          discard context.runtime.set_agent_goal(agent_id, "Complete task. Call `finish_work` exactly once with final result.")
          let message = prompt & "\n\ninput: " & data.toJson().pretty()
          discard context.runtime.send_agent_message(
            agent_id,
            message
          )
    )))

proc pure*[T](given: T): Start ~> T =
  (_: ptr Context,) {.closure.} =>
    ((_: Start, consumer: Consumer[T]) {.closure.} =>
      consumer(Outcome[T].ok(given)))

proc `>>>`*[A, B, C](
  left: Contextual[A, B];
  right: Contextual[B, C]
): Contextual[A, C] =
  proc composed(ctx: ptr Context): (A, Consumer[C]) -> void =
    let left_step = left(ctx)
    let right_step = right(ctx)
    proc apply(value: A; consumer: Consumer[C]) =
      left_step(value, (outcome: Outcome[B],) => (
        if outcome.isErr:
          consumer(Outcome[C].err(outcome.error))
        else:
          right_step(outcome.get, consumer)))
    apply
  composed

proc `[]`*[A, B](profile: Profile; _: typedesc[A]; _: typedesc[B]): (Prompt -> Contextual[A, B]) =
  result = (prompt: Prompt,) =>
    ((context: ptr Context,) {.closure.} =>
      ((value: A, consumer: Consumer[B]) {.closure.} =>
        submit(context, profile, prompt, value, consumer)))

proc minimal*(model: Model): Profile = Profile(model: model, effort: re_minimal)
proc low*(model: Model): Profile = Profile(model: model, effort: re_low)
proc medium*(model: Model): Profile = Profile(model: model, effort: re_medium)
proc high*(model: Model): Profile = Profile(model: model, effort: re_high)
proc xhigh*(model: Model): Profile = Profile(model: model, effort: re_xhigh)
