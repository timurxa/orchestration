#ifndef DHT_H
#define DHT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double re;
    double im;
} dht_complex;

typedef struct dht_plan dht_plan;

/* Create a reusable plan for the direct-grid order-0 transform (n >= 1).
 * tol must be finite and positive and selects a built-in asymptotic profile;
 * the 1e-13 accuracy evidence in this repository is for the release profile
 * selected by tol=1e-13. threads is the FFTW worker count (0 selects one). */
dht_plan *dht_plan_create(size_t n, double tol, unsigned threads);
/* Experimental profile constructors used by the benchmark harness. They let
 * the search compare asymptotic term/cutoff pairs; their tol value is metadata
 * and does not constitute a formal accuracy guarantee. */
dht_plan *dht_plan_create_profile(size_t n, double tol, unsigned terms,
                                   double cutoff, unsigned threads);
dht_plan *dht_plan_create_profile_ex(size_t n, double tol, unsigned terms,
                                      double cutoff, unsigned threads,
                                      unsigned block_ratio);
void dht_plan_destroy(dht_plan *plan);

/* y[m] = sum_{k=0}^{n-1} x[k] J0(2*pi*m*k/n), m=0..n-1.
 * x and y must not overlap. A plan may be reused sequentially, but
 * concurrent dht_apply calls on the same plan are not supported. */
int dht_apply(const dht_plan *plan, const dht_complex *x, dht_complex *y);

size_t dht_size(const dht_plan *plan);
double dht_tolerance(const dht_plan *plan);
unsigned dht_asymptotic_terms(const dht_plan *plan);
double dht_asymptotic_cutoff(const dht_plan *plan);
size_t dht_direct_entries(const dht_plan *plan);
size_t dht_plan_bytes(const dht_plan *plan);
unsigned dht_block_ratio(const dht_plan *plan);

#ifdef __cplusplus
}
#endif

#endif
