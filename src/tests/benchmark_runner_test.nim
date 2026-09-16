import std/[os, tempfiles, unittest]
import ../benchmark/benchmark_runner

suite "benchmark runner":
  test "runs timed deterministic candidate":
    let root = createTempDir("rigidbody-runner-test-", "")
    defer:
      if dirExists(root): removeDir(root)
    let report = benchmark_candidate("/tmp/rigidbody-baseline", 42, root)
    check report.valid
    check report.stability >= 0.99
    check report.checksums.len == 3
