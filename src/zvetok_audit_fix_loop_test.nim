{.experimental: "callOperator".}

import zvetok

type
  ImplementationRequest = distinct string
  Codebase = distinct Location
  Issues = distinct seq[string]
  Audit = object
    case ok: bool
    of true: discard
    of false: issues: Issues

zvetok:
  proc fix: (Codebase, Issues) ~> Codebase =
    cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")

  proc audit: (ImplementationRequest, Codebase) ~> Audit =
    cheap[(ImplementationRequest, Codebase), Audit]("Audit the codebase for issues based on the implementation request")

  proc audit_fix_loop: (ImplementationRequest, Codebase) ~> Codebase {.entry.} =
    (&&& it audit) >>> (so[((ImplementationRequest, Codebase), Audit), Codebase](input) do:
      let ((req, code), audit) = input
      if audit.ok: pure(code)
      else: (req, (code, audit.issues)) >>> lift[(_, here)](fix) >>> audit_fix_loop)
