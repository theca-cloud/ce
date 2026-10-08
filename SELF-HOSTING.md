# Self-hosting Theca

From an empty folder to a running instance, then what keeps it running: the reverse proxy, S3 storage, logging in with OIDC, WebDAV and sync, backups, upgrades. Every command here was run, most of them at every change by the CE's tests (`scripts/smoke.sh`).

**Contents**: [What you need](#what-you-need) · [Install](#install) · [The reverse proxy](#the-reverse-proxy) · [S3 storage](#s3-storage) · [Logging in with OIDC](#logging-in-with-oidc) · [A private CA](#a-private-ca) · [Email](#email) · [WebDAV and sync](#webdav-and-sync) · [Backups](#backups) · [Upgrades](#upgrades) · [Troubleshooting](#troubleshooting)

## What you need

- **Docker** with Compose (v2.24 or later), on amd64 or arm64 (a Raspberry Pi 4 or 5 does).
- **A domain with HTTPS**, through a reverse proxy: **required**, not advised. The web app downloads files through a Service Worker, which browsers only allow on HTTPS. Only `localhost` is exempt: enough to try it on your own computer, not to use it from anywhere else.
- **Disk** for your files (or an S3 storage), and some room in the container's temporary folder: a file uploaded through WebDAV is written there before being stored, so it needs as much free space as the largest files uploaded at once.

## Install

In an empty folder, the release's compose:

```sh
curl -fsSLO https://git.pband.ch/theca/ce/releases/download/v0.1.0/docker-compose.yml
```

It runs Theca (the server and the web app, one image) and Postgres. The address users open goes in `.env`:

```sh
echo PUBLIC_URL=https://cloud.example.com > .env
```

### The secrets

Secrets are **files**, never environment variables (they'd leak through `docker inspect`, logs and child processes). Each one is mounted read-only into the containers that need it, from `./secrets/`:

```sh
mkdir secrets
openssl rand -hex 24 > secrets/postgres_password
echo "postgres://theca:$(cat secrets/postgres_password)@postgres:5432/theca" > secrets/database_url
openssl rand -hex 32 > secrets/server.key
openssl rand -hex 32 > secrets/data.key
chmod 644 secrets/*
```

| File | What it is |
|---|---|
| `postgres_password` | The database's password, read by Postgres. |
| `database_url` | How the server reaches the database, the same password in it. |
| `server.key` | Signs the server's own download and upload links. Changing it only breaks the links in flight. |
| `data.key` | Encrypts the secrets stored in the database (two-factor keys). **Never change it, never lose it**: without it, every user sets up two-factor authentication again. |

The files are readable by everyone on the host (`644`) because the server runs as its own user (uid 65532), not yours. Keep the folder itself private: `chmod 700 secrets`, owned by you, works, as Docker mounts the files as root.

The server refuses to start with a missing or empty secret, and says which one.

### First start

```sh
docker compose up -d
docker compose logs theca
```

The logs end with the **setup link**:

```
not set up yet: open https://cloud.example.com/setup?token=…
```

Open it (behind your proxy, see below) and create the admin, your organization and the storage: **"A folder on the server"** with the path **`/data/files`**, the volume the compose gives it. More storages can be added later in **Administration → Storages**.

The token is only in memory: a restart prints a new link, and the old one stops working. The setup can't be done twice.

The files live in two Docker volumes, `theca_db` (the database) and `theca_data` (the files). A folder of yours instead of a volume works too, owned by the server's user: `sudo chown 65532:65532 /srv/theca-files`, then `- /srv/theca-files:/data` in the compose's `volumes`.

## The reverse proxy

The server listens on `127.0.0.1:8080`, plain HTTP: only a proxy on the same machine reaches it. The proxy must:

- **Serve HTTPS** for `PUBLIC_URL`'s domain.
- **Not limit request bodies**: uploads through WebDAV are whole files.
- **Not cut long requests**: a large file takes a while, up or down.
- **Pass the client's address** in `X-Forwarded-For`, and the server must trust the proxy for it (`TRUSTED_PROXIES`): rate limits and logs then see each client, not the proxy.

Ready-made, in Docker next to Theca, with Let's Encrypt certificates: **[examples/caddy/](examples/caddy)** and **[examples/traefik/](examples/traefik)** (both tested at every change, behind HTTPS). Only the proxy is then published.

With a proxy already on the machine, point it at `127.0.0.1:8080`. For nginx:

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    client_max_body_size 0;
    proxy_request_buffering off;
    proxy_buffering off;
    proxy_read_timeout 1h;
    proxy_send_timeout 1h;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

The server then sees the proxy coming from the compose network's gateway: trust it in `docker-compose.yml` (the line is there, commented out):

```sh
docker network inspect theca_default --format '{{(index .IPAM.Config 0).Gateway}}'
```

```yaml
      TRUSTED_PROXIES: 172.18.0.1   # what the command printed
```

## S3 storage

Instead of a folder on the server, any S3-compatible storage: Garage, MinIO, a provider. Browsers then upload and download straight to it, with links the server signs, so it needs **its own HTTPS address** (e.g. `s3.example.com`) and **a CORS rule** allowing your `PUBLIC_URL` (methods `PUT` and `GET`, headers `x-amz-checksum-sha256` and `If-None-Match`, `ETag` exposed). The server reaches the storage at that same address.

**[examples/s3-garage/](examples/s3-garage)** runs [Garage](https://garagehq.deuxfleurs.fr/) next to Theca and sets everything up: the bucket, its key, the CORS rule, at every start. For another S3 storage, the rule's XML is in core's [CONFIGURATION.md](https://git.pband.ch/theca/core/src/branch/prod/CONFIGURATION.md) (Storage backends).

Each library keeps the storage it was created on; the default one is chosen in **Administration → Storages**. The key files are paths the server reads (`/run/secrets/...`), never values: mount them as secrets, as the example does.

## Logging in with OIDC

An identity provider (Authelia, Authentik, Keycloak, Google, Microsoft...) can log users in. Two kinds:

- **For the whole instance**, added in **Administration → Login providers**: listed on the login page, its sessions reach everything the account can.
- **For one organization**, added by its owner in its settings: its sessions only ever reach that organization, whatever the provider says about the user. An organization runs its own provider; it never reaches anyone's other organizations or account.

An existing account links a provider from **Account → Ways to log in**. The setting `oidc_link_by_email` links it automatically by email instead, when the provider says the email is verified (an organization's provider only links that organization's members).

**[examples/authelia/](examples/authelia)** sets up Authelia as the instance's provider (tested at every change, a login included); its README gives the order (the provider in Theca first, for its callback URL).

## A private CA

If the server reaches your S3 storage or identity provider behind certificates from your own certificate authority, it must trust it. `SSL_CERT_FILE` names the certificates it trusts, **replacing** the public ones: give it both.

```sh
cat /etc/ssl/certs/ca-certificates.crt my-ca.pem > secrets/ca-bundle.pem
```

```yaml
  theca:
    environment:
      SSL_CERT_FILE: /run/secrets/ca-bundle.pem
    secrets: [database_url, server.key, data.key, ca-bundle.pem]

secrets:
  ca-bundle.pem:
    file: ./secrets/ca-bundle.pem
```

(The CE's tests run Garage and Authelia behind a CA of their own this way.)

## Email

Theca sends emails for invitations, registration and forgotten passwords. Without SMTP, they wait (and registration stays closed). In **Administration → Settings**: `smtp_host`, `smtp_port`, `smtp_tls`, `smtp_username`, `smtp_from`, and `smtp_password_file`: the password is a file, mounted like the other secrets (e.g. `/run/secrets/smtp_password`). Changes apply without a restart.

## WebDAV and sync

The drive is at **`https://cloud.example.com/dav/`**. Log in with any username and an **app password** (**Account → App passwords**: for everything, one organization or one library, read-only if you like), never your account's password. It lists your organizations, then their libraries ("My files" for your own).

- **macOS**: Finder, Go → Connect to Server (⌘K).
- **Windows**: Explorer, Map network drive (or a client such as Cyberduck or WinSCP).
- **Linux**: your file manager (`davs://cloud.example.com/dav/`), or `davfs2`.
- **Phones**: the Files app's network locations, or any WebDAV client.

### Two-way sync with rclone

A folder kept in sync both ways with a library, with [rclone](https://rclone.org/)'s `bisync`. Set up once (`vendor = owncloud` makes rclone send and trust files' modification times, which Theca keeps):

```sh
rclone config create theca webdav url=https://cloud.example.com/dav/ vendor=owncloud \
    user=me pass="$(rclone obscure 'the app password')"
```

The first run, with `--resync`, makes both sides the union of the two:

```sh
rclone bisync ~/Documents theca:Acme/Documents --resync
```

Then the same without `--resync`, as often as you like: each run brings the changes from both sides since the last one (new files, edits, deletions). A timer runs it, e.g. every 15 minutes with cron (`crontab -e`):

```
*/15 * * * * rclone bisync ~/Documents theca:Acme/Documents >> ~/.cache/rclone-theca.log 2>&1
```

What to know:

- **A file changed on both sides** between two runs is kept twice, on both sides: `report.txt.conflict1` (your folder's) and `report.txt.conflict2` (Theca's). Nothing is lost; you pick, and delete the other.
- **Deletions sync too**, both ways (into Theca's trash, where they stay restorable).
- bisync keeps its state in `~/.cache/rclone/bisync`. If a run stops halfway, the next refuses until you check both sides and run `--resync` again.
- A run is a snapshot, not a live sync: what changes during a run waits for the next one.

## Backups

Three things, all needed together to restore:

1. **The database**: names, folders, versions, accounts.
2. **The files**: the `theca_data` volume (or your S3 bucket).
3. **`secrets/`**, for `data.key` above all.

```sh
docker compose exec -T postgres pg_dump -U theca -Fc theca > theca.dump
docker run --rm -v theca_data:/data:ro -v "$PWD":/backup alpine tar czf /backup/files.tar.gz -C /data .
tar czf secrets.tar.gz secrets
```

Take the database first, then the files: a file uploaded in between is in the files and not yet in the database (harmless, cleaned up later); the other order could miss files the database knows.

**Restoring**, into an empty folder with the same `docker-compose.yml` and `.env`:

```sh
tar xzf secrets.tar.gz
docker run --rm -v theca_data:/data -v "$PWD":/backup alpine tar xzf /backup/files.tar.gz -C /data
docker compose up -d postgres
docker compose exec -T postgres pg_restore -U theca -d theca < theca.dump
docker compose up -d
```

(Compose then warns that the `theca_data` volume already existed: expected, it's the restored one.)

## Upgrades

**Before 1.0**, the compose names an exact version, and an upgrade is a choice: read the release notes first. Until 1.0, **an upgrade may mean starting over**, the database's structure still changing between releases: copy your files out (WebDAV, rclone), install the new release in a new folder, copy them back in. The notes say when it's the case.

**From 1.0**, the compose names the major version (`ce:1`): `docker compose pull && docker compose up -d`, the database upgraded at startup. A failed upgrade changes nothing (it runs in one transaction).

**Postgres** is pinned to its major version (18): minor updates come with `docker compose pull`. A new major version needs its data converted: back up the database (above), point the compose at the new image with a new volume, restore.

## Troubleshooting

- **"missing environment variable" or "cannot read secret file"**: a secret is missing or misnamed (see [The secrets](#the-secrets)). **"…is empty"**: a secret file has nothing in it.
- **The server refuses Postgres's collation**: the database was created without `--locale-provider=builtin --builtin-locale=C.UTF-8`, which the compose sets. It's only read when the database is created: a volume from another setup keeps its old collation.
- **`PUBLIC_URL` is missing**: `.env` isn't next to `docker-compose.yml`, or lacks the line.
- **The setup link is lost**: `docker compose restart theca`, then the logs: a new link.
- **Downloads fail in the browser**: the page isn't on HTTPS (the Service Worker), see [What you need](#what-you-need).
- **Uploads fail through WebDAV, with a proxy in front**: its body size limit or timeout (nginx's default limit is 1 MB), see [The reverse proxy](#the-reverse-proxy).
- **Uploads fail in the browser, with S3**: the bucket's CORS rule, or its address unreachable from the browser.
- **Everyone shares one rate limit**: the proxy isn't in `TRUSTED_PROXIES`, so every request seems to come from it.
