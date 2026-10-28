# <img src="https://raw.githubusercontent.com/theca-cloud/ce/main/logo.svg" alt="" width="36" align="top"> Running Theca

**Theca** is a self-hosted cloud storage: a web app, a WebDAV drive, every file's history, files deduplicated in chunks. What it is and why: the [README](https://github.com/theca-cloud/ce#readme). Try it first: **[the demo](https://demo.theca.rs)**, reset every hour.

This page is for operators: from an empty folder to a running instance, then what keeps it running. Most commands here run at every change in the image's tests.

## The image

`thecacloud/ce`: the server and the web app in one image, built from source ([Dockerfile](https://github.com/theca-cloud/ce/blob/main/Dockerfile): `docker build .` rebuilds it). **amd64 and arm64** (a Raspberry Pi 4 or 5 does). Distroless, runs as uid 65532, listens on 8080, plain HTTP.

| Tag | Follows |
|---|---|
| `1` | the latest 1.x: what the compose uses. An upgrade keeps your data. |
| `1.0`, `1.0.0` | a minor line, or one release |
| `latest` | the latest release, across majors |

## What you need

- **Docker** with Compose v2.24+.
- **A domain with HTTPS** through a reverse proxy: **required**. The web app downloads through a Service Worker, which browsers only allow on HTTPS (or `localhost`, enough to try it on your own computer).
- **Disk** for the files (or an S3 storage), and room in the container's `/tmp`: a WebDAV upload is written there before being stored, so as much as the largest files uploaded at once.

## Install

In an empty folder:

```sh
curl -fsSLO https://raw.githubusercontent.com/theca-cloud/ce/main/docker-compose.yml
echo PUBLIC_URL=https://cloud.example.com > .env
```

The compose runs Theca and Postgres 18 (created with `--locale-provider=builtin --builtin-locale=C.UTF-8`: the server refuses other collations).

### The secrets

Secrets are **files**, never environment variables (those leak through `docker inspect` and logs), mounted read-only from `./secrets/`:

```sh
mkdir secrets
openssl rand -hex 24 > secrets/postgres_password
echo "postgres://theca:$(cat secrets/postgres_password)@postgres:5432/theca" > secrets/database_url
openssl rand -hex 32 > secrets/server.key
openssl rand -hex 32 > secrets/data.key
chmod 644 secrets/* && chmod 700 secrets
```

| File | What it is |
|---|---|
| `postgres_password` | The database's password. |
| `database_url` | How the server reaches the database. |
| `server.key` | Signs the server's own upload and download links: changing it only breaks the links in flight. |
| `data.key` | Encrypts the secrets stored in the database (two-factor keys). **Never change it, never lose it**: without it, every user sets up two-factor authentication again. |

`644` because the server runs as its own user, not yours; the folder stays private (`700`). A missing or empty secret stops the server, naming it.

### First start

```sh
docker compose up -d
docker compose logs theca   # ends with: not set up yet: open https://cloud.example.com/setup?token=…
```

Open the link (behind your proxy) and create the admin, your organization and the storage: **"A folder on the server"**, path **`/data/files`**. The token lives in memory: a restart prints a new link. More storages later, in **Administration → Storages**.

Data lives in two volumes, `theca_db` and `theca_data`. A folder of yours works too, owned by the server's user: `sudo chown 65532:65532 /srv/theca`, then `- /srv/theca:/data`.

## The reverse proxy

The server listens on `127.0.0.1:8080`. The proxy must serve HTTPS for `PUBLIC_URL`, **not limit request bodies** (WebDAV uploads are whole files), **not cut long requests**, and pass `X-Forwarded-For`, from an address in `TRUSTED_PROXIES` (otherwise every client shares the proxy's rate limits).

Ready-made, with Let's Encrypt: [examples/caddy](https://github.com/theca-cloud/ce/tree/main/examples/caddy) and [examples/traefik](https://github.com/theca-cloud/ce/tree/main/examples/traefik). With nginx on the host:

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

The server then sees nginx at the compose network's gateway (`docker network inspect theca_default --format '{{(index .IPAM.Config 0).Gateway}}'`): set it as `TRUSTED_PROXIES` in the compose (the line is there, commented out).

## S3 storage

Any S3-compatible storage (Garage, MinIO, a provider) instead of a folder. Browsers then upload and download straight to it with links the server signs, so it needs **its own HTTPS address** (e.g. `s3.example.com`, no path prefix: it would break the signatures) and **a CORS rule** for `PUBLIC_URL`:

```xml
<CORSConfiguration><CORSRule>
  <AllowedOrigin>https://cloud.example.com</AllowedOrigin>
  <AllowedMethod>PUT</AllowedMethod><AllowedMethod>GET</AllowedMethod>
  <AllowedHeader>x-amz-checksum-sha256</AllowedHeader><AllowedHeader>if-none-match</AllowedHeader>
  <ExposeHeader>ETag</ExposeHeader><MaxAgeSeconds>3600</MaxAgeSeconds>
</CORSRule></CORSConfiguration>
```

Without it, WebDAV works but the web app's transfers fail. [examples/s3-garage](https://github.com/theca-cloud/ce/tree/main/examples/s3-garage) runs Garage next to Theca and sets up the bucket, its key and the rule. Key files are paths the server reads (`/run/secrets/…`), never values. Each library keeps the storage it was created on; the default is chosen in **Administration → Storages**.

## Logging in with OIDC

Authelia, Authentik, Keycloak, Google, Microsoft… Two kinds:

- **For the instance** (**Administration → Login providers**): on the login page, its sessions reach everything the account can.
- **For one organization** (its owner's settings): its sessions only ever reach that organization.

An account links a provider from **Account → Ways to log in**; `oidc_link_by_email` links by verified email instead. [examples/authelia](https://github.com/theca-cloud/ce/tree/main/examples/authelia) sets up Authelia.

**A private CA** (for your S3 or provider): `SSL_CERT_FILE` names the certificates the server trusts, replacing the public ones, so give it both: `cat /etc/ssl/certs/ca-certificates.crt my-ca.pem > secrets/ca-bundle.pem`, mounted as a secret, `SSL_CERT_FILE: /run/secrets/ca-bundle.pem`.

## Email

For invitations, registration and password resets. Without SMTP they wait, and registration stays closed. In **Administration → Settings**: the `smtp_*` settings below; the password is a file (`smtp_password_file`), mounted like the other secrets.

## WebDAV and two-way sync

The drive: **`https://cloud.example.com/dav/`**, any username, an **app password** (**Account → App passwords**: everything, one organization or one library, read-only if you like). macOS Finder (⌘K), Windows Explorer (map a network drive), Linux file managers (`davs://…`), phone file apps. What operating systems leave beside files (`.DS_Store`, Finder's `._*`, `Thumbs.db`, `desktop.ini`) is accepted and not stored, so Finder tags don't survive a copy.

Two-way sync with [rclone](https://rclone.org/) `bisync` (`vendor = owncloud`: modification times kept):

```sh
rclone config create theca webdav url=https://cloud.example.com/dav/ vendor=owncloud \
    user=me pass="$(rclone obscure 'the app password')"
rclone bisync ~/Documents theca:Acme/Documents --resync   # once: the union of both sides
rclone bisync ~/Documents theca:Acme/Documents            # then as often as you like (cron)
```

A file changed on both sides between runs is kept twice (`.conflict1`, `.conflict2`); deletions sync both ways (into Theca's trash); a run stopped halfway asks for `--resync` again.

## Backups

All three, together: **the database**, **the files** (`theca_data`, or your bucket), and **`secrets/`** (`data.key` above all). The database first: a file uploaded in between is then only extra, never missing.

```sh
docker compose exec -T postgres pg_dump -U theca -Fc theca > theca.dump
docker run --rm -v theca_data:/data:ro -v "$PWD":/b alpine tar czf /b/files.tar.gz -C /data .
tar czf secrets.tar.gz secrets
```

Restore, in a folder with the same compose and `.env`:

```sh
tar xzf secrets.tar.gz
docker run --rm -v theca_data:/data -v "$PWD":/b alpine tar xzf /b/files.tar.gz -C /data
docker compose up -d postgres
docker compose exec -T postgres pg_restore -U theca -d theca < theca.dump
docker compose up -d
```

## Upgrades

`docker compose pull && docker compose up -d`. The database is migrated forward at startup, in one transaction (a failure changes nothing), and every release is tested upgrading the data of the releases before it. A new major version is a choice: read its release notes, then change the tag. Postgres stays on its major (18); a new one is a dump and a restore into a new volume.

## Troubleshooting

- **"missing environment variable", "cannot read secret file", "…is empty"**: a secret is missing, misnamed or empty.
- **The collation is refused**: the database wasn't created by this compose (the collation is set at creation only).
- **The setup link is lost**: `docker compose restart theca`, then the logs.
- **Downloads fail in the browser**: not on HTTPS.
- **WebDAV uploads fail behind a proxy**: its body limit or timeout (nginx's default limit is 1 MB).
- **Browser uploads fail with S3**: the CORS rule, or the bucket's address unreachable from the browser.
- **Everyone shares one rate limit**: the proxy isn't in `TRUSTED_PROXIES`.

## Configuration reference

Copied from core's [CONFIGURATION.md](https://github.com/theca-cloud/core/blob/main/CONFIGURATION.md) at this release's core: every environment variable and setting the server reads. Settings are changed in **Administration → Settings**, without a restart.

<!-- core:CONFIGURATION.md start -->
## Environment variables

**Secrets only exist as `X__FILE`**: the variable holds the path to a file containing the value (a trailing newline is ignored). Everything else is a plain variable. The server only reads these files, never writes them (they can be read-only, e.g. Docker secrets): a missing or empty one stops it at startup, naming the variable.

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL__FILE` | yes | | File containing the PostgreSQL URL, e.g. `postgres://user:password@host:5432/theca`. PostgreSQL 18+ with the built-in `C.UTF-8` collation (`initdb --locale-provider=builtin --builtin-locale=C.UTF-8`); the server refuses to start otherwise. |
| `SERVER_KEY__FILE` | yes | | File containing the server's key: 64 hex characters, e.g. `openssl rand -hex 32`. Derives the key signing the server's own upload/download URLs: rotating it only invalidates the URLs in flight. |
| `DATA_KEY__FILE` | yes | | File containing the key encrypting secrets stored in the database (TOTP secrets): 64 hex characters, e.g. `openssl rand -hex 32`. **Back it up with the database and never change it**: without it, those secrets are lost (users must set up TOTP again). |
| `SETUP_OPEN` | no | `false` | `true`: a fresh instance's setup needs no token (the first visitor sets it up). Otherwise the server prints the setup URL, token included, in its logs at startup. |
| `TRUSTED_PROXIES` | no | | Comma-separated addresses or CIDRs of the reverse proxies in front of the server (e.g. `172.17.0.1, 10.0.0.0/8`). Their `X-Forwarded-For` gives the client's address. Unset: the peer is the client, so behind an undeclared proxy every client shares the proxy's address (and its rate limits). |
| `METRICS_ADDR` | no | | Where Prometheus metrics are served (`/metrics`), e.g. `127.0.0.1:9090` or an internal address. Unset: no metrics. Never the public port. |
| `WEB_DIR` | no | | A directory of static files served for every path the API doesn't use (the web app's build; `index.html` for unknown paths, as a single-page app needs). Unknown `/api/` and `/dav/` paths stay `404`. Set by the CE image. |
| `PUBLIC_URL` | yes | | The URL clients reach the server at, e.g. `https://cloud.example.com`. Used in links and in the server's own presigned URLs. |
| `LISTEN_ADDR` | no | `0.0.0.0:8080` | Address and port the server listens on. |
| `RUST_LOG` | no | `info` | Log filter (`tracing` syntax), e.g. `info,theca_core=debug`. |

## Instance settings

Changed in the web app's **Administration → Settings**, or through the admin API (`PATCH /api/v1/admin/settings`), which validates them and applies them at once, without a restart. Stored as strings in the `setting` table and typed by the server. A missing key takes its default; an invalid value is refused by the API (and stops the server at startup if written to the database by hand); an unknown key is logged as a warning.

| Key | Default | Description |
|---|---|---|
| `instance_name` | `Theca` | Shown in emails and the web app. |
| `gc_grace_period_secs` | `86400` (24 h) | How long an unreferenced chunk, untouched, is kept before garbage collection deletes it (abandoned uploads). |
| `presigned_url_lifetime_secs` | `900` (15 min) | How long presigned upload and download URLs stay valid. |
| `max_pending_uploads` | `15` | Most chunks a user may have being uploaded at once (declared, upload URL still valid, not uploaded yet). Requesting more upload URLs is refused (`429`); clients read it (`GET /api/v1/limits`) and size their upload window by it, so raising it speeds every client up, lowering it never makes them fail. |
| `registration` | `closed` | `open`: anyone can create an account (verified by email, so it needs SMTP). `closed`: accounts come from invitations (and the setup). |
| `password_strength` | `3` | The zxcvbn score (0 to 4) a new password needs, wherever one is chosen (registration, setup, reset, invitation, change), the account's email counting against it. `0`: no score asked. At least 8 characters at every level. The web app shows the same score as the user types (`GET /api/v1/instance` gives the level). |
| `organization_creation` | `anyone` | `anyone`: every account can create company organizations (and owns them). `admins`: only instance admins (the admin API creates them for others). |
| `smtp_host` | | The SMTP server. Unset: emails stay queued (and registration and invitations are unavailable). Changes apply to the next sending run, no restart needed. |
| `smtp_port` | `587` | Its port. |
| `smtp_tls` | `starttls` | `starttls` (587), `tls` (465), or `none` (a server on the same host or network only). |
| `smtp_username` | | Login, if the server needs one. |
| `smtp_password_file` | | Path to a file holding the SMTP password (never the password itself). |
| `smtp_from` | | The sender, e.g. `Theca <noreply@example.com>`. Required with `smtp_host`. |
| `rate_limit_login_ip` | `30/300` | Login attempts from one client address: count/seconds. Beyond: `429` with `Retry-After`. Limits slow guessing down; none locks anyone out for good. |
| `rate_limit_login_account` | `10/300` | **Failed** logins on one account (a user logging in normally is never slowed down). |
| `rate_limit_totp` | `10/300` | Failed TOTP or recovery codes on one account. |
| `rate_limit_email_address` | `5/3600` | Emails asked for one address (registration, verification, password reset). |
| `rate_limit_email_ip` | `30/3600` | Emails asked from one client address. |
| `rate_limit_setup_ip` | `10/60` | Setup attempts from one client address (the setup token). |
| `rate_limit_invitations` | `100/3600` | Members added to one organization. |
| `job_chunk_gc_interval_secs` | `3600` (1 h) | How often unreferenced chunks are collected. |
| `job_trash_purge_interval_secs` | `3600` (1 h) | How often the trash past its retention is purged. |
| `job_cleanup_interval_secs` | `86400` (24 h) | How often expired tokens, invitations, unverified accounts, old emails and job history are cleaned. |
| `job_orphan_check_interval_secs` | `86400` (24 h) | How often storage backends are checked for objects without a row. |
| `job_email_send_interval_secs` | `30` | How often queued emails are sent. |
| `trash_retention_secs` | `2592000` (30 days) | How long trashed files and folders stay restorable; then the hourly purge deletes them for good (their chunks follow with the garbage collection). `0`: purged at the next run. |
| `session_idle_lifetime_secs` | `604800` (7 days) | A session expires after this long without being used (each use extends it). At least `600`. Applies to existing sessions at once. |
| `oidc_link_by_email` | `false` | Logging in through an OIDC provider with an identity not linked yet links it to the account with the same email, if the provider says that email is verified. Off: identities are only linked by their owner, from a session. Turn on only if you trust every provider's email verification. An organization's provider only links that organization's members (an invitation isn't enough), and only opens sessions restricted to it. |
| `oidc_allow_internal_issuers` | `false` | Organizations' identity providers may use `http` and internal addresses (private networks, localhost). Off, an organization's issuer must be `https` and resolve to public addresses only, so an organization's owner can't make the server call into its own network. Turn on only when every organization on the instance is trusted (e.g. a single company's install with its Keycloak inside). Instance-wide providers are never restricted. |
| `session_max_lifetime_secs` | `0` (no cap) | A session expires this long after login, even if used every day (users log in again). At least `600`, or `0` for no cap. |
<!-- core:CONFIGURATION.md end -->
