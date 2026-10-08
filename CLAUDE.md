@../docs/CLAUDE.md

# This repo: `ce`

The Community Edition: **assembly only** (`../docs/decisions.md`, Repository, CI and releases). It builds nothing of its own: it puts the published `core` and `web` images together into the CE image, and ships what a self-hoster needs to run it. Its version is the **product version** users see (CE 1.3 = some `core` + some `web`).

Nothing is built yet: the first session drafts `roadmap/00. global.md` with the user (`../docs/ROADMAP.md`, item 4), then one file per step, each written right before implementing it, as in `../core/roadmap/` and `../web/roadmap/`.

## What it assembles

- **One pin: the `web` version.** `web` pins `core` (the exact `@theca/client` in its `package.json`) and says so: the label `org.theca.core` on its image (readable from the registry without pulling: `docker buildx imagetools inspect git.pband.ch/theca/web:<v>`), and "Built for core X" in its release notes. `ce` takes its `core` from there, never pins it a second time (decisions.md: `web` pins `core`, `ce` pins only `web`). A `core` hotfix reaches the CE through a `web` patch release.
- **`git.pband.ch/theca/web:<v>`**: `FROM scratch`, the app's static build in `/web/`, nothing to run (`../web/README.md`, The image).
- **`git.pband.ch/theca/core:<v>`**: the server binary (`theca-server`), serving the API, WebDAV and, with `WEB_DIR`, the web build on the same origin. Its configuration: `../core/CONFIGURATION.md` (environment for what the server needs to start, secrets only as `X__FILE`; everything else is an instance setting in the database, changed from the admin's pages). It runs its migrations at startup, has a `theca-server healthcheck` subcommand for Docker's `HEALTHCHECK` (the images ship no `curl`), and prints the first-run setup link (`/setup?token=`) in its logs.
- **Images for amd64 and arm64** (arm64: self-hosters on a Raspberry Pi).

## What it ships (V1, `../docs/ROADMAP.md` item 4)

- **The CE image**: `core`'s binary and `web`'s build, `WEB_DIR` set. Its CI tests the pair before publishing (decisions.md).
- **A compose** with Postgres (17+, the built-in `C.UTF-8` collation: `../core/CONFIGURATION.md`) and Garage (S3).
- **The S3 buckets' CORS rule**: browsers upload and download chunks through presigned URLs on the bucket's origin, so the bucket must allow `PUT` and `GET` from `PUBLIC_URL`, the signed headers (`x-amz-checksum-sha256`, `If-None-Match`), and expose `ETag` (decisions.md, Web app: no CORS on the server). Set up by the compose. **Gap**: decisions.md says it's documented in `../core/CONFIGURATION.md`, which doesn't have it yet: a `core` docs change (its own branch and commit).
- **The `rclone bisync` documentation**: V1's two-way sync goes through WebDAV (`../docs/features.md`); the sync client is V2.

## Prior art to start from

- `../core/try/`: `run.sh` and a compose running the released server with Postgres, set up, for a WebDAV client: the closest thing to a CE today (not for real data: no TLS, a fixed admin password).
- `../web/scripts/dev.sh` and `../web/.woodpecker/ci.yaml`: core with Postgres and Mailpit, the web build served through `WEB_DIR`, a second never-set-up server.
- **Tooling** as in `../web` (copied from `cli`, where it was debugged): `scripts/ci.sh` (what the pipelines and the pre-push hook call), `.woodpecker/` (path filters; the release merge into `dev` skipped), `scripts/release.sh` and `release-ci.sh` (`git-cliff` changelog, tags, the image, the Gitea release). Woodpecker sometimes fails on its own (a clone, a canceled run): a new commit, or a restarted step, gets it going.

@README.md
