# syntax=docker/dockerfile:1

# Cross-compile on GitHub amd64 for Pi targets only (arm64 + arm/v7).
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder

ARG TARGETPLATFORM
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      $(case "$TARGETPLATFORM" in \
        "linux/arm64") echo "gcc-aarch64-linux-gnu" ;; \
        "linux/arm/v7") echo "gcc-arm-linux-gnueabihf" ;; \
        *) echo "UNSUPPORTED" ;; \
      esac) \
    && rm -rf /var/lib/apt/lists/* \
    && case "$TARGETPLATFORM" in \
         "linux/arm64"|"linux/arm/v7") ;; \
         *) echo "unsupported TARGETPLATFORM: $TARGETPLATFORM" >&2; exit 1 ;; \
       esac

WORKDIR /build
COPY app/Cargo.toml app/Cargo.lock ./app/
COPY app/src ./app/src
COPY templates ./templates

WORKDIR /build/app

ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
    CARGO_PROFILE_RELEASE_LTO=false

RUN case "$TARGETPLATFORM" in \
      "linux/arm64") \
        rustup target add aarch64-unknown-linux-gnu \
        && export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
        && cargo build --locked --release --target aarch64-unknown-linux-gnu \
        && mv target/aarch64-unknown-linux-gnu/release/rootos /rootos ;; \
      "linux/arm/v7") \
        rustup target add armv7-unknown-linux-gnueabihf \
        && export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
        && cargo build --locked --release --target armv7-unknown-linux-gnueabihf \
        && mv target/armv7-unknown-linux-gnueabihf/release/rootos /rootos ;; \
    esac

FROM debian:bookworm-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1000 app \
    && useradd -u 1000 -g app -M -s /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder --chown=1000:1000 /rootos /usr/local/bin/rootos
COPY --chown=1000:1000 static ./static

USER 1000:1000
EXPOSE 5000
ENTRYPOINT ["/usr/local/bin/rootos"]
CMD ["serve"]
