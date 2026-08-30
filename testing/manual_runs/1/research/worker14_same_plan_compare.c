#include "../src/dht.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int worker14_apply_serial_reference(const dht_plan *, const dht_complex *,
                                    dht_complex *);

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
    if (n < 2) return 2;
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *serial = (dht_complex *)malloc(n * sizeof(*serial));
    dht_complex *parallel = (dht_complex *)malloc(n * sizeof(*parallel));
    if (x == NULL || serial == NULL || parallel == NULL) return 2;
    fill_input(x, n);
    dht_plan *p = dht_plan_create_profile_ex(n, 1e-13, 10, 64.0, threads, 2);
    if (p == NULL || worker14_apply_serial_reference(p, x, serial) != 0 ||
        dht_apply(p, x, parallel) != 0) {
        dht_plan_destroy(p);
        free(parallel); free(serial); free(x);
        return 2;
    }
    size_t byte_mismatches = 0;
    double max_abs = 0.0;
    for (size_t m = 0; m < n; ++m) {
        if (memcmp(&serial[m], &parallel[m], sizeof(serial[m])) != 0) {
            ++byte_mismatches;
        }
        max_abs = fmax(max_abs, hypot(serial[m].re - parallel[m].re,
                                      serial[m].im - parallel[m].im));
    }
    printf("N=%zu threads=%u direct=%zu byte_mismatched_rows=%zu max_abs=%.17g "
           "serial_hash=0x%016" PRIx64 " parallel_hash=0x%016" PRIx64 "\n",
           n, threads, dht_direct_entries(p), byte_mismatches, max_abs,
           hash_bytes(serial, n * sizeof(*serial)),
           hash_bytes(parallel, n * sizeof(*parallel)));
    dht_plan_destroy(p);
    free(parallel); free(serial); free(x);
    return byte_mismatches == 0 ? 0 : 1;
}
