import std/[os, strutils]
import ./rigidbody_benchmark

let args = commandLineParams()
var seed = 1'u64
var output = "result.json"
var probe_velocity = 1.0
var i = 0
while i < args.len:
  if args[i] == "--seed":
    inc i
    seed = uint64(parseUInt(args[i]))
  elif args[i] == "--output":
    inc i
    output = args[i]
  elif args[i] == "--probe-velocity":
    inc i
    probe_velocity = parseFloat(args[i])
  inc i
let scene = make_scene(seed)
var result = baseline_result(scene)
result.friction_distance = friction_distance_for_velocity(probe_velocity)
write_result(output, result)
