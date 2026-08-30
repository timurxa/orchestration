#include "../src/dht.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint64_t rng_state = UINT64_C(0x8f3c2d1e7a6b5948);
static const uint64_t base_seed = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t mix_seed(uint64_t z) {
    z = (z ^ (z >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94d049bb133111eb);
    return z ^ (z >> 31);
}

static uint64_t input_seed(size_t n, unsigned kind) {
    return mix_seed(base_seed ^ (uint64_t)n * UINT64_C(0x9e3779b97f4a7c15) ^
                    (uint64_t)(kind + 1u) * UINT64_C(0xd1b54a32d192ed03));
}

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

static void fill_input(dht_complex *x, size_t n, unsigned kind) {
    rng_state = input_seed(n, kind);
    for (size_t k = 0; k < n; ++k) {
        double t = (double)k / (double)n;
        if (kind == 0) {
            x[k].re = uniform_signed();
            x[k].im = uniform_signed();
        } else if (kind == 1) {
            double u = (t - 0.37) / 0.07;
            double g = exp(-0.5 * u * u);
            x[k].re = g;
            x[k].im = -0.7 * g;
        } else if (kind == 2) {
            double u = (t - 0.61) / 0.17;
            double bump = fabs(u) < 1.0 ? exp(-1.0 / (1.0 - u * u)) : 0.0;
            x[k].re = bump;
            x[k].im = sin(37.0 * t) * bump;
        } else if (kind == 3) {
            x[k].re = sin(2.0 * M_PI * (0.125 * k + 0.00031 * k * k));
            x[k].im = cos(2.0 * M_PI * (0.237 * k - 0.00017 * k * k));
        } else {
            double exponent = -12.0 + 24.0 * t;
            double magnitude = pow(10.0, exponent);
            double sign = (k & 1u) ? -1.0 : 1.0;
            x[k].re = sign * magnitude;
            x[k].im = -sign * magnitude * (0.25 + 0.5 * t);
        }
    }
}

static uint64_t digest_complex(const dht_complex *a, size_t n) {
    uint64_t h = UINT64_C(0xcbf29ce484222325);
    for (size_t k = 0; k < n; ++k) {
        uint64_t bits[2];
        memcpy(&bits[0], &a[k].re, sizeof(bits[0]));
        memcpy(&bits[1], &a[k].im, sizeof(bits[1]));
        for (unsigned j = 0; j < 2; ++j) {
            for (unsigned b = 0; b < 8; ++b) {
                h ^= (bits[j] >> (8u * b)) & UINT64_C(0xff);
                h *= UINT64_C(0x100000001b3);
            }
        }
    }
    return h;
}

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

static double median(double *a, unsigned n) {
    for (unsigned i = 1; i < n; ++i) {
        double v = a[i];
        unsigned j = i;
        while (j > 0 && a[j - 1] > v) {
            a[j] = a[j - 1];
            --j;
        }
        a[j] = v;
    }
    return a[n / 2];
}

static const char *case_name(unsigned kind) {
    static const char *names[] = {
        "random", "gaussian", "compact_bump", "oscillatory", "dynamic"
    };
    return kind < sizeof(names) / sizeof(names[0]) ? names[kind] : "unknown";
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 9;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 2;
    double tol = argc > 4 ? strtod(argv[4], NULL) : 1e-13;
    unsigned threads = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 1;
    unsigned terms = argc > 6 ? (unsigned)strtoul(argv[6], NULL, 10) : 0;
    double cutoff = argc > 7 ? strtod(argv[7], NULL) : 0.0;
    unsigned block_ratio = argc > 8 ? (unsigned)strtoul(argv[8], NULL, 10) : 2;
    unsigned kind = 0;
    int csv = 0;
    for (int i = 9; i < argc; ++i) {
        if (strcmp(argv[i], "csv") == 0) {
            csv = 1;
        } else {
            kind = (unsigned)strtoul(argv[i], NULL, 10);
        }
    }
    if (reps == 0) return 2;

    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    double *times = (double *)malloc(reps * sizeof(*times));
    if (x == NULL || y == NULL || times == NULL) return 2;
    fill_input(x, n, kind);
    uint64_t seed = input_seed(n, kind);
    uint64_t input_hash = digest_complex(x, n);

    double t0 = now_seconds();
    dht_plan *p = terms > 0 && cutoff > 0.0
                      ? dht_plan_create_profile_ex(n, tol, terms, cutoff,
                                                   threads, block_ratio)
                      : dht_plan_create(n, tol, threads);
    double setup = now_seconds() - t0;
    if (p == NULL) return 2;
    for (unsigned i = 0; i < warmups; ++i) {
        if (dht_apply(p, x, y) != 0) return 2;
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        if (dht_apply(p, x, y) != 0) return 2;
        times[i] = now_seconds() - begin;
    }
    uint64_t output_hash = digest_complex(y, n);
    double *copy = (double *)malloc(reps * sizeof(*copy));
    memcpy(copy, times, reps * sizeof(*copy));
    double med = median(copy, reps);
    double min = times[0], max = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min) min = times[i];
        if (times[i] > max) max = times[i];
    }
    if (csv) {
        printf("blocked_asym_fft,%s,%zu,%u,%u,%u,%u,%.17g,%u,%.17g,%zu,%.9f,%.9f,%.9f,%.9f,%zu,0x%016" PRIx64 ",0x%016" PRIx64 ",0x%016" PRIx64 ",%.17g,%.17g,\"",
               case_name(kind), n, reps, warmups, threads, dht_block_ratio(p),
               tol, dht_asymptotic_terms(p), dht_asymptotic_cutoff(p),
               dht_direct_entries(p), setup, med, min, max, dht_plan_bytes(p),
               seed, input_hash, output_hash, y[n / 3].re, y[n / 3].im);
        for (unsigned i = 0; i < reps; ++i) {
            printf("%.9f%s", times[i], i + 1 == reps ? "" : ";");
        }
        putchar('"');
        putchar('\n');
    } else {
        printf("N=%zu case=%s reps=%u warmups=%u threads=%u ratio=%u tol=%.3e terms=%u z0=%.1f direct=%zu setup_s=%.6f median_s=%.6f min_s=%.6f max_s=%.6f plan_bytes=%zu seed=0x%016" PRIx64 " input_hash=0x%016" PRIx64 " output_hash=0x%016" PRIx64 " sample=%.17g,%.17g samples=",
               n, case_name(kind), reps, warmups, threads, dht_block_ratio(p),
               tol, dht_asymptotic_terms(p), dht_asymptotic_cutoff(p),
               dht_direct_entries(p), setup, med, min, max, dht_plan_bytes(p),
               seed, input_hash, output_hash, y[n / 3].re, y[n / 3].im);
        for (unsigned i = 0; i < reps; ++i) {
            printf("%.9f%s", times[i], i + 1 == reps ? "" : ";");
        }
        putchar('\n');
    }
    dht_plan_destroy(p);
    free(copy); free(times); free(y); free(x);
    return 0;
}
