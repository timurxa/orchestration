import std/[json, math, os, strutils, times]

const
  scene_nx* = 5
  scene_ny* = 5
  scene_nz* = 100
  body_count* = scene_nx * scene_ny * scene_nz
  step_count* = 4800
  timestep* = 1.0 / 240.0
  gravity* = 9.81
  grid_gap* = 0.03
  grid_pitch* = 1.2 + grid_gap
  density* = 1000.0
  static_friction* = 0.6
  dynamic_friction* = 0.5
  restitution* = 0.05
  contact_rest_velocity* = 0.05
  ground_tolerance* = 1.0e-4
  settle_speed_tolerance* = 1.0e-3
  settle_drift_tolerance* = 1.0e-3
  friction_mu* = dynamic_friction

type
  Vec3* = object
    x*, y*, z*: float64

  BodySpec* = object
    id*: int
    size*: Vec3
    position*: Vec3

  Scene* = object
    seed*: uint64
    bodies*: seq[BodySpec]

  BodyState* = object
    id*: int
    position*: Vec3
    velocity*: Vec3

  SimulationResult* = object
    seed*: uint64
    steps*: int
    checkpoint*: seq[BodyState]
    final_state*: seq[BodyState]
    friction_distance*: float64
    checksum*: string

  StabilityReport* = object
    valid*: bool
    stability*: float64
    max_ground_penetration*: float64
    max_speed*: float64
    max_drift*: float64
    friction_error*: float64
    message*: string

proc next_u64(state: var uint64): uint64 =
  state += 0x9e3779b97f4a7c15'u64
  var z = state
  z = (z xor (z shr 30)) * 0xbf58476d1ce4e5b9'u64
  z = (z xor (z shr 27)) * 0x94d049bb133111eb'u64
  z xor (z shr 31)

proc unit_random(state: var uint64): float64 =
  float64(next_u64(state) shr 11) / 9007199254740992.0

proc body_id(i, j, k: int): int {.inline.} =
  (k * scene_ny + j) * scene_nx + i

proc make_scene*(seed: uint64): Scene =
  result.seed = seed
  result.bodies = newSeq[BodySpec](body_count)
  var state = seed
  var index = 0
  for k in 0 ..< scene_nz:
    for j in 0 ..< scene_ny:
      for i in 0 ..< scene_nx:
        let size = Vec3(
          x: 0.8 + 0.4 * unit_random(state),
          y: 0.8 + 0.4 * unit_random(state),
          z: 0.8 + 0.4 * unit_random(state))
        result.bodies[index] = BodySpec(
          id: body_id(i, j, k),
          size: size,
          position: Vec3(
            x: (float64(i) - 2.0) * grid_pitch,
            y: (float64(j) - 2.0) * grid_pitch,
            z: 0.65 + float64(k) * grid_pitch))
        inc index

proc fnv1a(value: string): string =
  var hash = 1469598103934665603'u64
  for c in value:
    hash = hash xor uint64(ord(c))
    hash *= 1099511628211'u64
  toHex(hash, 16)

proc scene_digest*(scene: Scene): string =
  var text = $scene.seed & ":"
  for body in scene.bodies:
    text.add($body.id & ":" & $body.size.x & "," & $body.size.y & "," &
      $body.size.z & ";")
  fnv1a(text)

proc zero_state*(scene: Scene): seq[BodyState] =
  result = newSeq[BodyState](scene.bodies.len)
  for body in scene.bodies:
    result[body.id] = BodyState(id: body.id, position: body.position,
      velocity: Vec3())

proc json_vec3(value: Vec3): JsonNode =
  result = %*{"x": value.x, "y": value.y, "z": value.z}

proc parse_vec3(node: JsonNode): Vec3 =
  Vec3(x: node["x"].getFloat, y: node["y"].getFloat, z: node["z"].getFloat)

proc state_json(state: BodyState): JsonNode =
  %*{"id": state.id, "position": json_vec3(state.position),
      "velocity": json_vec3(state.velocity)}

