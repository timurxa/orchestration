# F* v2 multi-module build diagnosis

> **Historical build snapshot.** Later addendum and run-log entries supersede
> its build result; consult the current state/run log before relying on it.

## Result

Current `make verify` is false-green evidence. It exits zero while warning that three `open` directives cannot resolve. F* warning 285 is nonfatal by default. The module filenames also do not match their declared names: source says `module WorkflowV2.Kernel`, while file is `WorkflowV2/Kernel.fst`. F* resolves the module as `WorkflowV2.Kernel.fst` in an include directory. Official F* documentation says module name must match filename ([module structure](https://fstar-lang.org/tutorial/book/part1/part1_getting_off_the_ground.html)).

Correcting only the source layout exposes a real typechecking failure in `WorkflowV2.Identity`: its `work_package` proof fails at line 94. Thus current success does not establish that all listed modules verify as modules. Kernel alone verifies. Identity does not. Journal has not been established as a clean dependency-ordered build because Identity fails first.

## Reproduction

F* binary: `/Users/alex/.opam/ocaml.5.3.0/bin/fstar.exe`, version `F* 2026.03.24`, commit `70671ffb81fa30aba09b9d6e2af275dfbccaa8f8`. F* expects Z3 4.13.3. Ambient Homebrew `z3` is 4.15.4; put opam bin directory first in `PATH` so `z3` resolves to `/Users/alex/.opam/ocaml.5.3.0/bin/z3` (4.13.3).

From repository root, current target:

```sh
make -C src/fstar/v2 verify \
  FSTAR=/Users/alex/.opam/ocaml.5.3.0/bin/fstar.exe
```

Output:

```text
* Warning 285 at Identity.fst(3,16-3,22):
  - No modules in namespace WorkflowV2.Kernel and no file with that name either
* Warning 285 at Journal.fst(3,16-3,22):
  - No modules in namespace WorkflowV2.Kernel and no file with that name either
* Warning 285 at Journal.fst(4,16-4,24):
  - No modules in namespace WorkflowV2.Identity and no file with that name either
All verification conditions discharged successfully
```

Makefile passes dependency-ordered source arguments, but unresolved imports are warnings, not fatal errors. Adding `--warn_error @285` to that invocation turns warnings into errors (three errors reported). Zero exit status means only that no fatal diagnostic occurred; it does not mean imports resolved.

Per-module reproduction against current slash-layout sources:

```sh
cd src/fstar/v2
/Users/alex/.opam/ocaml.5.3.0/bin/fstar.exe --cache_off \
  --include src --include /tmp/fstar-v2-proof-research \
  --odir /tmp/fstar-v2-proof-research src/WorkflowV2/Identity.fst
```

Output:

```text
* Warning 285 at Identity.fst(3,16-3,22):
  - No modules in namespace WorkflowV2.Kernel and no file with that name either
* Error 134 at Identity.fst(3,16-3,22):
  - Namespace 'WorkflowV2.Kernel' cannot be found.
1 error was reported (see above)
```

`--cache_off` disables reads and writes of `.checked` files. Each process therefore needs a resolvable source module or an existing checked module. Here import lookup seeks `WorkflowV2.Kernel.fst`, not current `WorkflowV2/Kernel.fst`, so each later process fails import lookup. Caching does not fix filename/path mismatch.

To isolate path behavior, exact source copies were staged under canonical F* filenames in `/tmp/fstar-v2-dot-layout/`:

```text
WorkflowV2.Kernel.fst
WorkflowV2.Identity.fst
WorkflowV2.Journal.fst
```

With correct Z3 path, checking `WorkflowV2.Identity.fst` resolves its Kernel dependency and reports:

```text
* Error 19 at WorkflowV2.Identity.fst(94,30-94,32):
  - Subtyping check failed
  - Expected type work_ref_for w == work_ref_for w got type Prims.unit
  - The SMT solver could not prove the query.
1 error was reported (see above)
```

Same failure occurs when all three canonical module files are checked in one dependency-ordered invocation with `--warn_error @285`: no warning 285, but Identity proof fails. Path correction enables actual module resolution and reveals independent proof blocker.

## Minimal reproducible target

Use canonical module filenames, or stage byte-for-byte copies under those filenames. Keep `--cache_off` if independent full checks are desired, and make unresolved-module warning 285 fatal. Pin F* and expected Z3 in target. For example, after renaming files to matching dotted names:

```make
FSTAR := /Users/alex/.opam/ocaml.5.3.0/bin/fstar.exe
BUILD_DIR ?= /tmp/fstar-v2-check
SOURCES := src/WorkflowV2.Kernel.fst \
           src/WorkflowV2.Identity.fst \
           src/WorkflowV2.Journal.fst

verify:
	@mkdir -p "$(BUILD_DIR)"
	PATH="/Users/alex/.opam/ocaml.5.3.0/bin:$$PATH" \
	  $(FSTAR) --cache_off --warn_error @285 \
	  --include src --include "$(BUILD_DIR)" --odir "$(BUILD_DIR)" \
	  $(SOURCES)
```

With current contents, target must fail at Identity line 94. That is correct until proof is fixed. Then it can establish a clean dependency-ordered check without import warnings. Do not suppress 285, omit dependencies, or treat warning-bearing success as verification.

## Source anchors

- `src/fstar/v2/Makefile:5-13`: slash-path module list and permissive one-shot invocation with `--cache_off`.
- `src/fstar/v2/src/WorkflowV2/Kernel.fst:1`, `Identity.fst:1`, `Journal.fst:1`: declared dotted module names.
- `src/fstar/v2/src/WorkflowV2/Identity.fst:3,94`: unresolved import under current layout; failing `work_package` proof under canonical layout.
- `src/fstar/v2/src/WorkflowV2/Journal.fst:3-4`: imports affected by same path mismatch.
