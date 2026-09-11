We start with a representative example:
```nim
konez:
  > fix (Codebase, Issues) ~> Codebase:
    cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")

  > audit (ImplementationRequest, Codebase) ~> Audit:
    cheap[(ImplementationRequest, Codebase), Audit]("Audit the codebase for issues based on the implementation request")

  > audit_fix_loop (ImplementationRequest, Codebase) ~> Codebase {.entry.}:
    (it &&& audit) >>> so[Codebase](((req, code), audit)):
      if audit.ok: pure(code)
      else: (req, (code, audit.issues)) >>> lift[(_, here)](fix) >>> audit_fix_loop
```
we set up Flow forward declarations and a typed macro which allows us to do further processing. We annotate the procs we generate to easily reference them later.
```nim
konez_semantic:
  const fix = FlowRef(0)
  const audit = FlowRef(1)
  const audit_fix_loop = FlowRef(0)
  
  const flow_0: (Codebase, Issues) ~> Codebase {.flow(0).} =
    cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")

  const flow_1: (ImplementationRequest, Codebase) ~> Audit {.flow(1).} =
    cheap[(ImplementationRequest, Codebase), Audit]("Audit the codebase for issues based on the implementation request")

  const flow_2: (ImplementationRequest, Codebase) ~> Codebase {.flow(2, true).} =
    (it &&& audit) >>> so[Codebase](((req, code), audit)):
      if audit.ok: pure(code)
      else: (req, (code, audit.issues)) >>> lift[(_, here)](fix) >>> audit_fix_loop
```
given that we've provided the right code in `konez.nim`, this should compile
