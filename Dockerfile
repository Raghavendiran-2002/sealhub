# syntax=docker/dockerfile:1

# Compile on the host arch (fast on GitHub amd64), cross-build arm64 instead of QEMU rustc.
FROM --platform=$BUILDPLATFORM rust:1-alpine AS builder

ARG TARGETPLATFORM
RUN apk add --no-cache build-base musl-dev \
    && case "$TARGETPLATFORM" in \
         "linux/arm64") apk add --no-cache gcc-aarch64-linux-musl ;; \
       esac

WORKDIR /build
COPY app/Cargo.toml app/Cargo.lock ./app/
COPY app/src ./app/src
COPY templates ./templates

WORKDIR /build/app

# CI/release flags: keep binary small but avoid full LTO (much faster builds).
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
    CARGO_PROFILE_RELEASE_LTO=false

RUN case "$TARGETPLATFORM" in \
      "linux/arm64") \
        rustup target add aarch64-unknown-linux-musl \
        && export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-musl-gcc \
        && cargo build --locked --release --target aarch64-unknown-linux-musl \
        && mv target/aarch64-unknown-linux-musl/release/rootos /rootos ;; \
      *) \
        cargo build --locked --release \
        && mv target/release/rootos /rootos ;; \
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
