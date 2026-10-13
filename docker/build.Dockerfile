# Build image for Phoebus IPAs: Ubuntu 24.04 with the swift.org Swift
# toolchain, Go (for the icon renderer), the packages the build needs, the
# pinned xtool fork and actool at a pinned commit (it compiles the app icons'
# asset catalog; PHOEBUS_ACTOOL). Built and pushed by .github/workflows/build-image.yml
# as ghcr.io/<owner>/phoebus-builder; the IPA workflow runs inside it.
#
# The Darwin SDK is not in the image: it comes from Xcode, which may not be
# redistributed, so the IPA workflow installs it from a private URL (see
# docs/building-on-linux.md, "CI").
#
# To build xtool from an unpushed commit, pass a clone of the fork:
#   docker build -f docker/build.Dockerfile \
#     --build-context xtool-src=<clone> --build-arg XTOOL_REPO=/xtool-src .
FROM scratch AS xtool-src

# actool, a reimplementation of Apple's asset catalog compiler that runs on
# Linux, built at a pinned commit; only the binary goes into the image.
FROM rust:1.98.0-slim-bookworm AS actool
ARG ACTOOL_REPO=https://github.com/pendo324/actool
ARG ACTOOL_REV=cfc176caf4004242b6445daff1d616928345186a
RUN cargo install --locked --git "$ACTOOL_REPO" --rev "$ACTOOL_REV" --root /actool actool \
    && rm -rf /usr/local/cargo/registry /usr/local/cargo/git

FROM ubuntu:24.04
ARG XTOOL_REPO=https://github.com/pendo324/xtool
ENV PHOEBUS_TOOLS=/opt/phoebus \
    SWIFT_DIR=/opt/phoebus/swift \
    GO_DIR=/opt/phoebus/go
ENV PATH=/opt/phoebus/swift/usr/bin:/opt/phoebus/go/bin:$PATH

COPY scripts/ci/setup-linux.sh scripts/ci/build-libimobiledevice.sh /phoebus/scripts/ci/
COPY scripts/lgrender/go.mod /phoebus/scripts/lgrender/
RUN /phoebus/scripts/ci/setup-linux.sh && rm -rf /var/lib/apt/lists/*

# xtool, with the libimobiledevice it is built against copied next to it
# (Ubuntu's is older than xtool needs).
COPY scripts/install-xtool.sh scripts/xtool-env.sh /phoebus/scripts/
RUN --mount=type=bind,from=xtool-src,target=/xtool-src \
    git config --global --add safe.directory '*' \
    && /phoebus/scripts/ci/build-libimobiledevice.sh /tmp/limd \
    && PKG_CONFIG_PATH=/tmp/limd/lib/pkgconfig XTOOL_BUNDLE_LIBS_FROM=/tmp/limd/lib \
       XTOOL_REPO="$XTOOL_REPO" /phoebus/scripts/install-xtool.sh \
    && rm -rf /tmp/limd /root/.cache /root/.swiftpm

# Last, so moving the actool pin rebuilds only this layer.
COPY --from=actool /actool/bin/actool /usr/local/bin/actool
ENV PHOEBUS_ACTOOL=/usr/local/bin/actool

WORKDIR /io
