# Worker 28 build fingerprint

Audit date: 2026-08-28. This is a filesystem/toolchain fingerprint; the
checkout has no usable .git metadata (git status --short --branch returned
fatal: not a git repository), so no commit ID is available.

## Scope and source hashes

The hash scope is the retained implementation, its forwarding wrapper, all
build/run sources, and the documented build/run inputs. research/**,
bench/results.csv, and unrelated historical binaries are excluded.

~~~text
SHA-256                                      path
d26404a71c88a617a00c0d6c8c1997c95d7128b4b57bb1331c0c7b0571370b46  Makefile
af80bb65a88cf2bbdb9028e0ee39c0d7cc951e6e1cd4566db325ca8d6016c8ea  README.md
cfecef2db88dfa84ac5863cba13dfc30fbda0b0cd155db6688808a0a337933c7  bench/README.md
ed36207269b7088e0e37434543f86becd45677913743a5bfecbb2087e5c1775a  bench/accuracy.c
f40df7df4cb2436c6d0e65d45cb68b3fe97d89979fb3667c447375b1c04a7882  bench/benchmark.c
7c381806ddf1491e80726d22b996a3b36ee85d94dcbe942e8c6f7cad671340ca  bench/direct_benchmark.c
8a5833c860cb2f3dcf548f8d0d5b70fab7131acced5a6bbfdb8ea5622bc77e6a  bench/run_winner.sh
3e838bac9b296773230063b75b8373a92e3c4459bd1b956d8d76c2d96d30fbbb  src/dht.h
e3c2121597a297dc3ba54987dfae5ea3300deb81da07a8d40e634f1f14a39354  src/dht_asym.c
e5c6415e39ee34bd7ffada6d01d74a02fee430254acdd4279e2553861a94e165  best/dht.h
5b63d5bb2fb7d523461869313ce271b352b5b9f3bb3e68c27ee7518a3bf4823c  best/dht_asym.c
~~~

The existing build outputs were also fingerprinted:

~~~text
90730776717c8a38badde3d9c6d4317d6b13d61303d6f2f37ba867a35b089657  build/dht_asym.o
aaae8961712e305af98d81648d1cc2b393107ddcbd9c960a7f5d35714890e109  build/dht_accuracy
dc17bfe2380e181a887cdbfe0a3367d09d9f71ee07330529b521df93d74d2bca  build/dht_benchmark
c51b03e29613b6a62d1c8c9c1c4e2d46a738adedde55684822d61f59f901b21e  build/dht_direct_benchmark
~~~

## Toolchain and dependency versions

~~~text
$ command -v clang
/usr/bin/clang

$ clang --version | head -n 3
Apple clang version 21.0.0 (clang-2100.1.1.101)
Target: arm64-apple-darwin25.5.0
Thread model: posix

$ pkg-config --modversion fftw3
3.3.10
$ pkg-config --modversion mpfr
4.2.2
$ pkg-config --modversion gmp
6.3.0

$ /opt/homebrew/bin/brew list --versions fftw mpfr gmp
fftw 3.3.10_3
gmp 6.3.0
mpfr 4.2.2
~~~

The Makefile uses -I/opt/homebrew/include, -L/opt/homebrew/lib,
-lfftw3_threads -lfftw3 -lmpfr -lgmp -lm, and Apple Grand Central Dispatch.

## Reproducibility evidence

Commands were run from the repository root.

~~~text
$ make all
make: Nothing to be done for 'all'.
[exit_code=0]
~~~

This confirms that the existing final artifacts satisfy the Make dependency
graph; it does not claim that this audit performed a clean rebuild.

~~~text
$ make verify
build/dht_accuracy 65536 1e-13 10
dense N=32 case=0 terms=10 z0=30.0 direct=609 rel_l2=1.0459e-15 scaled_linf=9.7243e-16 PASS
dense N=32 case=1 terms=10 z0=30.0 direct=609 rel_l2=1.0110e-15 scaled_linf=8.2793e-16 PASS
dense N=32 case=2 terms=10 z0=30.0 direct=609 rel_l2=2.5470e-16 scaled_linf=1.1634e-16 PASS
dense N=32 case=3 terms=10 z0=30.0 direct=609 rel_l2=1.3587e-15 scaled_linf=2.0509e-15 PASS
dense N=32 case=4 terms=10 z0=30.0 direct=609 rel_l2=1.2367e-15 scaled_linf=6.4385e-16 PASS
dense N=64 case=0 terms=10 z0=30.0 direct=1857 rel_l2=1.5642e-15 scaled_linf=1.1990e-15 PASS
dense N=64 case=1 terms=10 z0=30.0 direct=1857 rel_l2=8.2587e-16 scaled_linf=7.8667e-16 PASS
dense N=64 case=2 terms=10 z0=30.0 direct=1857 rel_l2=2.0251e-16 scaled_linf=9.6377e-17 PASS
dense N=64 case=3 terms=10 z0=30.0 direct=1857 rel_l2=1.7696e-15 scaled_linf=2.8086e-15 PASS
dense N=64 case=4 terms=10 z0=30.0 direct=1857 rel_l2=1.5965e-15 scaled_linf=1.0505e-15 PASS
dense N=128 case=0 terms=10 z0=30.0 direct=4305 rel_l2=2.8378e-15 scaled_linf=3.5766e-15 PASS
dense N=128 case=1 terms=10 z0=30.0 direct=4305 rel_l2=6.8478e-16 scaled_linf=6.2480e-16 PASS
dense N=128 case=2 terms=10 z0=30.0 direct=4305 rel_l2=1.6424e-16 scaled_linf=8.0911e-17 PASS
dense N=128 case=3 terms=10 z0=30.0 direct=4305 rel_l2=2.9654e-15 scaled_linf=9.1671e-15 PASS
dense N=128 case=4 terms=10 z0=30.0 direct=4305 rel_l2=2.5072e-15 scaled_linf=1.7414e-15 PASS
dense N=256 case=0 terms=10 z0=30.0 direct=11121 rel_l2=1.5667e-15 scaled_linf=1.7558e-15 PASS
dense N=256 case=1 terms=10 z0=30.0 direct=11121 rel_l2=6.0084e-16 scaled_linf=5.0487e-16 PASS
dense N=256 case=2 terms=10 z0=30.0 direct=11121 rel_l2=1.3268e-16 scaled_linf=6.8912e-17 PASS
dense N=256 case=3 terms=10 z0=30.0 direct=11121 rel_l2=1.8996e-15 scaled_linf=4.2783e-15 PASS
dense N=256 case=4 terms=10 z0=30.0 direct=11121 rel_l2=1.9623e-15 scaled_linf=1.6436e-15 PASS
dense N=512 case=0 terms=10 z0=30.0 direct=24561 rel_l2=2.1360e-15 scaled_linf=2.7059e-15 PASS
dense N=512 case=1 terms=10 z0=30.0 direct=24561 rel_l2=5.7279e-16 scaled_linf=4.4317e-16 PASS
dense N=512 case=2 terms=10 z0=30.0 direct=24561 rel_l2=1.1667e-16 scaled_linf=6.3699e-17 PASS
dense N=512 case=3 terms=10 z0=30.0 direct=24561 rel_l2=2.3494e-15 scaled_linf=9.0584e-15 PASS
dense N=512 case=4 terms=10 z0=30.0 direct=24561 rel_l2=2.4228e-15 scaled_linf=2.2831e-15 PASS
large-rows-diagnostic N=65536 terms=10 z0=30.0 direct=6603633 max_row_rel=8.3716e-15 DIAGNOSTIC_PASS
delta-full N=65536 at=1 terms=10 z0=30.0 direct=6603633 rel_l2=1.6267e-16 scaled_linf=2.7990e-16 PASS
delta-full N=65536 at=65535 terms=10 z0=30.0 direct=6603633 rel_l2=1.1401e-15 scaled_linf=7.9047e-16 PASS
[exit_code=0]
~~~

All completed correctness values are below the stated rel_l2 <= 1e-13
and scaled_linf <= 1e-12 gate.

~~~text
$ make benchmark
build/dht_benchmark 65536 31 5 1e-13 10 10 30 4 0
N=65536 case=random reps=31 warmups=5 threads=10 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=6603633 setup_s=0.723012 median_s=0.016998 min_s=0.014093 max_s=0.031081 plan_bytes=74849448 seed=0x02de8669e7ffa0d2 input_hash=0x941d7106a171047d output_hash=0x002e9ec9482db281 sample=-0.23627552361868714,0.59930337544306134 samples=0.019729000;0.019164000;0.018175000;0.030273000;0.031081000;0.026765000;0.018674000;0.019684000;0.016527000;0.020543000;0.023947000;0.019814000;0.022557000;0.016403000;0.017512000;0.014951000;0.014428000;0.016729000;0.016421000;0.014665000;0.014678000;0.014093000;0.014205000;0.014254000;0.016998000;0.015158000;0.014183000;0.014514000;0.014164000;0.018842000;0.017092000
[exit_code=0]
~~~

## Not completed in this audit

The README extended command
./build/dht_accuracy 65536 1e-13 10 12 21 512 4 was started but interrupted
before it emitted a result. ./bench/run_winner.sh was not started. No
pass/fail claim is made for either command.

## Deployment caveat

This build is host-specific: it targets Apple arm64, includes Apple Grand
Central Dispatch, and assumes Homebrew dependencies under /opt/homebrew
(FFTW 3.3.10_3, MPFR 4.2.2, GMP 6.3.0). Reproduce on a matching Apple
Silicon/macOS/Homebrew environment, or revise the include and library paths
and platform threading implementation before deployment. FFTW MEASURE
planning and wall-clock timings are environment-dependent even when the
source and binary hashes match.