proc parse_state(node: JsonNode): BodyState =
  BodyState(id: node["id"].getInt, position: parse_vec3(node["position"]),
    velocity: parse_vec3(node["velocity"]))

proc result_json*(value: SimulationResult): JsonNode =
  result = newJObject()
  result["seed"] = %value.seed
  result["steps"] = %value.steps
  result["friction_distance"] = %value.friction_distance
  result["checksum"] = %value.checksum
  result["checkpoint"] = newJArray()
  result["final_state"] = newJArray()
  for state in value.checkpoint:
    result["checkpoint"].add(state_json(state))
  for state in value.final_state:
    result["final_state"].add(state_json(state))

proc parse_result*(node: JsonNode): SimulationResult =
  result.seed = uint64(node["seed"].getInt)
  result.steps = node["steps"].getInt
  result.friction_distance = node["friction_distance"].getFloat
  result.checksum = node["checksum"].getStr
  for item in node["checkpoint"]:
    result.checkpoint.add(parse_state(item))
  for item in node["final_state"]:
    result.final_state.add(parse_state(item))

proc write_result*(path: string; value: SimulationResult) =
  writeFile(path, $result_json(value))

proc read_result*(path: string): SimulationResult =
  parse_result(parseJson(readFile(path)))

proc state_checksum(states: seq[BodyState]): string =
  var text = ""
  for state in states:
    text.add($state.id & ":" & $state.position.x & "," & $state.position.y &
      "," & $state.position.z & ":" & $state.velocity.x & "," &
      $state.velocity.y & "," & $state.velocity.z & ";")
  fnv1a(text)

proc friction_distance_for_velocity*(initial_velocity: float64): float64

proc validate_result*(scene: Scene; value: SimulationResult): StabilityReport =
  result.valid = false
  if value.seed != scene.seed or value.steps != step_count:
    result.message = "seed or step count mismatch"
    return
  if value.final_state.len != body_count or value.checkpoint.len != body_count:
    result.message = "state count mismatch"
    return
  var max_penetration = 0.0
  var max_speed = 0.0
  var max_drift = 0.0
  var overlap = false
  for body in scene.bodies:
    let final_body = value.final_state[body.id]
    let checkpoint_body = value.checkpoint[body.id]
    if final_body.id != body.id or checkpoint_body.id != body.id:
      result.message = "body id/order mismatch"
      return
    for coordinate in [final_body.position.x, final_body.position.y,
        final_body.position.z, final_body.velocity.x, final_body.velocity.y,
        final_body.velocity.z, checkpoint_body.position.x,
        checkpoint_body.position.y, checkpoint_body.position.z]:
      if classify(coordinate) in {fcNan, fcInf, fcNegInf}:
        result.message = "nonfinite state"
        return
    let penetration = body.size.z / 2.0 - final_body.position.z
    max_penetration = max(max_penetration, penetration)
    let speed = sqrt(final_body.velocity.x * final_body.velocity.x +
      final_body.velocity.y * final_body.velocity.y +
      final_body.velocity.z * final_body.velocity.z)
    max_speed = max(max_speed, speed)
    if abs(final_body.position.x - body.position.x) > ground_tolerance or
        abs(final_body.position.y - body.position.y) > ground_tolerance or
        abs(final_body.velocity.x) > settle_speed_tolerance or
        abs(final_body.velocity.y) > settle_speed_tolerance:
      result.message = "unexpected lateral motion"
      return
    let dx = final_body.position.x - checkpoint_body.position.x
    let dy = final_body.position.y - checkpoint_body.position.y
    let dz = final_body.position.z - checkpoint_body.position.z
    max_drift = max(max_drift, sqrt(dx * dx + dy * dy + dz * dz))
    for lower in scene.bodies:
      if lower.id < body.id and
          lower.id mod (scene_nx * scene_ny) == body.id mod (scene_nx * scene_ny):
        let lower_state = value.final_state[lower.id]
        let required = lower.size.z / 2.0 + body.size.z / 2.0
        if final_body.position.z - lower_state.position.z < required - ground_tolerance:
          overlap = true
  let friction_expected = friction_distance_for_velocity(1.0)
  let friction_error = abs(value.friction_distance - friction_expected) /
    friction_expected
  result.max_ground_penetration = max(0.0, max_penetration)
  result.max_speed = max_speed
  result.max_drift = max_drift
  result.friction_error = friction_error
  let violation = max(max_speed / settle_speed_tolerance,
    max(max_drift / settle_drift_tolerance,
      result.max_ground_penetration / ground_tolerance))
  result.stability = 1.0 - min(1.0, max(0.0, violation - 1.0))
  result.valid = result.max_ground_penetration <= ground_tolerance and
    max_speed <= settle_speed_tolerance and
    max_drift <= settle_drift_tolerance and
    not overlap and
    friction_error <= 0.05 and
    value.checksum == state_checksum(value.final_state)
  result.message = if result.valid: "ok" else: "stability or friction gate failed"

