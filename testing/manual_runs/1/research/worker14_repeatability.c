#include "../src/dht.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t next_u64(void) {
    uint64_t x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static double uniform_signed(void) {
    return 2.0 * (double)(next_u64() >> 11) * 0x1.0p-53 - 1.0;
}

static void fill_input(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = uniform_signed();
        x[k].im = uniform_signed();
    }
}

static uint64_t hash_bytes(const void *data, size_t bytes) {
    const unsigned char *p = (const unsigned char *)data;
    uint64_t h = UINT64_C(1469598103934665603);
    for (size_t i = 0; i < bytes; ++i) {
        h ^= p[i];
        h *= UINT64_C(1099511628211);
    }
    return h;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned threads = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 10;
    unsigned cycles = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 3;
    unsigned repeats = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 5;
    if (n < 2 || cycles == 0 || repeats == 0) return 2;

    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    dht_complex *first = (dht_complex *)malloc(n * sizeof(*first));
    if (x == NULL || y == NULL || first == NULL) return 2;
    fill_input(x, n);

    uint64_t reference_hash = 0;
    size_t repeat_mismatches = 0;
    size_t cycle_mismatches = 0;
    size_t direct = 0;
    size_t plan_bytes = 0;
    for (unsigned cycle = 0; cycle < cycles; ++cycle) {
        dht_plan *p = dht_plan_create_profile_ex(n, 1e-13, 10, 64.0,
                                                  threads, 2);
        if (p == NULL) return 2;
        direct = dht_direct_entries(p);
        plan_bytes = dht_plan_bytes(p);
        uint64_t cycle_hash = 0;
        for (unsigned repeat = 0; repeat < repeats; ++repeat) {
            if (dht_apply(p, x, y) != 0) return 2;
            uint64_t h = hash_bytes(y, n * sizeof(*y));
            if (repeat == 0) {
                cycle_hash = h;
                memcpy(first, y, n * sizeof(*first));
            } else if (h != cycle_hash ||
                       memcmp(first, y, n * sizeof(*first)) != 0) {
                ++repeat_mismatches;
            }
        }
        if (cycle == 0) {
            reference_hash = cycle_hash;
        } else if (cycle_hash != reference_hash) {
            ++cycle_mismatches;
        }
        dht_plan_destroy(p);
    }
    printf("N=%zu threads=%u cycles=%u repeats=%u direct=%zu plan_bytes=%zu "
           "repeat_mismatches=%zu cycle_mismatches=%zu hash=0x%016" PRIx64
           "\n",
           n, threads, cycles, repeats, direct, plan_bytes, repeat_mismatches,
           cycle_mismatches, reference_hash);
    free(first);
    free(y);
    free(x);
    return repeat_mismatches == 0 && cycle_mismatches == 0 ? 0 : 1;
}
