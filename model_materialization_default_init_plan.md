# Model materialization default-init fix

## Goal

Remove the generic `default(A)` compiler-crash path while preserving typed
success values and structured parse failures.

## Plan

1. Change `ModelMaterialization[A]` into a case object:

   ```nim
   ModelMaterialization[A] = object
     case ok*: bool
     of true:
       value*: A
     of false:
       error*: string
   ```

   Failure values then contain no `A` field.

2. Rewrite generated materializers to return explicit constructors:

   - parse failure: `ModelMaterialization[A](ok: false, error: ...)`
   - success: `ModelMaterialization[A](ok: true, value: packed_artifact)`
   - unexpected output kind: explicit failure constructor

3. Remove `var decoded: ModelMaterialization[A]` from the runtime handler.
   Keep the decoded value scoped inside a `try` block with a `let` binding.

4. Add `.noinit.` only where required after compilation checks. Do not use
   it as a substitute for explicit construction.

5. Search production and generated paths for every generic `default(A)` and
   remove or replace each one. The known crash is caused by the generic
   artifact-construction path, not merely by the result wrapper.

6. Keep sentinel generation only for generic helpers that truly need a
   synthetic artifact. Generate concrete sentinels from `artifact_tree` for
   scalar, enum, `Location`, sequence, option, tuple, object, variant, and
   distinct types. Never use a zero/default value as an artifact sentinel.

## Verification

- Re-run the historical `genFieldObjConstr` reproducer on available Nim
  versions.
- Compile generated flows returning string, object, and variant artifacts.
- Test valid `finish_work` JSON and invalid JSON/type failures.
- Test nested, fanout, and chained model flows.
- Run all repository Nim tests with isolated nimcache directories.
