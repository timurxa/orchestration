import std/[options, atomics]
import json
import results
import schematic
import codex_json
import codex_runtime
import artifact

type
  Scope* = object
    codex*: ptr CodexRuntime
  Nursery* = object
  Task*[T] = object
  ModelError* = object
    error*: string
  BackedValue[T] = object
    value: T
    artifacts_ids: seq[ArtifactID]
  Outcome[T] = Result[BackedValue[T], ModelError]
  Job*[T] = proc(s: Scope): T {.closure.}
  Prompt* = string
  Model* = enum
    m_luna, m_terra, m_sol
  Profile* = object
    model*: Model
    effort*: ReasoningEffort
  Request*[T] = object
    prompt*: Prompt
    profile*: Profile
    anchors*: seq[ArtifactID]

var agent_id: Atomic[int]

proc model_name(model: Model): string =
  result = case model:
    of m_luna: "gpt-5.6-luna"
    of m_terra: "gpt-5.6-terra"
    of m_sol: "gpt-5.6-sol"

proc perform*[T](s: Scope; r: Request[T]): Outcome[T] =
  let codex = s.codex

  var completion: Option[ToolCallContext]
  let schema = schemaOf(BackedValue[T])
  var tools: DynamicToolRegistry = @[]
  tools.register_dynamic_tool(
    "finish_work",
    "Submit final structured result. Call exactly once when task is complete.",
    toJsonSchema(schema),
    nil,
    proc(data: pointer; context: ToolCallContext) =
      completion = some(context)
  )

  let agent_id = $agent_id.fetchAdd(1)
  discard codex.create_agent(
    agent_id = agent_id, 
    model = model_name(r.profile.model),
    tools = tools,
  developer_instructions = """
    Complete user task.
    Call finish_work exactly once after completion.
    Put final result in finish_work arguments.
    """,
  )

  var sent_initial_message = false

  let output = s.codex.server_stdout_stream()
  var line: string
  while output.readLine(line):
    discard s.codex.accept_json(parseJson(line))

    if not sent_initial_message and
        codex.agents[agent_id].thread_id.has_value:
      discard codex.send_agent_message(agent_id, r.prompt)
      sent_initial_message = true

    if completion.isSome:
      let done = completion.get()

      codex.accept_tool_response(
        done,
        true,
        @[dynamic_tool_text($done.params.arguments)]
      )

      let parsed = schema.tryParse(done.params.arguments)
      if parsed.ok: result = ok(parsed.value)
      else: result = err(ModelError(error: $parsed.issues.len))

      break
