#set document(title: "Semantic Primitives for Orchestration")
#set page(margin: (x: 1.25in, y: 1in))
#set text(size: 11pt, lang: "en")
#set par(leading: 0.65em, justify: true)

= Semantic Primitives for Orchestration

Our core semantic additions are:

#table(
  columns: (1.2fr, 4fr),
  inset: 8pt,
  align: (left, left),
  stroke: (x: none, y: 0.5pt),
  fill: (_, row) => if row == 0 { luma(235) } else { none },
  [*Primitive*], [*Meaning*],
  [#raw("pure")], [Value to arrow-compatible translation],
  [#raw(">>>")], [Direct composition],
  [#raw("&&&")], [Same input, multiple computations (fan-out)],
  [#raw("lift")], [Structured-preserving focused computation],
  [#raw("it")], [Projection],
  [#raw("=>")], [Easy inline dynamic workloads],
)

== Execution model

At the actual execution level, we have:

```nim
type Contextual[A, B] = (
    ctx: ptr Context,
    val: ArtifactDate,
    con: (Outcome[B]) -> void
  )-> void
```

The shortcut #raw("A ~> B = Contextual[A, B]") is used throughout. Note
that #raw("->") still represents a regular Nim function.

The core operators are:

```nim
pure : A -> (A ~> A)
>>>  : (A ~> B) -> (B ~> C) -> (A ~> C)
&&&  : (A ~> B) -> (A ~> C) -> (A ~> (B, C))
```

== Runtime choices

For runtime choices and integrating inline code, we use #raw("=>"), which
has the following grammar:

```nim
(x: A) => body: ? ~> B : A ~> B
```

== Projection

For projection, we introduce the simple #raw("it") primitive, which allows
for easily working with tuples:

```nim
(A, B) >>> (it[1])
(A, B, C) >>> (it[1..2])
(a: A, b: B) >>> (it[a])
```

It also works with objects:

```nim
(A) >>> (it[issues])
```

It may eventually support paths as well. Its defining characteristic is that
it is a projection operator and does not perform any transformation beyond
discarding data.

== Structured lifting

The last primitive is #raw("lift"), which handles parallelization and certain
effectful transformations. It is defined as #raw("lift[S](f)"), with
#raw("f : A ~> B"), and takes the shape #raw("S[A] -> S[B]"):

```nim
S ::= _, ?
      seq[S]
      Option[S]
      (S_1, ..., S_n)
      (a: S_a, ..., z: S_z)
```

#raw("?") represents places where #raw("f") will be applied, while
#raw("_") means to ignore that input.

A few examples motivate this:

+ *Decompose, solve, synthesize:*

  ```nim
  decompose >>> lift[seq[?]](solve) >>> synthesize
  ```

  Here we have parallel solves running to transform a sequence of subproblems
  into a sequence of solutions.

+ *Partial processing:*

  ```nim
  (a, b) >>> lift[(_, ?)](f)
  ```

  Without #raw("lift"), this would require:

  ```nim
  (a, b) >>> (it[0] &&& (it[1] >>> f))
  ```

Together, all these primitives allow for very concise and understandable
orchestration code.

= Implementation

== First Pass

Take the representative input
```nim
type
  ImplementationRequest = distinct string
  Codebase = distinct Location
  Issues = distinct seq[string]
  Audit = object
    case ok: bool
    of true: discard
    of false: issues: Issues

const cheap = luna.low

proc fix: (Codebase, Issues) ~> Codebase =
  cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")

proc audit: (ImplementationRequest, Codebase) ~> Audit =
  cheap[(ImplementationRequest, Codebase), Audit]("Audit the codebase for issues based on the implementation request")

proc audit_fix_loop: (ImplementationRequest, Codebase) ~> Codebase =
  (it &&& audit) >>> (((req, code), audit)) so:
    if audit.ok: pure(code)
    else: (req, (code, audit.issues)) >>> lift[(_, here)](fix) >>> audit_fix_loop
```
On first pass we lower all the primitives to get (focusing only on the procs), where `&&&`
requires special handling because we do not want repeated `&&&` calls to lead to nested tuples
```nim
proc fix: C_ntextual[(Codebase, Issues), Codebase] =
  cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")

proc audit: C_ntextual[(ImplementationRequest, Codebase), Audit] =
  cheap[(ImplementationRequest, Codebase), Audit]("Audit the codebase for issues based on the implementation request")

proc audit_fix_loop: C_ntextual[(ImplementationRequest, Codebase), Codebase) =
  (it &&& audit) >>> (((req, code), audit)) so:
    if audit.ok: pure(code)
    else: (req, (code, audit.issues)) >>> lift[(_, here)](fix) >>> audit_fix_loop

proc audit_fix_loop: C_ntextual[(ImplementationRequest, Codebase), Codebase) =
  proc (ctx: ptr C_ntext; inp: (ImplementationRequest, Codebase); con: proc (cod: Codebase)) =
    
```
