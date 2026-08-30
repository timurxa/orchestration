# Worker 25 packaging/reproduction check

Status: **PASS for the documented Makefile reproduction path**, with one
packaging caveat for using `best/` outside the repository layout.

The final checks used the later/current workspace snapshot after concurrent
worker updates. No production files were edited. Build outputs and the tiny
probe were kept under `/private/tmp/worker25_packaging.final.MrjcQm` because
the prescribed `~/areas/temp` directory was not writable in this sandbox.

## Reproduction commands

From the repository root:

```sh
make -C /Users/alex/areas/productive/orchestration/testing/manual_runs/1 \
  BUILD=/private/tmp/worker25_packaging.final.MrjcQm/make all
```

Result: exit 0. `dht_asym.o`, `dht_benchmark`, `dht_accuracy`, and
`dht_direct_benchmark` all compiled and linked.

```sh
make -C /Users/alex/areas/productive/orchestration/testing/manual_runs/1 \
  BUILD=/private/tmp/worker25_packaging.final.MrjcQm/make verify
```

Result: exit 0. Dense MPFR cases through `N=512` all passed. The large-row
diagnostic reported `8.1393e-15`; full delta checks reported `1.6267e-16`
and `1.1394e-15`, all below the stated acceptance limits.

```sh
make -C /Users/alex/areas/productive/orchestration/testing/manual_runs/1 \
  BUILD=/private/tmp/worker25_packaging.final.MrjcQm/make benchmark
```

Result: exit 0. `N=65536`, random case, terms 10, cutoff 30, ratio 4;
`plan_bytes=74849448`, `input_hash=0x941d7106a171047d`, and
`output_hash=0x83db592db4288d88`.

```sh
make -C /Users/alex/areas/productive/orchestration/testing/manual_runs/1 \
  BUILD=/private/tmp/worker25_packaging.final.MrjcQm/make direct
```

Result: exit 0; direct benchmark checksum was
`-1.8666746202849271,0.27668635070987596`.

## `best/` forwarding pair and C API

The forwarding source compiled with the repository layout:

```sh
cc -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include -I/Users/alex/areas/productive/orchestration/testing/manual_runs/1/best \
  -c /Users/alex/areas/productive/orchestration/testing/manual_runs/1/best/dht_asym.c \
  -o /private/tmp/worker25_packaging.final.MrjcQm/best/dht_asym.o
```

A deterministic `N=16` C consumer was compiled once against `src/` and once
against `best/`. Both printed exactly:

```text
checksum=0x5fd81b9a781a47a2 size=16 tol=1e-13 terms=10 cutoff=30 direct=225 bytes=7408 ratio=4
```

`diff` of the two probe outputs returned exit 0. A C++17 consumer including
`best/dht.h` and linking the C object also returned exit 0 with the same
output, confirming the header's `extern "C"` linkage. `nm` exposed all 12
public `dht_*` symbols, including `dht_apply`, plan creation/destruction, and
metadata accessors.

## Portability caveat

`best/dht.h` includes `../src/dht.h`, and `best/dht_asym.c` includes
`../src/dht_asym.c`. Therefore the pair works when the repository's `best/`
and `src/` sibling layout is preserved, but copying only the two `best/`
files to a standalone directory fails immediately with:

```text
fatal error: '../src/dht_asym.c' file not found
```

`sh -n bench/run_winner.sh` passed. The full sweep script was not run because
it writes the production `bench/results.csv`, which was out of scope under
the no-production-edits constraint. The explicit README profile command was
also not rerun after the final snapshot because the user requested immediate
finalization; the Makefile's advertised `all/verify/benchmark` path itself
passed.
