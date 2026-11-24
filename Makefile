# bitten: Mach-O loader + Darwin compatibility layer for Linux x86-64.
CC      ?= cc
CFLAGS  ?= -O2 -g
CFLAGS  += -std=gnu17 -Wall -Wextra -Wno-unused-parameter -fno-strict-aliasing \
           -fno-omit-frame-pointer -Isrc/include -pthread
LDLIBS  := -lm -ldl -lresolv -lutil
# The Mach-O main executable prefers its linked address (0x100000000), so
# keep the loader itself out of the low 4 GiB+ range: a normal PIE lands high.
LDFLAGS += -pie -rdynamic -pthread

BUILD   ?= build
# EXCLUDE=path/to/file.c leaves a source out (useful while one is in flux).
SRCS := $(filter-out $(EXCLUDE),$(wildcard src/loader/*.c src/libsystem/*.c src/frameworks/*/*.c))
ASMS := $(wildcard src/loader/*.S)
OBJS := $(patsubst src/%.c,$(BUILD)/obj/%.o,$(SRCS)) $(patsubst src/%.S,$(BUILD)/obj/%.o,$(ASMS))

all: $(BUILD)/mrun

$(BUILD)/mrun: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

$(BUILD)/obj/%.o: src/%.c $(wildcard src/include/*.h)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -fPIE -c -o $@ $<

$(BUILD)/obj/%.o: src/%.S
	@mkdir -p $(dir $@)
	$(CC) -c -o $@ $<

# ---- tests ---------------------------------------------------------------
# C tests are compiled to real Mach-O with clang + ld64.lld against a stub
# libSystem generated from the symbols bitten implements. No Apple SDK.
TEST_C    := $(wildcard tests/c/*.c)
TEST_BINS := $(patsubst tests/c/%.c,$(BUILD)/tests/c/%,$(TEST_C))
MACHO_CC  ?= clang
# Debian and Ubuntu keep ld64.lld in a versioned LLVM directory.
MACHO_LD  ?= $(or $(shell command -v ld64.lld 2>/dev/null),$(lastword $(sort $(wildcard /usr/lib/llvm-*/bin/ld64.lld))),ld64.lld)

$(BUILD)/tests/sdk/libSystem.tbd: $(BUILD)/mrun tools/gen-tbd.sh
	@mkdir -p $(dir $@)
	tools/gen-tbd.sh $(BUILD)/mrun > $@

$(BUILD)/tests/c/%: tests/c/%.c $(BUILD)/tests/sdk/libSystem.tbd tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -nostdinc \
	    -Itests/include -fno-stack-protector -c -o $@.o $<
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/tests/sdk -lSystem -o $@ $@.o

# Go tests: real darwin/amd64 binaries from the Go toolchain's own linker.
# They are built when a Go toolchain is available (GO=...), otherwise skipped.
GO ?= go
TEST_GO     := $(wildcard tests/go/*/main.go)
TEST_GOBINS := $(if $(shell command -v $(GO) 2>/dev/null),$(patsubst tests/go/%/main.go,$(BUILD)/tests/go/%,$(TEST_GO)))

$(BUILD)/tests/go/%: tests/go/%/main.go tests/go/go.mod
	@mkdir -p $(dir $@)
	cd tests/go && GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-buildvcs=false \
	    $(GO) build -o $(abspath $@) ./$*

test-bins: $(TEST_BINS) $(TEST_GOBINS)

check: $(BUILD)/mrun $(TEST_BINS) $(TEST_GOBINS)
	BUILD=$(BUILD) tests/run.sh

check-dmgx:
	python3 -m unittest discover -s tests/dmgx

clean:
	rm -rf $(BUILD)

.PHONY: all clean check check-dmgx test-bins
