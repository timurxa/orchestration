#include "../src/dht.h"

#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.141592653589793238462643383279502884
#endif

static int failures;

static void check(int condition, const char *label) {
    printf("%s: %s\n", condition ? "PASS" : "FAIL", label);
    if (!condition) {
        ++failures;
    }
}

static int same_complex(dht_complex a, dht_complex b) {
    return memcmp(&a, &b, sizeof(a)) == 0;
}

static void test_n1(void) {
    const dht_complex input = {3.25, -1.75};
    const double cutoffs[] = {21.0, 4.0};
    dht_plan *plans[3] = {
        dht_plan_create(1, 1e-13, 0),
        dht_plan_create_profile(1, 1e-13, 3, cutoffs[0], 1),
        dht_plan_create_profile_ex(1, 1e-13, 3, cutoffs[1], 1, 2),
    };
    for (size_t i = 0; i < sizeof(plans) / sizeof(plans[0]); ++i) {
        dht_complex output = {NAN, NAN};
        int ok = plans[i] != NULL && dht_apply(plans[i], &input, &output) == 0 &&
                 same_complex(input, output) && dht_size(plans[i]) == 1 &&
                 dht_direct_entries(plans[i]) == 0;
        check(ok, i == 0 ? "N=1 default plan" : "N=1 profile plan");
        dht_plan_destroy(plans[i]);
    }
}

static void test_small_accuracy(void) {
    const dht_complex input[] = {
        {0.75, -0.20}, {-1.25, 0.40}, {0.25, 2.00}, {1.50, -0.75},
    };
    for (size_t n = 2; n <= 3; ++n) {
        dht_complex output[3];
        dht_plan *plan = dht_plan_create(n, 1e-13, 1);
        int ok = plan != NULL &&
                 dht_apply(plan, input, output) == 0;
        double max_error = 0.0;
        if (ok) {
            for (size_t m = 0; m < n; ++m) {
                dht_complex expected = {0.0, 0.0};
                for (size_t k = 0; k < n; ++k) {
                    double kernel = j0((2.0 * M_PI * (double)m * (double)k) /
                                       (double)n);
                    expected.re += input[k].re * kernel;
                    expected.im += input[k].im * kernel;
                }
                max_error = fmax(max_error, hypot(output[m].re - expected.re,
                                                   output[m].im - expected.im));
            }
            ok = max_error <= 1e-13;
        }
        char label[64];
        snprintf(label, sizeof(label), "N=%zu/3 dense binary64 reference (max %.3e)",
                 n, max_error);
        check(ok, label);
        dht_plan_destroy(plan);
    }
}

static void test_nulls(void) {
    dht_complex x = {1.0, -2.0};
    dht_complex y = {0.0, 0.0};
    dht_plan *plan = dht_plan_create(3, 1e-13, 1);
    check(plan != NULL, "null-argument test plan creation");
    if (plan != NULL) {
        check(dht_apply(NULL, &x, &y) == -1, "dht_apply(NULL, x, y)");
        check(dht_apply(plan, NULL, &y) == -1, "dht_apply(plan, NULL, y)");
        check(dht_apply(plan, &x, NULL) == -1, "dht_apply(plan, x, NULL)");
    }
    dht_plan_destroy(plan);
    dht_plan_destroy(NULL);
    check(dht_size(NULL) == 0 && dht_asymptotic_terms(NULL) == 0 &&
              dht_direct_entries(NULL) == 0 && dht_plan_bytes(NULL) == 0 &&
              dht_block_ratio(NULL) == 0 && isnan(dht_tolerance(NULL)) &&
              isnan(dht_asymptotic_cutoff(NULL)),
          "null metadata getters and destroy");
}

static void test_invalid_profiles(void) {
    const double cutoffs[] = {NAN, INFINITY, -INFINITY, -1.0, 0.0};
    for (size_t i = 0; i < sizeof(cutoffs) / sizeof(cutoffs[0]); ++i) {
        dht_plan *plan = dht_plan_create_profile_ex(5, 1e-13, 1,
                                                     cutoffs[i], 1, 2);
        char label[80];
        snprintf(label, sizeof(label), "reject cutoff[%zu] (%g)", i, cutoffs[i]);
        check(plan == NULL, label);
        dht_plan_destroy(plan);
    }
}

static void test_oversized_inputs(void) {
    unsigned over_int = (unsigned)INT_MAX + 1u;
    check(dht_plan_create_profile_ex(3, 1e-13, over_int, 4.0, 1, 2) == NULL,
          "reject terms > INT_MAX");
    check(dht_plan_create_profile_ex(3, 1e-13, 1, 4.0, over_int, 2) == NULL,
          "reject threads > INT_MAX");
    check(dht_plan_create_profile_ex((size_t)INT32_MAX + 1u, 1e-13, 1,
                                     4.0, 1, 2) == NULL,
          "reject N > INT32_MAX");
}

static uint64_t hash_bytes(const void *data, size_t bytes) {
    const unsigned char *p = (const unsigned char *)data;
    uint64_t hash = UINT64_C(1469598103934665603);
    for (size_t i = 0; i < bytes; ++i) {
        hash ^= p[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static void test_repeated_apply(void) {
    const size_t n = 65;
    dht_complex *input = malloc(n * sizeof(*input));
    dht_complex *first = malloc(n * sizeof(*first));
    dht_complex *output = malloc(n * sizeof(*output));
    int ok = input != NULL && first != NULL && output != NULL;
    dht_plan *plan = NULL;
    if (ok) {
        for (size_t k = 0; k < n; ++k) {
            input[k].re = sin(0.17 * (double)k) + 0.01 * (double)k;
            input[k].im = cos(0.11 * (double)k) - 0.02 * (double)k;
        }
        plan = dht_plan_create_profile_ex(n, 1e-13, 10, 4.0, 3, 2);
        ok = plan != NULL;
        for (unsigned repeat = 0; ok && repeat < 4; ++repeat) {
            ok = dht_apply(plan, input, output) == 0;
            if (repeat == 0 && ok) {
                memcpy(first, output, n * sizeof(*first));
            } else if (ok) {
                ok = memcmp(first, output, n * sizeof(*first)) == 0;
            }
        }
    }
    printf("%s: deterministic repeated applies (hash=0x%016" PRIx64 ")\n",
           ok ? "PASS" : "FAIL", ok ? hash_bytes(first, n * sizeof(*first)) : 0);
    if (!ok) {
        ++failures;
    }
    dht_plan_destroy(plan);
    free(output);
    free(first);
    free(input);
}

int main(void) {
    test_n1();
    test_small_accuracy();
    test_nulls();
    test_invalid_profiles();
    test_oversized_inputs();
    test_repeated_apply();
    printf("SUMMARY: %s (%d failure%s)\n", failures == 0 ? "PASS" : "FAIL",
           failures, failures == 1 ? "" : "s");
    return failures == 0 ? 0 : 1;
}
