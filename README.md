# Theca

**Your files, on your server.** Theca is a self-hosted cloud storage: a web app, a drive your computer and phone mount over WebDAV, and every file's history, in one Docker image.

## Why Theca

- **Storage that doesn't repeat itself.** Files are cut into chunks, and a chunk is stored once across the libraries that trust each other: a copy, a renamed file or a new version of a large file only stores what changed.
- **Your files skip the server.** With S3 storage, the web app uploads and downloads chunks straight to the bucket through short-lived signed URLs; the server only decides who may do what.
- **Nothing is overwritten.** Every version is kept, as a tree: restore an old one and keep working, and two people editing at once both keep their work.

![The file browser](https://raw.githubusercontent.com/theca-cloud/ce/main/screenshots/browse.png)

## Try the demo

**[demo.theca.rs](https://demo.theca.rs)**, log in as `demo@theca.rs` / `thecademo`. It's shared and reset every hour: upload, edit, restore versions, empty the trash. To keep it usable for everyone, changing the account's password, turning on two-factor authentication and deleting the account are blocked, and its storage is capped at 100 MB.

## Run it

```sh
curl -fsSLO https://raw.githubusercontent.com/theca-cloud/ce/main/docker-compose.yml
# the commands at the top of docker-compose.yml: .env and the secrets
docker compose up -d && docker compose logs theca   # the setup link
```

**Run it yourself**: [OPERATING.md](https://github.com/theca-cloud/ce/blob/main/OPERATING.md) (also the [Docker Hub page](https://hub.docker.com/r/thecacloud/ce)) covers HTTPS, S3, OIDC, WebDAV and sync, every setting, backups and upgrades. Ready-made setups: [examples/](https://github.com/theca-cloud/ce/tree/main/examples) (Garage, Caddy, Traefik, Authelia).

<details>
<summary><b>Everything it does</b></summary>

- **Libraries** of files and folders, owned by an organization: yours ("My files"), your family's, your team's, each with its members, readers or writers.
- **Versions**: each upload adds one; any version is previewed, downloaded or made current again.
- **A trash**, restorable until it's purged (30 days by default).
- **Previews** of images, PDFs, videos, music and text, in the browser.
- **A network drive** over WebDAV (Finder, Windows Explorer, Linux file managers, phones), and **two-way sync** with `rclone bisync`.
- **Your disk, or S3** (Garage, MinIO, AWS, Backblaze...), chosen per library; optional compression.
- **Logging in your way**: passwords with two-factor authentication (TOTP), or your identity provider (OIDC: Authelia, Authentik, Keycloak, Google, Microsoft...); app passwords for WebDAV and scripts.
- **Organizations** for groups and companies: members, libraries, their own login provider, a quota. A company keeps its files when someone leaves.
- **Search** by name, across everything you can reach.
- **Admin pages**: accounts, organizations, storages, login providers, settings, background jobs; Prometheus metrics.
- **Your data, yours**: export everything, delete your account.

| | |
|---|---|
| ![A file's preview and versions](https://raw.githubusercontent.com/theca-cloud/ce/main/screenshots/file.png) | ![Search](https://raw.githubusercontent.com/theca-cloud/ce/main/screenshots/search.png) |
| ![An organization's settings](https://raw.githubusercontent.com/theca-cloud/ce/main/screenshots/organization.png) | ![The admin's settings](https://raw.githubusercontent.com/theca-cloud/ce/main/screenshots/admin.png) |

</details>

## Status

**Stable since 1.0**: upgrades keep your data, migrated forward at startup and tested against every earlier release's data; nothing you rely on breaks within a major version (`thecacloud/ce:1`). This is the **Community Edition**, free and complete; a hosted service and an Enterprise Edition will come later.

The image is built from this repository's `Dockerfile`, from source ([core](https://github.com/theca-cloud/core), the server, and [web](https://github.com/theca-cloud/web), the web app): `docker build .` rebuilds it. Contributing: [CONTRIBUTING.md](https://github.com/theca-cloud/ce/blob/main/CONTRIBUTING.md). License: AGPL-3.0.
