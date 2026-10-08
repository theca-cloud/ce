# Caddy

[Caddy](https://caddyserver.com/) in front of Theca, in the same compose: HTTPS certificates from Let's Encrypt, obtained and renewed by itself. Only Caddy is published (ports 80 and 443); the server isn't reachable without it.

## Set up

Your domain's DNS points to this machine, ports 80 and 443 open. Next to `docker-compose.yml`, copy `compose.caddy.yml` and the `Caddyfile`, and add the domain to `.env`:

```sh
PUBLIC_URL=https://cloud.example.com
DOMAIN=cloud.example.com
```

```sh
docker compose -f docker-compose.yml -f compose.caddy.yml up -d
```

The server trusts Caddy's `X-Forwarded-For` (`TRUSTED_PROXIES`, its fixed address in the network): rate limits and logs see the clients' addresses.

## With S3 or Authelia

Each needs its own address: `S3_DOMAIN` (Garage, [`s3-garage/`](../s3-garage)) or `AUTH_DOMAIN` (Authelia, [`authelia/`](../authelia)) in `.env`, its block uncommented in the `Caddyfile`, and its domain added to Caddy's `aliases` in `compose.caddy.yml` (the server reaches it through Caddy, inside the network). Add every overlay to the command:

```sh
docker compose -f docker-compose.yml -f compose.s3.yml -f compose.caddy.yml up -d
```

## Another proxy

Caddy and Traefik have no request body limit by default. nginx has (1 MB): set `client_max_body_size 0;` and `proxy_request_buffering off;`, or uploads through WebDAV fail.