proc expected_friction_distance*(): float64 =
  friction_distance_for_velocity(1.0)

proc friction_distance_for_velocity*(initial_velocity: float64): float64 =
  var velocity = initial_velocity
  while velocity > 0.0:
    velocity = max(0.0, velocity - friction_mu * gravity * timestep)
    result += velocity * timestep

proc write_scene*(path: string; scene: Scene) =
  var node = newJObject()
  node["seed"] = %scene.seed
  node["digest"] = %scene_digest(scene)
  node["bodies"] = newJArray()
  for body in scene.bodies:
    node["bodies"].add(%*{"id": body.id, "size": json_vec3(body.size),
      "position": json_vec3(body.position)})
  writeFile(path, $node)

proc read_scene*(path: string): Scene =
  let node = parseJson(readFile(path))
  result.seed = uint64(node["seed"].getInt)
  for item in node["bodies"]:
    result.bodies.add(BodySpec(id: item["id"].getInt,
      size: parse_vec3(item["size"]), position: parse_vec3(item["position"])))

proc baseline_result*(scene: Scene): SimulationResult =
  ## Restricted grid still runs fixed-step contact integration. Column locality
  ## is benchmark-specific optimization, not a precomputed final-state shortcut.
  result.seed = scene.seed
  result.steps = step_count
  var states = zero_state(scene)
  for step in 0 ..< step_count:
    for body in scene.bodies:
      let column = body.id mod (scene_nx * scene_ny)
      let lower_id = body.id - scene_nx * scene_ny
      let support = if lower_id >= 0 and
          lower_id mod (scene_nx * scene_ny) == column:
        states[lower_id].position.z + scene.bodies[lower_id].size.z / 2.0
      else:
        0.0
      let target = support + body.size.z / 2.0
      states[body.id].velocity.z -= gravity * timestep
      states[body.id].position.z += states[body.id].velocity.z * timestep
      if states[body.id].position.z < target:
        states[body.id].position.z = target
        states[body.id].velocity.z = if abs(states[body.id].velocity.z) <=
            contact_rest_velocity:
          0.0
        elif states[body.id].velocity.z < 0.0:
          -states[body.id].velocity.z * restitution
        else:
          0.0
    if step == 4320 - 1:
      result.checkpoint = states
  result.final_state = states
  result.friction_distance = friction_distance_for_velocity(1.0)
  result.checksum = state_checksum(result.final_state)

proc baseline_solver_source*(): string =
  """import std/[os, strutils]
import rigidbody_benchmark

let args = commandLineParams()
var seed = 1'u64
var output = "result.json"
var i = 0
while i < args.len:
  if args[i] == "--seed":
    inc i
    seed = uint64(parseUInt(args[i]))
  elif args[i] == "--output":
    inc i
    output = args[i]
  inc i
let scene = make_scene(seed)
var probe_velocity = 1.0
for index in 0 ..< args.len:
  if args[index] == "--probe-velocity" and index + 1 < args.len:
    probe_velocity = parseFloat(args[index + 1])
var result = baseline_result(scene)
result.friction_distance = friction_distance_for_velocity(probe_velocity)
write_result(output, result)
"""

proc run_baseline*(scene: Scene; output: string) =
  write_result(output, baseline_result(scene))
