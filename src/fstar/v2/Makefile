FSTAR ?= fstar.exe
BUILD_DIR ?= /tmp/fstar-v2-check
SOURCE_DIR := src
FSTAR_FLAGS ?= --cache_off --warn_error @285

MODULES := WorkflowV2.Kernel WorkflowV2.GraphCodec WorkflowV2.Identity WorkflowV2.Graph WorkflowV2.GenerationExample WorkflowV2.ChainProof WorkflowV2.Journal
SOURCES := $(addsuffix .fst,$(addprefix $(SOURCE_DIR)/,$(MODULES)))

.PHONY: verify
verify:
	@mkdir -p "$(BUILD_DIR)"
	$(FSTAR) $(FSTAR_FLAGS) --include "$(SOURCE_DIR)" \
		--include "$(BUILD_DIR)" --odir "$(BUILD_DIR)" $(SOURCES)
