FSTAR ?= fstar.exe
BUILD_DIR ?= /tmp/fstar-v1-check
SOURCE_DIR := src

MODULES := \
	Base \
	Protocol \
	Artifacts \
	Operations \
	Work \
	Expansion \
	JournalTypes \
	OperationFacts \
	JournalFacts \
	Contracts \
	Admission \
	Budget \
	Reducer \
	Recovery \
	Storage \
	Actions \
	Theorems \
	Targets

.PHONY: verify
verify:
	@mkdir -p "$(BUILD_DIR)"
	@set -eu; for module in $(MODULES); do \
		$(FSTAR) --cache_off --include "$(SOURCE_DIR)" \
			--include "$(BUILD_DIR)" --odir "$(BUILD_DIR)" \
			"$(SOURCE_DIR)/WorkflowV1/$$module.fst"; \
	done
