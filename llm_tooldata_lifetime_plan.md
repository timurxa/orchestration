# Dynamic tool callback lifetime plan

## Goal

Keep the dynamic callback `.nimcall.` and avoid closures, while making callback
state lifetime explicit and safe for persistent Codex runtimes.

## Recommended design: runtime-owned POD bindings

1. Replace GC-managed `ref LlmToolData` with a small manually allocated POD
   token. The token contains only:

   - owning `CodexRuntime` pointer
   - stable binding ID

   No `string`, `seq`, `JsonNode`, or other traced fields.

2. Add a runtime-owned binding table keyed by binding ID. Each binding stores
   the erased pointers and scalar metadata needed by the generated callback:

   - `RuntimeContext` pointer
   - model request ID
   - output kind
   - generated materializer pointer
   - active/completed state

3. Generated `submit` allocates/registers one binding, creates the token, and
   passes the token as `DynamicTool.data`. The existing `.nimcall.` callback:

   - casts only the POD token
   - looks up the binding in the owning runtime
   - ignores/rejects inactive or unknown bindings
   - queues copied transport data

4. Keep the binding alive for the full lifetime of copied agent tools. On
   successful materialization, retire the binding. On invalid output, keep it
   active so the model can retry `finish_work`.

5. At runtime teardown, deactivate bindings before releasing the associated
   `RuntimeContext`; free token storage only after no agent can invoke the
   callback. Persistent agents must not retain an active binding after its
   flow ends.

6. Remove `LlmToolData`, `new_llm_tool_data`, `retain_llm_tool_data`,
   `release_llm_tool_data`, and the `ref`/raw-pointer reconstruction.

## Rejected alternatives

- Closures: GC lifetime is cleaner, but disallowed and changes the callback API.
- Inline state inside `DynamicTool`: registry/agent copies can invalidate
  addresses.
- Current `ref object` behind `pointer`: untraced pointer and teardown hole.
- Manual state containing `RequestId.string_value`: traced data in unmanaged
  storage is unsafe.

## Verification

- Exercise callback through `accept_json` on the owner thread.
- Test integer and string tool request IDs.
- Test valid completion, invalid-result retry, and unknown/inactive binding.
- Test copied tools retained by a persistent agent.
- Test teardown ordering with readers stopped before context/binding release.
- Run all Nim tests under `--mm:orc` and `--mm:arc` with isolated nimcache.
