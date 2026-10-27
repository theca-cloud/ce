# The CE image, built from source (../docs/docs/adr/0001-ce-built-from-source.md):
# core's server and its WASM client from core's source, the web app from web's,
# both fetched from GitHub at the pins below. The official image is built by this
# very file, so a plain `docker build .` rebuilds it, logged in nowhere.
# The two pins: the web stage refuses a pair where web isn't built for that core.
ARG CORE_VERSION=1.1.0
ARG WEB_VERSION=1.2.0
ARG SOURCES=https://github.com/theca-cloud

# The sources, at their release tags (no `v` from 1.0.0 on; 0.x's tags had one).
# Local sources instead: --build-context core-src=<dir> --build-context web-src=<dir>,
# or, where named contexts can't be passed (the buildx plugin), folders of the
# build context: --build-arg CORE_SOURCE=<dir> --build-arg WEB_SOURCE=<dir>.
FROM scratch AS core-src
ARG SOURCES CORE_VERSION
ARG CORE_SOURCE=${SOURCES}/core.git#${CORE_VERSION}
ADD ${CORE_SOURCE} /

FROM scratch AS web-src
ARG SOURCES WEB_VERSION
ARG WEB_SOURCE=${SOURCES}/web.git#${WEB_VERSION}
ADD ${WEB_SOURCE} /

# The browser package's toolchain, on the build machine's platform (WASM is the
# same whatever the CPU): Rust at core's rust-toolchain.toml, on the Debian
# release distroless/cc is built from, and wasm-pack.
FROM --platform=$BUILDPLATFORM rust:1.98.0-bookworm AS client
RUN rustup target add wasm32-unknown-unknown \
 && cargo install --locked wasm-pack@0.15.0
WORKDIR /src
COPY --from=core-src / .
# @theca/client, as core's release publishes it: the engine, and the password
# scorer beside it (password/).
RUN wasm-pack build crates/client --release --target web --scope theca --out-dir /client \
 && sed -i 's|"name": "@theca/theca-client"|"name": "@theca/client"|' /client/package.json \
 && wasm-pack build crates/password --release --target web --out-dir /client/password \
 && rm /client/password/package.json /client/password/.gitignore \
 && sed -i 's|"files": \[|"files": ["password",|' /client/package.json

# The server, compiled natively for the target's architecture, against glibc
# (ADR 0001): off its platform it runs under emulation (arm64 on the amd64
# agent: about half an hour), so the binary is built on its own target.
FROM rust:1.98.0-bookworm AS server
WORKDIR /src
COPY --from=core-src / .
RUN SQLX_OFFLINE=true cargo build --release --locked -p theca-core --bin theca-server \
 && cp target/release/theca-server /theca-server

# The web app, with the client built above in place of the registry's: its
# lockfile entry is dropped so npm ci never reaches the (private) registry.
# First, the pair: web must pin @theca/client at the core being built.
FROM --platform=$BUILDPLATFORM node:24.22-bookworm AS web
WORKDIR /src
COPY --from=web-src / .
COPY --from=core-src /Cargo.toml /tmp/core.toml
RUN core=$(sed -n 's/^version = "\(.*\)"$/\1/p' /tmp/core.toml | head -1) \
 && pin=$(node -p "require('./package.json').dependencies['@theca/client']") \
 && { [ "$pin" = "$core" ] || { echo "web pins @theca/client $pin, not core $core" >&2; exit 1; }; } \
 && rm .npmrc \
 && npm pkg delete 'dependencies.@theca/client' \
 && node -e "const f='package-lock.json',l=require('./'+f);delete l.packages[''].dependencies['@theca/client'];delete l.packages['node_modules/@theca/client'];require('fs').writeFileSync(f,JSON.stringify(l,null,'\t'))" \
 && npm ci --no-audit --no-fund
COPY --from=client /client node_modules/@theca/client
RUN npm run build

# An empty /data for the image's user: distroless has no shell to mkdir it, and
# WORKDIR creates it without running anything (no emulation for arm64).
FROM scratch AS dirs
WORKDIR /data/files

FROM gcr.io/distroless/cc-debian12:nonroot
ARG CORE_VERSION WEB_VERSION
COPY --from=server /theca-server /theca-server
COPY --from=web /src/build /web
# Owned by nonroot: a named volume mounted there starts with this ownership,
# so the server can write the filesystem storage (/data/files).
COPY --from=dirs --chown=65532:65532 /data /data
ENV WEB_DIR=/web
# Plain HTTP: TLS is the reverse proxy's (declare it in TRUSTED_PROXIES).
ENV LISTEN_ADDR=0.0.0.0:8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s CMD ["/theca-server", "healthcheck"]
ENTRYPOINT ["/theca-server"]
LABEL org.theca.web=${WEB_VERSION} org.theca.core=${CORE_VERSION}
