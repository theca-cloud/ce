@../docs/CLAUDE.md

# This repo: `ce`

The Community Edition: the CE image, **built from `core`'s and `web`'s sources** (`../docs/docs/adr/0001-ce-built-from-source.md`), and what a self-hoster needs to run it. Its version is the **product version** users see (CE 1.3 = some `core` + some `web`). Published as `thecacloud/ce` on Docker Hub (and on Gitea, which `theca.pband.ch` pulls); the repository is mirrored to GitHub.

## What it builds

- **Two pins in the `Dockerfile`**: `CORE_VERSION` and `WEB_VERSION`, the release tags fetched from GitHub. The build refuses a pair where `web`'s `package.json` doesn't pin `@theca/client` at the core being built. A `core` hotfix reaches the CE through a `web` patch release bumping its pin, then both pins here.
- **The stages**: the WASM client (`wasm-pack`) and the web app (Node, with that client in place of the registry's, never reaching Gitea) on the build platform, their output being the same whatever the CPU; the server **compiled natively for each architecture**, against glibc (arm64 under QEMU on the amd64 agent: about 30 minutes, at release only, and only when core's pin changed: release candidates build amd64 only, and every stage is cached between runs, `ce-buildcache:rc` and `:release` on Gitea); `distroless/cc`, nonroot (the binary, `/web`, `WEB_DIR`, `HEALTHCHECK`, entrypoint).
- **Local sources**: `docker buildx build --build-context core-src=<dir> --build-context web-src=<dir> .` (`scripts/smoke.sh` takes them as `CORE_SRC` and `WEB_SRC`), or folders of the build context with `--build-arg CORE_SOURCE=<dir> --build-arg WEB_SOURCE=<dir>`. Clean exports, never a working tree (`target/` is gigabytes).
- The server: `../core/CONFIGURATION.md` (environment for what it needs to start, secrets only as `X__FILE`; everything else is an instance setting), copied into `OPERATING.md`'s configuration reference by `scripts/operating.sh` at the pinned `core` (CI refuses a stale copy). It runs its migrations at startup, has `theca-server healthcheck` for Docker's `HEALTHCHECK` (no `curl` in the image), and prints the first-run setup link in its logs.

## What it ships

- **Linting the pipelines**: `woodpecker-cli lint --plugins-privileged woodpeckerci/plugin-docker-buildx:5.0.0 .woodpecker/*.yaml` (the server trusts it; without the flag, lint rejects the image steps). A change to a pipeline's `when`, or to a file another pipeline's `when` names, can start nothing: check which pipelines a push will run (`rc.yaml` waits on `ci.yaml`).
- **The CE image**, amd64 and arm64 (arm64: self-hosters on a Raspberry Pi).
- **A compose** naming the major version (`thecacloud/ce:1`), with Postgres (18+ with the built-in `C.UTF-8` collation, or the server refuses to start) and the filesystem storage; **`examples/`** around it: S3 with Garage, Caddy, Traefik, OIDC with Authelia.
- **The S3 buckets' CORS rule**: browsers upload and download chunks through presigned URLs on the bucket's origin, so the bucket must allow `PUT` and `GET` from `PUBLIC_URL`, the signed headers (`x-amz-checksum-sha256`, `If-None-Match`), and expose `ETag`. Set up by `examples/s3-garage/`'s init; documented in `OPERATING.md` (S3 storage) for any other S3.
- **The `rclone bisync` documentation**: 1.0's two-way sync goes through WebDAV; the sync client is a `Next` feature (`../docs/docs/features.md`).

## CI and releases

- `scripts/ci.sh` (the pipeline and, `quick`, the pre-push hook): the compose files, then the smoke test against the image built for this platform. `.woodpecker/ci.yaml` builds amd64 only; `rc.yaml` (dev: `rc` tags, Gitea only) and `release.yaml` (the version tag: Gitea and Docker Hub, the Hub page from `OPERATING.md`, the Gitea release with `docker-compose.yml`, then the GitHub mirror) build both platforms.
- `scripts/release.sh`: the global template, on `VERSION`, also bumping the compose's major version.
- **Two documents, two audiences**: `README.md` for users (GitHub: what Theca is, the demo at `demo.theca.rs`), `OPERATING.md` for operators (Docker Hub's page, at most 25,000 characters: CI checks it). Both, and `CONTRIBUTING.md`, use absolute links and point to nothing private (Gitea, `docs`). The demo itself is a deployment elsewhere, not in this repository.
- Woodpecker sometimes fails on its own (a clone, a canceled run): a new commit, or a restarted step, gets it going.

@README.md
