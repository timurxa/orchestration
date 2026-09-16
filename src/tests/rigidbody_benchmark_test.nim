import std/unittest
import ../benchmark/rigidbody_benchmark

suite "rigidbody benchmark contract":
  test "seed fixes scene":
    let first = make_scene(42)
    let second = make_scene(42)
    check first.bodies.len == body_count
    check scene_digest(first) == scene_digest(second)
    check scene_digest(first) != scene_digest(make_scene(43))

  test "baseline satisfies bounded gates":
    let scene = make_scene(42)
    let report = validate_result(scene, baseline_result(scene))
    check report.valid
    check report.stability >= 0.99
    check report.friction_error <= 0.05

  test "wrong fast result fails overlap gate":
    let scene = make_scene(42)
    var value = baseline_result(scene)
    for state in value.final_state.mitems:
      state.position.z = 0.5
    value.checksum = "wrong"
    check not validate_result(scene, value).valid
