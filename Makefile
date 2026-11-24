# dmgbox: Mach-O loader + Darwin compatibility layer for Linux x86-64.
CC      ?= cc
CFLAGS  ?= -O2 -g
CFLAGS  += -std=gnu17 -Wall -Wextra -Wno-unused-parameter -fno-strict-aliasing \
           -fno-omit-frame-pointer -Isrc/include -pthread
LDLIBS  := -lm -ldl -lresolv -lutil
# The Mach-O main executable prefers its linked address (0x100000000), so
# keep the loader itself out of the low 4 GiB+ range: a normal PIE lands high.
LDFLAGS += -pie -rdynamic -pthread

SRCS := $(wildcard src/loader/*.c src/libsystem/*.c src/frameworks/*/*.c)
ASMS := $(wildcard src/loader/*.S)
OBJS := $(patsubst src/%.c,build/obj/%.o,$(SRCS)) $(patsubst src/%.S,build/obj/%.o,$(ASMS))

all: build/mrun

build/mrun: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

build/obj/%.o: src/%.c $(wildcard src/include/*.h)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -fPIE -c -o $@ $<

build/obj/%.o: src/%.S
	@mkdir -p $(dir $@)
	$(CC) -c -o $@ $<

# ---- tests ---------------------------------------------------------------
# C tests are compiled to real Mach-O with clang + ld64.lld against a stub
# libSystem generated from the symbols dmgbox implements. No Apple SDK.
TEST_C    := $(wildcard tests/c/*.c)
TEST_BINS := $(patsubst tests/c/%.c,build/tests/c/%,$(TEST_C))
MACHO_CC  ?= clang
MACHO_LD  ?= ld64.lld

build/tests/sdk/libSystem.tbd: build/mrun tools/gen-tbd.sh
	@mkdir -p $(dir $@)
	tools/gen-tbd.sh build/mrun > $@

build/tests/c/%: tests/c/%.c build/tests/sdk/libSystem.tbd tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -nostdinc \
	    -Itests/include -fno-stack-protector -c -o $@.o $<
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -Lbuild/tests/sdk -lSystem -o $@ $@.o

test-bins: $(TEST_BINS)

check: build/mrun $(TEST_BINS)
	tests/run.sh

clean:
	rm -rf build

.PHONY: all clean check test-bins
