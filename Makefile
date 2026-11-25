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

# The concurrency runtime implements functions with the swiftasync calling
# convention (async context in r14, guaranteed tail calls), which only
# clang can emit.
CLANG ?= clang
$(BUILD)/obj/frameworks/concurrency/%.o: src/frameworks/concurrency/%.c $(wildcard src/include/*.h src/frameworks/concurrency/*.h src/frameworks/swift/*.h)
	@mkdir -p $(dir $@)
	$(CLANG) $(CFLAGS) -Wno-unused-function -fPIE -c -o $@ $<

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
	    -L$(BUILD)/sdk -lSystem -o $@ $(FOUNDATION_OBJS) $(FOUNDATION_SWIFT_LINK)

# ---- AppKit ----------------------------------------------------------------
# Objective-C like Foundation. The class skeleton and the exported
# constants are generated from the table in tools/gen-appkit.py (which also
# writes sdk/include/AppKit/AppKitClasses.h); behaviour is hand-written in
# frameworks/AppKit/*.m.
APPKIT := $(FW_ROOT)/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
FRAMEWORKS += $(if $(HAVE_MACHO),$(APPKIT))
all: $(if $(HAVE_MACHO),$(APPKIT))
APPKIT_SRCS := $(wildcard frameworks/AppKit/*.m)
APPKIT_OBJS := $(patsubst frameworks/AppKit/%.m,$(BUILD)/fw/AppKit/%.o,$(APPKIT_SRCS)) $(BUILD)/fw/AppKit/AppKitClasses.o
sdk/include/AppKit/AppKitClasses.h: tools/gen-appkit.py
	python3 tools/gen-appkit.py header > $@
$(BUILD)/fw/AppKit/AppKitClasses.m: tools/gen-appkit.py
	@mkdir -p $(dir $@)
	python3 tools/gen-appkit.py source > $@
$(BUILD)/fw/AppKit/AppKitClasses.o: $(BUILD)/fw/AppKit/AppKitClasses.m sdk/include/AppKit/AppKitClasses.h $(wildcard sdk/include/AppKit/*.h)
	$(MACHO_CC) $(FW_CFLAGS) -c -o $@ $<
$(BUILD)/fw/AppKit/%.o: frameworks/AppKit/%.m sdk/include/AppKit/AppKitClasses.h $(wildcard frameworks/AppKit/*.h sdk/include/*/*.h sdk/include/*.h)
	@mkdir -p $(dir $@)
	$(MACHO_CC) $(FW_CFLAGS) -c -o $@ $<
$(APPKIT): $(APPKIT_OBJS) $(FOUNDATION) $(BUILD)/sdk/libSystem.tbd
	@mkdir -p $(dir $@)
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -dylib \
	    -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
	    -L$(BUILD)/sdk -lSystem $(FOUNDATION) -o $@ $(APPKIT_OBJS)

# AppKit tests, like the Foundation ones.
TEST_APPKIT     := $(wildcard tests/appkit/*.m)
TEST_APPKITBINS := $(if $(HAVE_MACHO),$(patsubst tests/appkit/%.m,$(BUILD)/tests/appkit/%,$(TEST_APPKIT)))
$(BUILD)/tests/appkit/%: tests/appkit/%.m $(APPKIT) $(wildcard sdk/include/*/*.h)
	@mkdir -p $(dir $@)
	$(MACHO_CC) $(FW_CFLAGS) -O1 -c -o $@.o $<
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/sdk -lSystem $(FOUNDATION) $(APPKIT) -o $@ $@.o

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
# A test whose first line is "// module: Swift" is compiled as the module
# Swift itself: the compiler looks up a few types (Optional, for weak
# references) in the standard library by name, and the test declares them.
swift_module = $(or $(shell sed -n '1s|^// module: *||p' $(1)),$(subst -,_,$(2)))
# Optional per-test files: NAME.flags holds extra swiftc flags; NAME.lib.swift
# is a separate resilient module (-enable-library-evolution, named NAME_lib)
# that the test imports, which is how compiled code meets types whose layout
# it cannot know.
TEST_SWIFT     := $(filter-out tests/swift/prelude.swift tests/swift/%.lib.swift,$(wildcard tests/swift/*.swift))
TEST_SWIFTBINS := $(if $(SWIFTC),$(patsubst tests/swift/%.swift,$(BUILD)/tests/swift/%,$(TEST_SWIFT)))
swift_lib = $(wildcard tests/swift/$(1).lib.swift)
$(BUILD)/tests/swift/%: tests/swift/%.swift tests/swift/%.c tests/swift/prelude.swift $(wildcard tests/swift/*.flags tests/swift/*.lib.swift) $(BUILD)/sdk/libSystem.tbd tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(if $(call swift_lib,$*),$(SWIFTC) $(SWIFTFLAGS_ALL) -enable-library-evolution -module-name $(subst -,_,$*)_lib \
	    -emit-module -emit-module-path $@.lib/$(subst -,_,$*)_lib.swiftmodule -c -o $@.lib.o \
	    tests/swift/prelude.swift $(call swift_lib,$*))
	$(SWIFTC) $(SWIFTFLAGS_ALL) -module-name $(call swift_module,$<,$*) $(shell cat tests/swift/$*.flags 2>/dev/null) \
	    $(if $(call swift_lib,$*),-I $@.lib) -c -o $@.swift.o tests/swift/prelude.swift $<
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -fblocks -nostdinc \
	    -Itests/include -fno-stack-protector -c -o $@.o tests/swift/$*.c
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -e _main \
	    -L$(BUILD)/sdk -lSystem -o $@ $@.o $@.swift.o $(if $(call swift_lib,$*),$@.lib.o)

# ---- the Swift standard library ------------------------------------------
# libswiftCore.dylib is Swift source of our own (stdlib/), compiled as the
# module Swift. Declaring the same public API as Apple's standard library
# makes the compiler emit the same symbol names, which is what programs
# bind to; @frozen types keep Apple's layouts because programs inline
# against them. The runtime itself (swift_retain, metadata...) stays in mrun.
# Like Apple's, the library is built without dynamic exclusivity checks:
# they would also be inlined into programs (array storage accesses).
SWIFT_MODDIR := $(BUILD)/swift
LIBSWIFTCORE := $(FW_ROOT)/usr/lib/swift/libswiftCore.dylib
STDLIB_SRCS  := $(wildcard stdlib/*.swift) $(BUILD)/stdlib/Integers.swift $(BUILD)/stdlib/Floats.swift \
                $(BUILD)/stdlib/Codable.swift
$(BUILD)/stdlib/Codable.swift: tools/gen-codable.py
	@mkdir -p $(dir $@)
	python3 tools/gen-codable.py > $@
SWIFT_TARGET := -target x86_64-apple-macos11 -runtime-compatibility-version none
FRAMEWORKS   += $(if $(and $(SWIFTC),$(HAVE_MACHO)),$(LIBSWIFTCORE))
all: $(if $(and $(SWIFTC),$(HAVE_MACHO)),$(LIBSWIFTCORE))

$(BUILD)/stdlib/Integers.swift: tools/gen-integers.py
	@mkdir -p $(dir $@)
	python3 tools/gen-integers.py > $@
$(BUILD)/stdlib/Floats.swift: tools/gen-floats.py
	@mkdir -p $(dir $@)
	python3 tools/gen-floats.py > $@
$(BUILD)/stdlib/Swift.o: $(STDLIB_SRCS)
	@mkdir -p $(dir $@) $(SWIFT_MODDIR)
	$(SWIFTC) -parse-stdlib -module-name Swift -module-link-name swiftCore $(SWIFT_TARGET) \
	    -enable-library-evolution -wmo -parse-as-library -O -enforce-exclusivity=unchecked \
	    -emit-module -emit-module-path $(SWIFT_MODDIR)/Swift.swiftmodule -c -o $@ $(STDLIB_SRCS)
	echo > $(BUILD)/stdlib/SwiftOnoneSupport.swift
	$(SWIFTC) -module-name SwiftOnoneSupport $(SWIFT_TARGET) -I $(SWIFT_MODDIR) -parse-as-library \
	    -emit-module -emit-module-path $(SWIFT_MODDIR)/SwiftOnoneSupport.swiftmodule \
	    -Xfrontend -disable-implicit-concurrency-module-import \
	    -Xfrontend -disable-implicit-string-processing-module-import -O \
	    -o $(BUILD)/stdlib/SwiftOnoneSupport.o -c $(BUILD)/stdlib/SwiftOnoneSupport.swift
# The few parts of Apple's runtime that live in libswiftCore as C data
# (the empty collection singletons) are C here too: stdlib/*.c.
STDLIB_COBJS := $(patsubst stdlib/%.c,$(BUILD)/stdlib/%.o,$(wildcard stdlib/*.c))
$(BUILD)/stdlib/%.o: stdlib/%.c
	@mkdir -p $(dir $@)
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -nostdlibinc \
	    -fno-stack-protector -Wall -c -o $@ $<
$(LIBSWIFTCORE): $(BUILD)/stdlib/Swift.o $(STDLIB_COBJS) $(BUILD)/sdk/libSystem.tbd
	@mkdir -p $(dir $@)
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -dylib \
	    -install_name /usr/lib/swift/libswiftCore.dylib \
	    -L$(BUILD)/sdk -lSystem -o $@ $(BUILD)/stdlib/Swift.o $(STDLIB_COBJS)

# ---- an SDK and the Swift overlays ----------------------------------------
# build/MacOSX.sdk is bitten's own macOS SDK: the headers in sdk/include
# with Clang module maps, so Swift code compiled for macOS can import our
# C and Objective-C modules. The Swift overlays (overlays/NAME/*.swift) are
# built against it into build/root/usr/lib/swift/libswiftNAME.dylib, each
# with its module in build/swift. The compiler gets a resource directory of
# our own with only the Clang builtin headers and shims, so the Linux
# modules shipped with the toolchain (its CoreFoundation, Dispatch...)
# cannot shadow ours.
SDKROOT      := $(BUILD)/MacOSX.sdk
SWIFTRES     := $(BUILD)/swift-res
SWIFT_TOOLRES = $(dir $(SWIFTC))../lib/swift
OVERLAYS     := $(notdir $(wildcard overlays/*))
OVERLAY_LIBS := $(if $(and $(SWIFTC),$(HAVE_MACHO)),$(foreach o,$(OVERLAYS),$(FW_ROOT)/usr/lib/swift/libswift$(o).dylib))
FRAMEWORKS   += $(OVERLAY_LIBS)
all: $(OVERLAY_LIBS)
SWIFT_SDKFLAGS = -sdk $(SDKROOT) -resource-dir $(SWIFTRES) -I $(SWIFT_MODDIR) \
                 -Xfrontend -disable-implicit-concurrency-module-import \
                 -Xfrontend -disable-implicit-string-processing-module-import

$(SDKROOT)/.stamp: $(shell find sdk/include -type f)
	@mkdir -p $(SDKROOT)/usr/include
	cp -r sdk/include/. $(SDKROOT)/usr/include/
	@touch $@
$(SWIFTRES)/.stamp:
	@mkdir -p $(SWIFTRES)
	ln -sfn $(abspath $(SWIFT_TOOLRES))/clang $(SWIFTRES)/clang
	ln -sfn $(abspath $(SWIFT_TOOLRES))/shims $(SWIFTRES)/shims
	@touch $@

# Overlays that import other overlays: the full list of overlays each one
# needs (built first, linked against).
OVERLAY_DEPS_Darwin     := _errno _signal
OVERLAY_DEPS_CoreGraphics := CoreFoundation
OVERLAY_DEPS_os := ObjectiveC
overlay_lib = $(FW_ROOT)/usr/lib/swift/libswift$(1).dylib
overlay_deps = $(foreach d,$(OVERLAY_DEPS_$(1)),$(call overlay_lib,$(d)))

.SECONDEXPANSION:
$(FW_ROOT)/usr/lib/swift/libswift%.dylib: $$(wildcard overlays/%/*.swift) $$(call overlay_deps,$$*) $(LIBSWIFTCORE) $(SDKROOT)/.stamp $(SWIFTRES)/.stamp
	@mkdir -p $(dir $@) $(BUILD)/overlays
	$(SWIFTC) -module-name $* -module-link-name swift$* $(SWIFT_TARGET) $(SWIFT_SDKFLAGS) \
	    $(shell cat overlays/$*/swiftc.flags 2>/dev/null) -enable-library-evolution -wmo -parse-as-library -O \
	    -emit-module -emit-module-path $(SWIFT_MODDIR)/$*.swiftmodule \
	    -c -o $(BUILD)/overlays/$*.o $(wildcard overlays/$*/*.swift)
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -dylib \
	    -install_name /usr/lib/swift/libswift$*.dylib \
	    -L$(BUILD)/sdk -lSystem $(LIBSWIFTCORE) $(call overlay_deps,$*) -o $@ $(BUILD)/overlays/$*.o

# ---- Foundation's Swift overlay ---------------------------------------------
# On macOS Foundation's Swift API lives in Foundation.framework itself, so
# frameworks/Foundation/swift/*.swift is compiled as module Foundation (over
# the Clang module of the same name) and linked into the framework with the
# Objective-C objects.
FOUNDATION_SWIFT_SRCS := $(wildcard frameworks/Foundation/swift/*.swift)
FOUNDATION_SWIFT_OBJ  := $(if $(and $(SWIFTC),$(HAVE_MACHO),$(FOUNDATION_SWIFT_SRCS)),$(BUILD)/fw/Foundation/FoundationSwift.o)
FOUNDATION_SWIFT_LINK  = $(if $(FOUNDATION_SWIFT_OBJ),$(FOUNDATION_SWIFT_OBJ) $(LIBSWIFTCORE) $(OVERLAY_LIBS))
$(FOUNDATION): $(FOUNDATION_SWIFT_OBJ)
$(BUILD)/fw/Foundation/FoundationSwift.o: $(FOUNDATION_SWIFT_SRCS) $(OVERLAY_LIBS) $(SDKROOT)/.stamp $(SWIFTRES)/.stamp
	@mkdir -p $(dir $@)
	$(SWIFTC) -module-name Foundation $(SWIFT_TARGET) $(SWIFT_SDKFLAGS) \
	    -enable-library-evolution -wmo -parse-as-library -O \
	    -emit-module -emit-module-path $(SWIFT_MODDIR)/Foundation.swiftmodule \
	    -c -o $@ $(FOUNDATION_SWIFT_SRCS)

# ---- frameworks written in Swift ------------------------------------------
# frameworks/NAME/*.swift (SwiftUI...) is built as module NAME into
# NAME.framework/Versions/A/NAME, against the SDK, the overlays (all of
# them, built first), Foundation and AppKit. Unlike the overlays they import
# _Concurrency implicitly, as ordinary Swift code does.
SWIFT_FWS     := $(patsubst frameworks/%/,%,$(sort $(dir $(wildcard frameworks/*/*.swift))))
swift_fw_lib   = $(FW_ROOT)/System/Library/Frameworks/$(1).framework/Versions/A/$(1)
SWIFT_FW_LIBS := $(if $(and $(SWIFTC),$(HAVE_MACHO)),$(foreach f,$(SWIFT_FWS),$(call swift_fw_lib,$(f))))
FRAMEWORKS    += $(SWIFT_FW_LIBS)
all: $(SWIFT_FW_LIBS)
# Swift frameworks that import other Swift frameworks (built first, linked).
# One rule per framework: the path names the framework twice, which a
# pattern rule cannot express.
SWIFT_FW_DEPS_SwiftUI := Combine
define swift_framework
$(call swift_fw_lib,$(1)): $(wildcard frameworks/$(1)/*.swift) $(OVERLAY_LIBS) $(APPKIT) $(FOUNDATION) $(foreach d,$(SWIFT_FW_DEPS_$(1)),$(call swift_fw_lib,$(d)))
	@mkdir -p $$(dir $$@) $(BUILD)/swiftfw
	$(SWIFTC) -module-name $(1) $(SWIFT_TARGET) -sdk $(SDKROOT) -resource-dir $(SWIFTRES) -I $(SWIFT_MODDIR) \
	    -Xfrontend -disable-implicit-string-processing-module-import \
	    -enable-library-evolution -wmo -parse-as-library -O \
	    -emit-module -emit-module-path $(SWIFT_MODDIR)/$(1).swiftmodule \
	    -c -o $(BUILD)/swiftfw/$(1).o $(wildcard frameworks/$(1)/*.swift)
	$(MACHO_LD) -arch x86_64 -platform_version macos 11.0 11.0 -dylib \
	    -install_name /System/Library/Frameworks/$(1).framework/Versions/A/$(1) \
	    -L$(BUILD)/sdk -lSystem $(LIBSWIFTCORE) $(OVERLAY_LIBS) $(FOUNDATION) $(APPKIT) \
	    $(foreach d,$(SWIFT_FW_DEPS_$(1)),$(call swift_fw_lib,$(d))) -o $$@ $(BUILD)/swiftfw/$(1).o
endef
$(foreach f,$(SWIFT_FWS),$(eval $(call swift_framework,$(f))))

# Tests in ordinary Swift, against that standard library: tests/swiftlib/
# NAME.swift with a C driver NAME.c (functions exported with @_silgen_name;
# swiftcc and C agree for plain integer and pointer arguments).
TEST_SWLIB     := $(wildcard tests/swiftlib/*.swift)
TEST_SWLIBBINS := $(if $(and $(SWIFTC),$(HAVE_MACHO)),$(patsubst tests/swiftlib/%.swift,$(BUILD)/tests/swiftlib/%,$(TEST_SWLIB)))
# They import _Concurrency implicitly, as ordinary Swift code does, and can
# import the SDK's modules and overlays.
LIBCONCURRENCY := $(FW_ROOT)/usr/lib/swift/libswift_Concurrency.dylib
# A test can name a later deployment target: symbols that moved between
# dylibs (errno into _errno, the signal constants into _signal, both in
# macOS 14) are hidden from older targets by $ld$hide directives.
SWLIB_MACOS_darwin := 14.0
swlib_macos = $(or $(SWLIB_MACOS_$(1)),11.0)
$(BUILD)/tests/swiftlib/%: tests/swiftlib/%.swift tests/swiftlib/%.c $(LIBSWIFTCORE) $(OVERLAY_LIBS) tests/include/darwin.h
	@mkdir -p $(dir $@)
	$(SWIFTC) -target x86_64-apple-macos$(call swlib_macos,$*) -runtime-compatibility-version none -sdk $(SDKROOT) -resource-dir $(SWIFTRES) -I $(SWIFT_MODDIR) \
	    -module-name $(subst -,_,$*) -parse-as-library \
	    -Xfrontend -disable-implicit-string-processing-module-import \
	    -wmo $(SWIFT_FLAGS) -c -o $@.swift.o $<
	$(MACHO_CC) -target x86_64-apple-macos11 -O1 -ffreestanding -fno-builtin -fblocks -nostdinc \
	    -Itests/include -fno-stack-protector -c -o $@.o tests/swiftlib/$*.c
	$(MACHO_LD) -arch x86_64 -platform_version macos $(call swlib_macos,$*) $(call swlib_macos,$*) -e _main \
	    -L$(BUILD)/sdk -lSystem $(LIBSWIFTCORE) $(OVERLAY_LIBS) -o $@ $@.o $@.swift.o

test-bins: $(TEST_APPKITBINS) $(TEST_BINS) $(TEST_OBJCBINS) $(TEST_FNDBINS) $(TEST_GOBINS) $(TEST_SWIFTBINS) $(TEST_SWLIBBINS)

check: $(BUILD)/mrun $(FRAMEWORKS) $(TEST_APPKITBINS) $(TEST_BINS) $(TEST_OBJCBINS) $(TEST_FNDBINS) $(TEST_GOBINS) $(TEST_SWIFTBINS) $(TEST_SWLIBBINS)
	BUILD=$(BUILD) tests/run.sh

check-dmgx:
	python3 -m unittest discover -s tests/dmgx

clean:
	rm -rf $(BUILD)

.PHONY: all clean check check-dmgx test-bins
