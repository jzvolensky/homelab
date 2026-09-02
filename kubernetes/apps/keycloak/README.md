# keycloak

The OIDC provider the openEO backend verifies tokens against, on
`keycloak.jzvolensky.com`. Keycloak 26 in production mode (`start`) with its own
PostgreSQL, so it survives restarts and can be administered from anywhere once
the hostname is routed.

## Before the first sync

```bash
export KEYCLOAK_DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
export KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
./seal-secrets.sh          # prints the admin username; save the password now
```

then uncomment `secrets-sealed.yaml` in `kustomization.yaml` and push. The
bootstrap admin is created only when no admin exists — changing those values
later does not rotate anything, that is a console operation.

## Routing

Add `keycloak.jzvolensky.com` to the Cloudflare tunnel, pointing at Traefik the
same way the website is. TLS terminates at Cloudflare, so Keycloak serves plain
HTTP and is told to trust `X-Forwarded-Proto` (`KC_PROXY_HEADERS=xforwarded`).
Without that it emits `http://` URLs behind an `https://` front door and login
loops.

`KC_HOSTNAME=https://keycloak.jzvolensky.com` is the canonical origin. Every
issuer, redirect and discovery URL comes from it, and it is the `iss` claim a
resource server checks — so it must match the ingress host exactly. Nothing
works until that hostname resolves; there is no LAN fallback, because a second
hostname would produce tokens whose `iss` does not match the first.

## The realm

`realm-configmap.yaml` bootstraps a realm `openeo` with one public client,
`openeo-cli` — standard flow, device flow and direct access grants, PKCE S256,
redirect URIs for localhost and the openEO Web Editor. It is imported once at
first boot; Keycloak skips a realm that already exists, so after that the console
is the source of truth and edits here do not travel.

Deliberately no users. Create yours in the console — a committed username and
password has no business behind a public hostname.

## Pointing Grappa at it

In `kubernetes/apps/openeo/grappa-deployment.yaml`:

```yaml
- name: GRAPPA_OIDC_ISSUER
  value: https://keycloak.jzvolensky.com/realms/openeo
- name: GRAPPA_OIDC_ID
  value: keycloak
- name: GRAPPA_OIDC_TITLE
  value: Homelab Keycloak
```

Do that only once the hostname resolves *from inside the cluster* — Grappa fetches
discovery and JWKS from the issuer URL itself, so it will hairpin out through
Cloudflare and back. That works and the keys are cached for an hour, so it is one
request per hour, not per token. Leave `GRAPPA_OIDC_AUDIENCE` unset: a Keycloak
access token's `aud` is not the client id unless you add an audience mapper, and
setting it without one rejects every token.

Then, with a user created in the console:

```bash
TOKEN=$(curl -s -X POST \
  https://keycloak.jzvolensky.com/realms/openeo/protocol/openid-connect/token \
  -d grant_type=password -d client_id=openeo-cli \
  -d username=<user> -d password=<password> | jq -r .access_token)

GRAPPA_TOKEN=$TOKEN scripts/smoke.sh http://openeo.192.168.1.250.nip.io:30080
```

(`scripts/smoke.sh` is in the openeo-grappa-driver repo.)
