AS := as
LD := ld
ASFLAGS := --64 -g -I src
SRCS := $(wildcard src/*.s)
OBJS := $(patsubst src/%.s,build/%.o,$(SRCS))

build/prettier-asm: $(OBJS)
	$(LD) -static -o $@ $(OBJS)

build/%.o: src/%.s src/defs.inc $(wildcard src/*.inc) | build
	$(AS) $(ASFLAGS) -o $@ $<

build:
	mkdir -p build

test: build/prettier-asm
	node tests/stage1/run.mjs
	@if [ -f corpus/cases/json.jsonl ]; then node tests/harness.mjs build/prettier-asm json; fi

# Records every measurement into results/data/, then writes RESULTS.md and results/charts/.
# RECORD_FLAGS passes flags to bench/record.mjs, for example RECORD_FLAGS="--reps 3 --force".
results: build/prettier-asm
	node bench/record.mjs $(RECORD_FLAGS)
	node bench/report.mjs

clean:
	rm -rf build

.PHONY: test results clean
