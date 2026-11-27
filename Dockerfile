# bitten: run macOS (Mach-O) programs from a .dmg in an ordinary container.
# No VM and no macOS files in the image: you mount your own .dmg at runtime.
#
#   docker build -t bitten .
#   docker run --rm -it -v /path/to/App.dmg:/dmg/app.dmg:ro bitten
#
# Windows on the desktop (X11; on Wayland through Xwayland):
#   docker run --rm -it -e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
#     -v "$XAUTHORITY":/tmp/.Xauthority:ro -e XAUTHORITY=/tmp/.Xauthority \
#     -v /path/to/App.dmg:/dmg/app.dmg:ro bitten run

FROM ubuntu:24.04 AS build
# gcc builds mrun; clang + lld build bitten's own frameworks (Foundation, ...)
# as Mach-O libraries, exactly the form macOS programs expect to load.
# The swift.org toolchain builds bitten's Swift stdlib and overlays (SwiftUI,
# Combine, ...); without it the image has no Swift and Swift apps cannot start.
ARG SWIFT=6.3.1
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev make clang lld python3 \
        ca-certificates curl binutils libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev \
        libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata zlib1g-dev libx11-dev \
    && rm -rf /var/lib/apt/lists/* \
    && case "$(uname -m)" in x86_64) p=ubuntu24.04 ;; aarch64) p=ubuntu24.04-aarch64 ;; *) exit 1 ;; esac \
    && curl -fsSL "https://download.swift.org/swift-$SWIFT-release/ubuntu2404${p#ubuntu24.04}/swift-$SWIFT-RELEASE/swift-$SWIFT-RELEASE-$p.tar.gz" \
        | tar -xz -C /opt && mv "/opt/swift-$SWIFT-RELEASE-$p" /opt/swift
WORKDIR /src
COPY Makefile ./
COPY src ./src
COPY sdk ./sdk
COPY frameworks ./frameworks
COPY stdlib ./stdlib
COPY overlays ./overlays
COPY tools ./tools
RUN make -j"$(nproc)" BUILD=/out && test -f /out/root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation \
    && test -f /out/root/usr/lib/swift/libswiftCore.dylib

# Optional: build and run the test suite (docker build --target test .)
FROM build AS test
# fonts-dejavu-core: open TrueType fonts for CoreText (tests/c/coretext).
RUN apt-get update && apt-get install -y --no-install-recommends golang-go python3 ca-certificates fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
# the Go tests' go.mod wants Go 1.24, newer than Ubuntu 24.04's golang-go
ENV GOTOOLCHAIN=go1.24.0
COPY tests ./tests
RUN make -j"$(nproc)" BUILD=/out check && make check-dmgx

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 zsh procps less ca-certificates libx11-6 \
        # Metal: tools/metal-compile.py builds an app's shaders with clang
        # (it reads Apple's AIR) into a shared object on first use
        clang libc6-dev binutils \
        # open fonts: CoreText maps Apple's font names to these
        fonts-dejavu-core fonts-noto-core \
    && rm -rf /var/lib/apt/lists/* \
    # the places macOS programs expect to exist
    && mkdir -p /Applications /Users/Shared /Library /System/Library /Volumes /private /dmg \
    && ln -s /tmp /private/tmp && ln -s /var /private/var && ln -s /etc /private/etc \
    && useradd --create-home --home-dir /Users/mac --shell /bin/zsh mac \
    && chown mac:mac /Applications /Users/mac
COPY --from=build /out/mrun /usr/local/bin/mrun
COPY --from=build /out/root /usr/local/lib/bitten/root
COPY --from=build /out/tools /usr/local/lib/bitten/tools
COPY tools/dmgx /usr/local/bin/dmgx
COPY docker/bitten /usr/local/bin/bitten
# macOS programs start shells through `login -fpl user ...`
COPY docker/login /usr/bin/login
COPY docker/zshrc /Users/mac/.zshrc
COPY examples /usr/share/bitten/examples
USER mac
WORKDIR /Users/mac
ENV HOME=/Users/mac USER=mac LOGNAME=mac SHELL=/bin/zsh TMPDIR=/tmp LANG=C.UTF-8
# the display page must listen beyond the container's loopback for -p 7681:7681
ENV BITTEN_DISPLAY_PUBLIC=1
EXPOSE 7681
ENTRYPOINT ["/usr/local/bin/bitten"]
