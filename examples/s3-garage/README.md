# S3 storage with Garage

Theca's files on [Garage](https://garagehq.deuxfleurs.fr/), a self-hosted S3 server, instead of the filesystem storage. Browsers then upload and download straight to Garage, with presigned URLs; Garage needs **its own HTTPS address** (e.g. `s3.example.com`) through your reverse proxy, which the server reaches too.

## Set up

Next to `docker-compose.yml`, copy `compose.s3.yml`, `garage.toml` and `garage-init.sh`, then add the secrets:

```sh
echo "GK$(openssl rand -hex 12)" > secrets/s3_access_key
openssl rand -hex 32 > secrets/s3_secret_key
openssl rand -hex 32 > secrets/garage_rpc_secret
openssl rand -hex 32 > secrets/garage_admin_token
chmod 644 secrets/s3_*
chmod 600 secrets/garage_*   # Garage refuses world-readable secrets
```

Start with both files:

```sh
docker compose -f docker-compose.yml -f compose.s3.yml up -d
```

At every start, `garage-init` prepares Garage: the node's layout, the bucket `theca`, your key, and the bucket's **CORS rule** (browsers may `PUT` and `GET` from `PUBLIC_URL`). It changes nothing that's already there, and follows a new `PUBLIC_URL` at the next start.

Your proxy serves Garage's address from `127.0.0.1:3900` (with [`caddy/`](../caddy) or [`traefik/`](../traefik): uncomment their S3 parts).

## In the setup

Choose "An S3 bucket":

| Field | Value |
|---|---|
| Endpoint | `https://s3.example.com` (Garage's address) |
| Region | `garage` |
| Bucket | `theca` |
| Access key file | `/run/secrets/s3_access_key` |
| Secret key file | `/run/secrets/s3_secret_key` |
| Path-style URLs | on |

The setup writes and reads a test object first: a wrong address or key fails there, not at the first upload.

## Another S3 server

Any S3 server works the same way: the bucket needs the CORS rule above (`AllowedOrigin` your `PUBLIC_URL`, methods `PUT` and `GET`, headers `x-amz-checksum-sha256` and `If-None-Match`, `ETag` exposed). See core's `CONFIGURATION.md`, Storage backends.
