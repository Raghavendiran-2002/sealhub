# syntax=docker/dockerfile:1

# Cross-compile on GitHub amd64 (BUILDPLATFORM) for Pi targets only — no amd64 image.
FROM --platform=$BUILDPLATFORM rust:1-alpine AS builder

ARG TARGETPLATFORM
RUN apk add --no-cache build-base musl-dev \
    && case "$TARGETPLATFORM" in \
         "linux/arm64") apk add --no-cache gcc-aarch64-linux-musl ;; \
         "linux/arm/v7") apk add --no-cache gcc-arm-linux-gnueabihf ;; \
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
        rustup target add aarch64-unknown-linux-musl \
        && export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-musl-gcc \
        && cargo build --locked --release --target aarch64-unknown-linux-musl \
        && mv target/aarch64-unknown-linux-musl/release/rootos /rootos ;; \
      "linux/arm/v7") \
        rustup target add armv7-unknown-linux-musleabihf \
        && export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER=arm-linux-gnueabihf-gcc \
        && cargo build --locked --release --target armv7-unknown-linux-musleabihf \
        && mv target/armv7-unknown-linux-musleabihf/release/rootos /rootos ;; \
      *) echo "unsupported TARGETPLATFORM: $TARGETPLATFORM" >&2; exit 1 ;; \
    esac

FROM alpine:3.21

RUN apk add --no-cache ca-certificates \
    && addgroup -S -g 1000 app \
    && adduser -S -D -H -u 1000 -G app app

WORKDIR /app
COPY --from=builder --chown=1000:1000 /rootos /usr/local/bin/rootos
COPY --chown=1000:1000 static ./static

USER 1000:1000
EXPOSE 5000
ENTRYPOINT ["/usr/local/bin/rootos"]
CMD ["serve"]
