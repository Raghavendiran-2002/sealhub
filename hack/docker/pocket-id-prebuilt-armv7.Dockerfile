# Build context: upstream pocket-id checkout at pocket-id-src/
# Binary must be at linux/arm/v7/sealhub-prebuilt (name avoids upstream .gitignore rule "pocket-id").

FROM alpine:3.24.1

WORKDIR /app

RUN apk add --no-cache su-exec

COPY linux/arm/v7/sealhub-prebuilt /app/pocket-id
COPY scripts/docker /app/docker

RUN chmod +x /app/pocket-id && \
    find /app/docker -name "*.sh" -exec chmod +x {} \;

EXPOSE 1411
ENV APP_ENV=production

HEALTHCHECK --interval=90s --timeout=5s --start-period=10s --retries=3 \
  CMD [ "/app/pocket-id", "healthcheck" ]

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["/app/pocket-id"]
