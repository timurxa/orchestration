# Worker 20 — benchmark integrity audit

Date: 2026-08-28

Scope: the repository contract plus `bench/benchmark.c`, `bench/accuracy.c`,
`bench/run_winner.sh`, `Makefile`, and the current `src/dht_asym.c` timing and
memory paths. No `src/` or `bench/` file was edited by this worker. The
workspace changed during the audit; this report uses the current snapshot and
retains the completed quick-probe evidence below.

## Final verdict

| Check | Result |
|---|---|
| Timed interval contains input-dependent transform work | PASS |
| Setup and accounted plan storage reported separately | PASS, with scope caveat |
| CSV syntax/field counts | PASS for current rows |
| Deterministic, self-identifying inputs/results | FAIL |
| Documented final commands exercise one profile | FAIL |

Overall: **FAIL integrity gate / reproducible harness defect**. The benchmark
can produce parseable timing rows, but the rows are not sufficient to establish
bitwise/replayable results or a single final profile.

## Evidence

### Timing scope — pass

`bench/benchmark.c:104` generates the test vector before the setup timer.
`106–111` time only `dht_plan_create*`, and each measured interval at
`117–119` brackets exactly one `dht_apply(p, x, y)`. Warmups at `113–115` are
outside measured repetitions.

The current implementation performs the input-dependent stages inside
`dht_apply` (`src/dht_asym.c:369–388`): output initialization, the zero row,
weighted scratch fill, FFT execution, output assembly, and direct corrections.
Plan construction uses only size/profile/tolerance/thread arguments and builds
input-independent tables. Input generation and allocation are harness
preparation, not transform work, so excluding them is consistent with the
contract.

The completed warmup probe kept the reported output sample identical when
warmups changed from 0 to 3; only timing noise changed.

### Setup/memory — pass with explicit accounting caveat

The current CSV has separate `setup_s` and `plan_bytes` columns, and the
emitter fills them separately (`bench/run_winner.sh:8`,
`bench/benchmark.c:130–134`). `dht_plan_bytes()` (`src/dht_asym.c:397–405`)
counts the plan struct, row metadata, direct kernel, weights/scales,
coefficients, and reusable FFT scratch.

It excludes FFTW’s internal plan allocation and caller-owned input/output
arrays. Therefore `plan_bytes` must be reported as accounted reusable plan
storage, not peak RSS or total process memory. Current N=65536 rows report
`plan_bytes=64366816` for `(terms,cutoff,ratio)=(12,21,4)`.

### Seed/reproducibility — fail

Both harnesses use mutable file-scope RNG state initialized to
`0x8f3c2d1e7a6b5948` (`bench/benchmark.c:10`, `bench/accuracy.c:11`). There is
no seed argument, seed column, or input digest.

`run_winner.sh` launches a fresh process per case/size, so the random generator
is repeatable by process discipline. However, `accuracy.c` advances the same
stream while walking dense sizes and cases. Completed order probes using the
unchanged accuracy harness showed that changing `max_dense` from 32 to 64
changed the later N=1024 `large-rows-diagnostic` result from `1.4237e-15` to
`1.3856e-15`; repeated identical invocations were stable. Thus the random
vector is deterministic only as a function of the entire preceding test
order, not `(N, case)`.

The current CSV provides additional evidence against bitwise process
reproducibility: its two fresh-process `random,N=65536` rows use the same
profile/thread settings but report slightly different one-point samples
(`checksum_re` about `-2.05137420759426` versus `-2.0513742075942596`, and
different last bits in `checksum_im`). FFTW `MEASURE` plan selection and/or
parallel execution can therefore change floating-point results between runs.

Recommendation: derive/reset the seed from explicit `(base_seed,N,case)`, print
the seed and an input digest, and add a specified full-output digest. Preserve
the current one-process-per-row discipline only as a temporary workaround.

### CSV — syntax pass, integrity metadata fail

`sh -n bench/run_winner.sh` passed. The current `bench/results.csv` has 11 data
rows; an `awk -F,` check found 19 fields in the header and every data row, with
no field-count mismatch. The final `samples_s` field is quoted and contains
the expected semicolon-separated timings.

The fields named `checksum_re` and `checksum_im` are not checksums:
`bench/benchmark.c:130–134` emits only `y[n/3].re` and `y[n/3].im`. They cannot
detect an error in another output row. Relabel them as samples or add a full
vector hash (plus input hash, algorithm, and byte-order definition). The CSV
also records no compiler/flags, source or binary hash, FFTW version, host, or
seed, so it is not self-describing. `setup_s`, medians, and raw samples are
necessarily timing observations rather than exact reproducibility values.

### Command/profile consistency — fail

The current source and README retain `(12,21,4)`, and `run_winner.sh` now uses
that profile. But `make benchmark` still expands to:

```text
build/dht_benchmark 65536 31 5 1e-13 10 10 30 4 0
```

while `make verify` omits explicit profile arguments and therefore uses the
source default `(12,21,4)`. The documented `make verify benchmark` sequence
does not verify and benchmark one profile. Do not call it a final comparable
result until the Makefile target is aligned.

## Exact final recommendation

Use one explicit profile for both checks after the final accuracy decision. For
the current retained profile, the commands are:

```sh
make all
./build/dht_accuracy 65536 1e-13 10 12 21 512 4
LC_ALL=C ./build/dht_benchmark 65536 31 5 1e-13 10 12 21 4 0 csv
```

Run the benchmark command once per case (`0` through `4`) for the case sweep,
or use `./bench/run_winner.sh` after its output metadata and profile alignment
are finalized. The independent full-vector MPFR acceptance check remains
required by the repository contract; this report does not certify numerical
accuracy.

No further computation was run for this conclusion. The available workspace
has no `.git` metadata, so source identity was checked by paths/hashes rather
than `git diff`.
