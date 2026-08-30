# Release-artifact review: actionable gaps

- **Define the stable API boundary.** `best/README.md:4-14` points users to `src/dht.h` and recommends `dht_plan_create_profile_ex`, while `src/dht.h:21-27` labels only `dht_plan_create_profile` experimental. Explicitly mark the supported release functions (and any stable query accessors), classify/remove both profile constructors and profile introspection if benchmark-only, and state source/ABI compatibility.

- **Fix the “standalone source pair” claim.** `best/dht.h:4` and `best/dht_asym.c:2` require `../src`, and the Makefile builds `src` directly. Either make `best/` self-contained or document the repo-relative dependency and provide the exact consumer compile/include command.

- **Resolve the profile/accuracy-command conflict.** `README.md:9-24` and `best/README.md:12-14` select `terms=10`, `cutoff=30`, `block_ratio=4`, but the README’s explicit accuracy command passes profile `12/21` (`bench/accuracy.c:293-296`); `make verify` uses the default `10/30/4`. Make the explicit command test the release profile, or label `12/21` as a comparison profile, and document the positional arguments.

- **Align the release gate with the stated large-N acceptance target.** `make verify` performs strict full-vector checks only for two large-N delta inputs; the general complex large-N case checks nine rows at the relaxed `1e-11` diagnostic threshold (`bench/accuracy.c:221-255`). Add a strict MPFR full-vector check for the release input at `N=65536`, or explicitly narrow the documented claim and label this as diagnostic coverage.

- **Document the actual platform/dependency contract.** The README names Apple clang, FFTW 3, and MPFR/GMP under `/opt/homebrew`, but `src/dht_asym.c` also requires libdispatch and threaded FFTW (`dispatch/dispatch.h`, `-lfftw3_threads`), while only the accuracy target needs MPFR/GMP. State supported OS/architecture, exact package names, required headers/libraries, and supported include/library-path overrides; the Makefile currently hard-codes Homebrew paths.

- **Add reproducible CLI usage and output semantics.** `bench/README.md:5` documents only the case-number/final-`csv` convention. Provide argument maps and canonical examples for `dht_accuracy` and `dht_benchmark`, distinguish the one-case `make benchmark` target from the full `bench/run_winner.sh` sweep, and state which PASS/diagnostic lines and thresholds constitute success.

- **State the tolerance/profile guarantee.** The public comment says `tol` controls the profile, but the implementation has only hard-coded default branches (`src/dht_asym.c:44-51`) and explicit profile constructors accept arbitrary values. Document that the `1e-13` guarantee applies only to the validated release profile (and identify behavior outside it), rather than implying a general tolerance guarantee.
