@../docs/CLAUDE.md

# This repo: `ce`

The Community Edition: the CE image, **built from `core`'s and `web`'s sources** (`../docs/docs/adr/0001-ce-built-from-source.md`), and what a self-hoster needs to run it. Its version is the **product version** users see (CE 1.3 = some `core` + some `web`). Published as `thecacloud/ce` on Docker Hub (and on Gitea, which `theca.pband.ch` pulls); the repository is mirrored to GitHub.

## What it builds

- **Two pins in the `Dockerfile`**: `CORE_VERSION` and `WEB_VERSION`, the release tags fetched from GitHub. The build refuses a pair where `web`'s `package.json` doesn't pin `@theca/client` at the core being built. A `core` hotfix reaches the CE through a `web` patch release bumping its pin, then both pins here.
- **The stages**: the WASM client (`wasm-pack`) and the web app (Node, with that client in place of the registry's, never reaching Gitea) on the build platform, their output being the same whatever the CPU; the server **compiled natively for each architecture**, against glibc (arm64 under QEMU on the amd64 agent: about 28 minutes); `distroless/cc`, nonroot (the binary, `/web`, `WEB_DIR`, `HEALTHCHECK`, entrypoint).
- **Local sources**: `docker buildx build --build-context core-src=<dir> --build-context web-src=<dir> .` (`scripts/smoke.sh` takes them as `CORE_SRC` and `WEB_SRC`), or folders of the build context with `--build-arg CORE_SOURCE=<dir> --build-arg WEB_SOURCE=<dir>` (what the pipelines pass: the buildx plugin has no named contexts). Clean exports, never a working tree (`target/` is gigabytes).
- **Until GitHub has `core` and `web`**: `scripts/sources.sh` clones them from Gitea at the pins into `.sources/`; `scripts/ci.sh` and the `sources` steps of `rc.yaml` and `release.yaml` use it. Then those lines go, marked where they are.
- The server: `../core/CONFIGURATION.md` (environment for what it needs to start, secrets only as `X__FILE`; everything else is an instance setting). It runs its migrations at startup, has `theca-server healthcheck` for Docker's `HEALTHCHECK` (no `curl` in the image), and prints the first-run setup link in its logs.

## What it ships

- **The CE image**, amd64 and arm64 (arm64: self-hosters on a Raspberry Pi).
- **A compose** naming the major version (`thecacloud/ce:1`), with Postgres (18+ with the built-in `C.UTF-8` collation, or the server refuses to start) and the filesystem storage; **`examples/`** around it: S3 with Garage, Caddy, Traefik, OIDC with Authelia.
- **The S3 buckets' CORS rule**: browsers upload and download chunks through presigned URLs on the bucket's origin, so the bucket must allow `PUT` and `GET` from `PUBLIC_URL`, the signed headers (`x-amz-checksum-sha256`, `If-None-Match`), and expose `ETag`. Set up by `examples/s3-garage/`'s init; documented in `../core/CONFIGURATION.md` (Storage backends) for any other S3.
- **The `rclone bisync` documentation**: 1.0's two-way sync goes through WebDAV; the sync client is a `Next` feature (`../docs/docs/features.md`).

## CI and releases

- `scripts/ci.sh` (the pipeline and, `quick`, the pre-push hook): the compose files, then the smoke test against the image built for this platform. `.woodpecker/ci.yaml` builds amd64 only; `rc.yaml` (dev: `rc` tags, Gitea only) and `release.yaml` (the version tag: Gitea and Docker Hub, the Hub page from `README.md`, the Gitea release with `docker-compose.yml`, then the GitHub mirror) build both platforms.
- `scripts/release.sh`: the global template, on `VERSION`, also bumping the compose's major version.
- `README.md` and `CONTRIBUTING.md` are GitHub's and Docker Hub's pages: absolute links, nothing pointing to the private Gitea or `docs`. `theca-cloud` stands for the GitHub organization until it exists.
- Woodpecker sometimes fails on its own (a clone, a canceled run): a new commit, or a restarted step, gets it going.

@README.md
