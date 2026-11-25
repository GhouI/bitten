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
ASMS := $(wildcard src/loader/*.S src/frameworks/*/*.S)
OBJS := $(patsubst src/%.c,$(BUILD)/obj/%.o,$(SRCS)) $(patsubst src/%.S,$(BUILD)/obj/%.o,$(ASMS))

# Frameworks above CoreFoundation are written in Objective-C and built as
# real Mach-O libraries (clang + ld64.lld), then loaded by mrun like any
# other macOS framework. They are built when that toolchain is present.
MACHO_CC  ?= clang
# Debian and Ubuntu keep ld64.lld in a versioned LLVM directory.
MACHO_LD  ?= $(or $(shell command -v ld64.lld 2>/dev/null),$(lastword $(sort $(wildcard /usr/lib/llvm-*/bin/ld64.lld))),ld64.lld)
HAVE_MACHO := $(and $(shell command -v $(MACHO_CC) 2>/dev/null),$(shell command -v $(MACHO_LD) 2>/dev/null))
FW_ROOT    := $(BUILD)/root
FOUNDATION := $(FW_ROOT)/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
FRAMEWORKS := $(if $(HAVE_MACHO),$(FOUNDATION))

all: $(BUILD)/mrun $(FRAMEWORKS)

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
TEST_C    := $(filter-out $(EXCLUDE),$(wildcard tests/c/*.c))
TEST_BINS := $(patsubst tests/c/%.c,$(BUILD)/tests/c/%,$(TEST_C))
$(BUILD)/sdk/libSystem.tbd: $(BUILD)/mrun tools/gen-tbd.sh
	@mkdir -p $(dir $@)
	tools/gen-tbd.sh $(BUILD)/mrun > $@

$(BUILD)/tests/c/%: tests/c/%.c $(BUILD)/sdk/libSystem.tbd tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -fblocks -nostdinc \
	    -Itests/include -fno-stack-protector -c -o $@.o $<
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/sdk -lSystem -o $@ $@.o

# ---- Foundation ------------------------------------------------------------
MACHO_TARGET := -target x86_64-apple-macos11
FW_CFLAGS := $(MACHO_TARGET) -x objective-c -fobjc-arc -fblocks -O2 -ffreestanding -nostdlibinc \
             -Isdk/include -fno-stack-protector -Wall -Wno-unused-parameter \
             -Wno-objc-protocol-method-implementation -Wno-nullability-completeness
FOUNDATION_SRCS := $(wildcard frameworks/Foundation/*.m)
FOUNDATION_OBJS := $(patsubst frameworks/Foundation/%.m,$(BUILD)/fw/Foundation/%.o,$(FOUNDATION_SRCS))
$(BUILD)/fw/Foundation/%.o: frameworks/Foundation/%.m $(wildcard frameworks/Foundation/*.h sdk/include/*/*.h sdk/include/*.h)
	@mkdir -p $(dir $@)
	$(MACHO_CC) $(FW_CFLAGS) -c -o $@ $<
$(FOUNDATION): $(FOUNDATION_OBJS) $(BUILD)/sdk/libSystem.tbd
	@mkdir -p $(dir $@)
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -dylib \
	    -install_name /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation \
	    -L$(BUILD)/sdk -lSystem -o $@ $(FOUNDATION_OBJS)

# Tests that use Foundation, compiled against the SDK headers in sdk/include.
TEST_FND     := $(wildcard tests/foundation/*.m)
TEST_FNDBINS := $(patsubst tests/foundation/%.m,$(BUILD)/tests/foundation/%,$(TEST_FND))
$(BUILD)/tests/foundation/%: tests/foundation/%.m $(FOUNDATION) $(wildcard sdk/include/*/*.h)
	@mkdir -p $(dir $@)
	$(MACHO_CC) $(FW_CFLAGS) -O1 -c -o $@.o $<
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/sdk -lSystem $(FOUNDATION) -o $@ $@.o

# Objective-C tests (ARC, blocks), against tests/include/objc.h.
TEST_OBJC     := $(wildcard tests/objc/*.m)
TEST_OBJCBINS := $(patsubst tests/objc/%.m,$(BUILD)/tests/objc/%,$(TEST_OBJC))
$(BUILD)/tests/objc/%: tests/objc/%.m $(BUILD)/sdk/libSystem.tbd tests/include/objc.h tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(MACHO_CC) -target x86_64-apple-macos11 -x objective-c -fobjc-arc -fblocks -O1 -ffreestanding \
	    -fno-builtin -nostdinc -Itests/include -fno-stack-protector -Wno-objc-root-class \
	    -Wno-unused-parameter -c -o $@.o $<
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/sdk -lSystem -o $@ $@.o

# Go tests: real darwin/amd64 binaries from the Go toolchain's own linker.
# They are built when a Go toolchain is available (GO=...), otherwise skipped.
GO ?= go
TEST_GO     := $(wildcard tests/go/*/main.go)
TEST_GOBINS := $(if $(shell command -v $(GO) 2>/dev/null),$(patsubst tests/go/%/main.go,$(BUILD)/tests/go/%,$(TEST_GO)))

$(BUILD)/tests/go/%: tests/go/%/main.go tests/go/go.mod
	@mkdir -p $(dir $@)
	cd tests/go && GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-buildvcs=false \
	    $(GO) build -o $(abspath $@) ./$*

# Swift tests: real compiler output from the open-source Swift toolchain
# (swift.org, any host) built with -parse-stdlib, so they need no standard
# library and no Apple files: only the runtime entry points bitten provides.
# Each test is tests/swift/NAME.swift (plus tests/swift/prelude.swift) and a
# C driver tests/swift/NAME.c with main(). Built when swiftc is available.
SWIFTC ?= $(or $(shell command -v swiftc 2>/dev/null),$(wildcard /opt/swift/usr/bin/swiftc))
SWIFT_FLAGS ?= -O
SWIFTFLAGS_ALL := -parse-stdlib -target x86_64-apple-macos11 -runtime-compatibility-version none \
                  -wmo -parse-as-library $(SWIFT_FLAGS)
TEST_SWIFT     := $(filter-out tests/swift/prelude.swift,$(wildcard tests/swift/*.swift))
TEST_SWIFTBINS := $(if $(SWIFTC),$(patsubst tests/swift/%.swift,$(BUILD)/tests/swift/%,$(TEST_SWIFT)))
$(BUILD)/tests/swift/%: tests/swift/%.swift tests/swift/%.c tests/swift/prelude.swift $(BUILD)/sdk/libSystem.tbd tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(SWIFTC) $(SWIFTFLAGS_ALL) -module-name $(subst -,_,$*) -c -o $@.swift.o tests/swift/prelude.swift $<
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -fblocks -nostdinc \
	    -Itests/include -fno-stack-protector -c -o $@.o tests/swift/$*.c
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/sdk -lSystem -o $@ $@.o $@.swift.o

test-bins: $(TEST_BINS) $(TEST_OBJCBINS) $(TEST_FNDBINS) $(TEST_GOBINS) $(TEST_SWIFTBINS)

check: $(BUILD)/mrun $(FRAMEWORKS) $(TEST_BINS) $(TEST_OBJCBINS) $(TEST_FNDBINS) $(TEST_GOBINS) $(TEST_SWIFTBINS)
	BUILD=$(BUILD) tests/run.sh

check-dmgx:
	python3 -m unittest discover -s tests/dmgx

clean:
	rm -rf $(BUILD)

.PHONY: all clean check check-dmgx test-bins
