CC ?= clang
CFLAGS ?= -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic -I/opt/homebrew/include
LDFLAGS ?= -L/opt/homebrew/lib
LDLIBS ?= -lfftw3_threads -lfftw3 -lm

BUILD := build

.PHONY: all clean verify benchmark direct

all: $(BUILD)/dht_benchmark $(BUILD)/dht_accuracy $(BUILD)/dht_direct_benchmark

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/dht_asym.o: src/dht_asym.c src/dht.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/dht_benchmark: bench/benchmark.c $(BUILD)/dht_asym.o | $(BUILD)
	$(CC) $(CFLAGS) $^ $(LDFLAGS) $(LDLIBS) -o $@

$(BUILD)/dht_accuracy: bench/accuracy.c $(BUILD)/dht_asym.o | $(BUILD)
	$(CC) $(CFLAGS) $^ $(LDFLAGS) -lmpfr -lgmp $(LDLIBS) -o $@

$(BUILD)/dht_direct_benchmark: bench/direct_benchmark.c | $(BUILD)
	$(CC) $(CFLAGS) $< $(LDFLAGS) -lm -o $@

verify: $(BUILD)/dht_accuracy
	$(BUILD)/dht_accuracy 65536 1e-13 10

benchmark: $(BUILD)/dht_benchmark
	$(BUILD)/dht_benchmark 65536 31 5 1e-13 10 10 30 4 0

direct: $(BUILD)/dht_direct_benchmark
	$(BUILD)/dht_direct_benchmark 512 5 1

clean:
	rm -rf $(BUILD)
