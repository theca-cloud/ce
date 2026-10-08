# OIDC with Authelia

[Authelia](https://www.authelia.com/) as an identity provider for the whole instance: users log in to Theca through it. It needs its own HTTPS address (e.g. `auth.example.com`), so it goes with a proxy example ([`caddy/`](../caddy) or [`traefik/`](../traefik): uncomment or add its part, and its domain in the proxy's `aliases`).

## Set up

Next to `docker-compose.yml`, copy `compose.authelia.yml`, `authelia.yml` and `users.yml`, then the secrets:

```sh
for s in session_secret storage_key oidc_hmac reset_jwt; do openssl rand -hex 32 > secrets/authelia_$s; done
openssl genrsa -out secrets/authelia_jwks_key 2048
openssl rand -hex 32 > secrets/oidc_client_secret
docker run --rm authelia/authelia:4.39 authelia crypto hash generate pbkdf2 --variant sha512 \
    --password "$(cat secrets/oidc_client_secret)" | sed -n 's/^Digest: //p' > secrets/oidc_client_secret_hash
chmod 600 secrets/authelia_* secrets/oidc_client_secret_hash
chmod 644 secrets/oidc_client_secret   # read by Theca too
```

In `users.yml`, the users and their password hashes (the command is in the file).

## The order

The client's callback URL holds the provider's ID, known once the provider exists in Theca:

1. `AUTH_DOMAIN=auth.example.com` in `.env`; start Theca (with the proxy) **without** Authelia yet.
2. In Theca, **Administration → Login providers**, add one: issuer `https://auth.example.com`, client ID `theca`, client secret file `/run/secrets/oidc_client_secret`. Its page shows the **callback URL**.
3. `OIDC_CALLBACK=<that URL>` in `.env`, then start everything:
   ```sh
   docker compose -f docker-compose.yml -f compose.caddy.yml -f compose.authelia.yml up -d
   ```

The login page then offers Authelia. A first login links to an existing account only if that account linked Authelia from its page (**Account → Ways to log in**), or with the setting `oidc_link_by_email` on (core's `CONFIGURATION.md`).
