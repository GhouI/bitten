# bitten: run macOS (Mach-O) programs from a .dmg in an ordinary container.
# No VM and no macOS files in the image: you mount your own .dmg at runtime.
#
#   docker build -t bitten .
#   docker run --rm -it -v /path/to/App.dmg:/dmg/app.dmg:ro bitten

FROM debian:trixie-slim AS build
# gcc builds mrun; clang + lld build bitten's own frameworks (Foundation, ...)
# as Mach-O libraries, exactly the form macOS programs expect to load.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev make clang lld \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY Makefile ./
COPY src ./src
COPY sdk ./sdk
COPY frameworks ./frameworks
COPY tools ./tools
RUN make -j"$(nproc)" BUILD=/out && test -f /out/root/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation

# Optional: build and run the test suite (docker build --target test .)
FROM build AS test
# fonts-dejavu-core: open TrueType fonts for CoreText (tests/c/coretext).
RUN apt-get update && apt-get install -y --no-install-recommends golang-go python3 ca-certificates fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
COPY tests ./tests
RUN make -j"$(nproc)" BUILD=/out check && make check-dmgx

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 zsh procps less ca-certificates \
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
COPY tools/dmgx /usr/local/bin/dmgx
COPY docker/bitten /usr/local/bin/bitten
# macOS programs start shells through `login -fpl user ...`
COPY docker/login /usr/bin/login
COPY docker/zshrc /Users/mac/.zshrc
COPY examples /usr/share/bitten/examples
USER mac
WORKDIR /Users/mac
ENV HOME=/Users/mac USER=mac LOGNAME=mac SHELL=/bin/zsh TMPDIR=/tmp LANG=C.UTF-8
ENTRYPOINT ["/usr/local/bin/bitten"]
