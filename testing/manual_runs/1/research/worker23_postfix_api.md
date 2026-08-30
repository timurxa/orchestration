# Worker 23 — post-fix API regression

Date: 2026-08-28

Status: **PASS** for the requested worker 17 API and harness regressions.
No production files under `src/` or `bench/` were edited.  The research-only
probe is `research/worker23_postfix_api.c`.

## Build

Exact command:

```sh
make -B all
```

Result: **PASS**, exit 0.  The compiler emitted only deployment-target/dylib
warnings while rebuilding `build/dht_asym.o`, `build/dht_benchmark`,
`build/dht_accuracy`, and `build/dht_direct_benchmark`.

## API probe

Exact commands:

```sh
cc -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic -I/opt/homebrew/include research/worker23_postfix_api.c build/dht_asym.o -L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm -o build/worker23_postfix_api
./build/worker23_postfix_api
```

Result: **PASS**, exit 0; `SUMMARY: PASS (0 failures)`.

The probe covered:

- `N=1` through the default, profile, and extended-profile constructors; the
  output was exactly the input and direct-entry count was zero.
- `N=2` and `N=3` against a dense binary64 `j0` reference; maximum absolute
  complex errors were `0.000e+00` and `5.551e-17`.
- Null `dht_apply` plan/input/output arguments, null metadata getters, and
  `dht_plan_destroy(NULL)`.
- `NaN`, `+Inf`, `-Inf`, `-1`, and `0` cutoff rejection.
- `terms > INT_MAX`, `threads > INT_MAX`, and `N > INT32_MAX` rejection.
- Four repeated applies on one plan; bytewise output was stable with hash
  `0x157aa684d34b988d`.

## Undefined-behavior regression

Exact commands:

```sh
cc -fsanitize=undefined -fno-sanitize-recover=undefined -O1 -g -std=c11 -Wall -Wextra -Wpedantic -I/opt/homebrew/include -c src/dht_asym.c -o build/worker23_dht_asym_ubsan.o
cc -fsanitize=undefined -fno-sanitize-recover=undefined -O1 -g -std=c11 -Wall -Wextra -Wpedantic -I/opt/homebrew/include research/worker23_postfix_api.c build/worker23_dht_asym_ubsan.o -L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm -o build/worker23_postfix_api_ubsan
./build/worker23_postfix_api_ubsan
```

Result: **PASS**, exit 0; all probe checks passed and no UBSan diagnostic was
reported.  In particular, nonfinite cutoffs were rejected during plan
creation, before the previous overflowing cast could be reached.

## Full accuracy verification

Exact command:

```sh
make verify
```

Result: **PASS**, exit 0.  All dense cases from `N=32` through `N=512`, the
`N=65536` large-row diagnostic, and both full delta checks printed `PASS` or
`DIAGNOSTIC_PASS`.  The largest dense normalized L2 shown was `5.5634e-15`,
and the largest dense scaled Linf shown was `1.8104e-14`.

## Intentionally failing accuracy profile

Exact command:

```sh
./build/dht_accuracy 32 1e-13 1 1 1 32 2; rc=$?; printf 'accuracy_intentionally_failing_profile_rc=%d\n' "$rc"; exit "$rc"
```

Observed output included:

```text
dense N=32 case=0 terms=1 z0=1.0 direct=13 rel_l2=1.8187e-02 scaled_linf=1.6291e-02 FAIL
accuracy_intentionally_failing_profile_rc=2
```

Result: **PASS** as a negative test.  The executable now returns nonzero
(exit 2) when the accuracy gate fails; the prior false-green behavior is
resolved.

## Conclusion

The requested worker 17 regressions are resolved: `N=1` works, small sizes
and null handling pass, invalid cutoffs and oversized terms/threads are
rejected safely, repeated application is deterministic, and the accuracy
harness both builds and propagates an intentionally failing profile.
