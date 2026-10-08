# Traefik

[Traefik](https://traefik.io/) in front of Theca, in the same compose: HTTPS certificates from Let's Encrypt, routes from the containers' labels. Only Traefik is published (ports 80 and 443).

## Set up

Your domain's DNS points to this machine, ports 80 and 443 open. Next to `docker-compose.yml`, copy `compose.traefik.yml`, and add to `.env`:

```sh
PUBLIC_URL=https://cloud.example.com
DOMAIN=cloud.example.com
ACME_EMAIL=you@example.com
```

```sh
docker compose -f docker-compose.yml -f compose.traefik.yml up -d
```

Traefik reads the Docker socket (read-only) to find the labels. The entrypoint's read timeout is lifted: Traefik's default (60 s) cuts large WebDAV uploads. The server trusts Traefik's `X-Forwarded-For` (`TRUSTED_PROXIES`, its fixed address in the network).

## With S3 or Authelia

Each needs its own address and router. In `compose.traefik.yml`, add the service's labels and its domain to Traefik's `aliases` (the server reaches it through Traefik, inside the network); `S3_DOMAIN` or `AUTH_DOMAIN` in `.env`:

```yaml
  garage:
    labels:
      - traefik.enable=true
      - traefik.http.routers.garage.rule=Host(`${S3_DOMAIN}`)
      - traefik.http.routers.garage.entrypoints=websecure
      - traefik.http.routers.garage.tls.certresolver=letsencrypt
      - traefik.http.services.garage.loadbalancer.server.port=3900
```

Authelia's are the same with `authelia`, `${AUTH_DOMAIN}` and port `9091`. Then every overlay in the command:

```sh
docker compose -f docker-compose.yml -f compose.s3.yml -f compose.traefik.yml up -d
```
