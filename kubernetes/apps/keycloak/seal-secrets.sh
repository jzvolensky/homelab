#!/usr/bin/env bash
# Seal Keycloak's credentials against THIS cluster's sealed-secrets key.
# Ciphertext from another cluster will not decrypt here.
#
#   export KEYCLOAK_DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
#   export KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
#   ./seal-secrets.sh
#
# Print the admin password before you lose it — the sealed file cannot be read
# back, and rotating the bootstrap admin afterwards is a console operation.
#
# Needs kubeseal, not a working kubectl context: the Secret is built here, and
# kubeseal can encrypt against a saved certificate instead of asking the cluster:
#
#   kubeseal --controller-name sealed-secrets-controller \
#            --controller-namespace kube-system --fetch-cert > sealed-secrets.pem
#   SEALED_SECRETS_CERT=sealed-secrets.pem ./seal-secrets.sh
set -euo pipefail
: "${KEYCLOAK_DB_PASSWORD:?export KEYCLOAK_DB_PASSWORD}"
: "${KEYCLOAK_ADMIN_PASSWORD:?export KEYCLOAK_ADMIN_PASSWORD}"
KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-admin}"
cd "$(dirname "$0")"

# The database password goes into a JDBC URL's credentials, and the admin one is
# typed at a login form; keeping both to unreserved characters avoids quoting
# surprises in either place.
for var in KEYCLOAK_DB_PASSWORD KEYCLOAK_ADMIN_PASSWORD; do
    if [[ "${!var}" =~ [^A-Za-z0-9._~-] ]]; then
        echo "refusing: $var must use only A-Z a-z 0-9 . _ ~ -" >&2
        exit 1
    fi
done

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

seal=(kubeseal --format yaml)
if [[ -n "${SEALED_SECRETS_CERT:-}" ]]; then
    seal+=(--cert "$SEALED_SECRETS_CERT")
else
    seal+=(--controller-name sealed-secrets-controller --controller-namespace kube-system)
fi

cat <<EOF | "${seal[@]}" > secrets-sealed.yaml
apiVersion: v1
kind: Secret
metadata:
    name: keycloak-secrets
    namespace: keycloak
type: Opaque
data:
    db-password: $(b64 "$KEYCLOAK_DB_PASSWORD")
    admin-username: $(b64 "$KEYCLOAK_ADMIN_USERNAME")
    admin-password: $(b64 "$KEYCLOAK_ADMIN_PASSWORD")
EOF

echo "Wrote secrets-sealed.yaml (encrypted, safe to commit)."
echo "Admin user: ${KEYCLOAK_ADMIN_USERNAME}  — store the password now, it is not recoverable from that file."
echo "Then uncomment secrets-sealed.yaml in kustomization.yaml, commit and push."
