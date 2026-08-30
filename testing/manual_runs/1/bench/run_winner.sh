#!/bin/sh
set -eu
export LC_ALL=C

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
make -C "$root" all

results="$root/bench/results.csv"
printf '%s\n' 'candidate,case,N,reps,warmups,threads,block_ratio,tol,terms,z0,direct_entries,setup_s,median_s,min_s,max_s,plan_bytes,seed,input_hash,output_hash,sample_re,sample_im,samples_s' > "$results"

for kind in 0 1 2 3 4
do
    "$root/build/dht_benchmark" 65536 101 10 1e-13 10 10 30 4 "$kind" csv >> "$results"
done

for profile in "12 21" "11 23" "10 30" "10 40" "12 22"
do
    set -- $profile
    "$root/build/dht_benchmark" 65536 51 7 1e-13 10 "$1" "$2" 4 0 csv >> "$results"
done

for n in 4096 8192 16384 32768 65536 131072
do
    "$root/build/dht_benchmark" "$n" 11 3 1e-13 10 10 30 4 0 csv >> "$results"
done
