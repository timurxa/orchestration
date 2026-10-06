import std/[json, os, random, tables, unittest]
import ../api/codex_json
import ../api/codex_runtime

suite "Codex workspace sandbox":
  test "thread start serializes workspace-write":
    let message = Message(
      kind: mk_request,
      request: Request(
        kind: mk_thread_start,
        id: RequestId(kind: rid_integer, integer_value: 1),
        params: Params(
          kind: mk_thread_start,
          thread_start: ThreadStartParams(
            sandbox: NullableOption[SandboxMode](
              state: nos_value,
              value: sm_workspace_write)))))

    let encoded = serialize_message(message)
    check encoded["method"].getStr == "thread/start"
    check encoded["params"]["sandbox"].getStr == "workspace-write"

  test "runtime gives each agent the workspace-write sandbox":
    randomize()
    let root = getTempDir() / ("codex-sandbox-test-" & $rand(high(int)))
    createDir(root)
    let fakeBin = root / "bin"
    createDir(fakeBin)
    let fakeCodex = fakeBin / "codex"
    writeFile(fakeCodex, "#!/bin/sh\nwhile IFS= read -r line; do :; done\n")
    setFilePermissions(fakeCodex, {fpUserRead, fpUserWrite, fpUserExec})

    let oldPath = getEnv("PATH")
    putEnv("PATH", fakeBin & PathSep & oldPath)
    var runtime: ptr CodexRuntime = nil
    try:
      runtime = init_codex_runtime(root)
      let requestId = create_agent(runtime, "sandbox-test-agent", "")
      let request = runtime.state.requests[request_id_key(requestId)]
      check request.request.params.thread_start.sandbox.state == nos_value
      check request.request.params.thread_start.sandbox.value == sm_workspace_write
      check request.request.params.thread_start.cwd.value == expandFilename(root)
    finally:
      if not runtime.isNil:
        deinit_codex_runtime(runtime)
      putEnv("PATH", oldPath)
      removeDir(root)
