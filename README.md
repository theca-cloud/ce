# Theca

**Your files, on your server.** Theca is a self-hosted cloud storage: a web app to browse and upload files, a drive your computer and phone mount over WebDAV, and every file's history. It runs on your hardware, from a Raspberry Pi to a server, and keeps your files on your disk or in any S3 storage.

This is the **Community Edition**: everything below, free and open source (AGPL-3.0), in one Docker image.

![The file browser](screenshots/browse.png)

## What it does

- **Libraries of files and folders**, owned by an organization: one for you ("My files"), one for your family, one for your team. Each library has its own members, readers or writers.
- **Every version kept.** Each upload of a file adds a version; any one is previewed, downloaded or made current again. Two people editing the same file at once both keep their work: the history branches instead of overwriting.
- **A trash** for what was deleted, restorable until it's purged (30 days by default).
- **Previews** of images, PDFs, videos, music and text, in the browser.
- **A network drive** over WebDAV: Finder, Windows Explorer, Linux file managers, your phone's file app. **Two-way sync** with `rclone bisync`.
- **Storage that doesn't repeat itself.** Files are split into chunks; a chunk stored once serves every file containing it, so a copy, a renamed file or a new version of a large file only stores what changed. Optional compression.
- **Your disk, or S3.** A folder on the server, or any S3-compatible storage (Garage, MinIO, AWS, Backblaze...), chosen per library.
- **Logging in your way**: passwords with two-factor authentication (TOTP), or your own identity provider (OIDC: Authelia, Authentik, Keycloak, Google, Microsoft...). App passwords for WebDAV and scripts.
- **Organizations** for groups and companies: their members, their libraries, their own login provider, their quota. A company keeps its files when someone leaves.
- **Search** by name, across everything you can reach.
- **An admin's pages**: accounts, organizations, storages, login providers, settings, background jobs. Prometheus metrics.
- **Your data, yours**: export everything, delete your account.

| | |
|---|---|
| ![A file's preview and versions](screenshots/file.png) | ![Search](screenshots/search.png) |
| ![An organization's settings](screenshots/organization.png) | ![The admin's settings](screenshots/admin.png) |

## Try it

You need Docker, and a domain with HTTPS through a reverse proxy (on your own computer, `localhost` does).

```sh
curl -fsSLO https://git.pband.ch/theca/ce/releases/download/v0.1.0/docker-compose.yml
# then the commands at the top of docker-compose.yml: .env and the secrets
docker compose up -d
docker compose logs theca   # the setup link
```

**[SELF-HOSTING.md](SELF-HOSTING.md)** says it all: the reverse proxy, S3 storage, OIDC, WebDAV and sync, backups, upgrades. Ready-made setups are in **[examples/](examples)**: Garage (S3), Caddy, Traefik, Authelia.

## Status

**Beta** (0.x). It works, and is tested end to end at every change, but until 1.0 an upgrade may mean starting over: the database's structure still changes between releases. Keep your files somewhere else too for now.

Theca also comes as a hosted service and, later, an Enterprise Edition (company features: LDAP, SAML, audit logs). The Community Edition stays complete: nothing above is held back.

## More

- How it's built and why: [the design documents](https://git.pband.ch/theca/docs).
- The parts: [core](https://git.pband.ch/theca/core) (the server), [web](https://git.pband.ch/theca/web) (the web app), [cli](https://git.pband.ch/theca/cli) (the `theca` command line).
- Contributing: [CONTRIBUTING.md](https://git.pband.ch/theca/docs/src/branch/prod/CONTRIBUTING.md).

License: AGPL-3.0.
