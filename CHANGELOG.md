# Changelog

## [1.2.1] - 2026-10-28

### Documentation

- Screenshots of a branched file's versions and a filled trash, all from a local instance

## [1.2.0] - 2026-10-27

### Features

- Core 1.1.0 and web 1.2.0

### Fixes

- **ci**: A change to rc.yaml alone runs the checks, then the rc

### Documentation

- **claude**: Linting the pipelines, and checking what a push starts

### Build and CI

- Release candidates for amd64 only, the build cache kept between runs

## [1.1.0] - 2026-10-17

### Features

- Web 1.1.0, the Theca mark

### Fixes

- **ci**: OPERATING.md's copy check refuses a missing marker

## [1.0.1] - 2026-10-16

### Documentation

- A README for users with a live demo, OPERATING.md for operators

## [1.0.0] - 2026-10-16

### Features

- CE built from source, published as thecacloud/ce (**breaking**)
- Core 1.0.0 and web 1.0.0, their sources from GitHub

## [0.2.0] - 2026-10-12

### Features

- Web 0.4.0 (core 0.19.0)
## [0.1.0] - 2026-10-08

### Features

- The CE image, its smoke test and release tooling
- Web 0.2.0 (core 0.17.0)
- The compose, with Postgres and secrets as read-only files
- Examples, S3 with Garage, Caddy, Traefik, OIDC with Authelia
- Web 0.3.0 (core 0.18.0), files keep their times; bisync tested

### Fixes

- Web 0.2.1 (core 0.17.1)
- Web 0.3.1, a file's page shows its modification time

### Documentation

- Bootstrap the ce repository
- Postgres 18+, as core's configuration says
- README and SELF-HOSTING.md, screenshots taken by a script
