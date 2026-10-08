# The CE image: core's server serving web's build (WEB_DIR). Nothing is built
# here. WEB_VERSION is the one pin; CORE_VERSION is the core that web is for,
# read from its label by scripts/core-version.sh and passed in, never written.
ARG WEB_VERSION=0.3.1
ARG CORE_VERSION
FROM git.pband.ch/theca/web:${WEB_VERSION} AS web

# An empty /data for the image's user: distroless has no shell to mkdir it, and
# WORKDIR creates it without running anything (no emulation for arm64).
FROM scratch AS dirs
WORKDIR /data/files

# Distroless, nonroot, LISTEN_ADDR, HEALTHCHECK and entrypoint are core's.
FROM git.pband.ch/theca/core:${CORE_VERSION}
ARG WEB_VERSION CORE_VERSION
COPY --from=web /web /web
# Owned by nonroot: a named volume mounted there starts with this ownership,
# so the server can write the filesystem storage (/data/files).
COPY --from=dirs --chown=65532:65532 /data /data
ENV WEB_DIR=/web
LABEL org.theca.web=${WEB_VERSION} org.theca.core=${CORE_VERSION}
