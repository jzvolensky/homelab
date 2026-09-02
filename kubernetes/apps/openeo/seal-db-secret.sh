#!/usr/bin/env bash
# Seal the PostgreSQL credentials for the openeo app against THIS cluster's
# sealed-secrets key. Ciphertext from another cluster will not decrypt here.
#
#   export POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
#   ./seal-db-secret.sh
#
# Needs kubeseal. It does NOT need a working kubectl context: the Secret is
# built here rather than by `kubectl create --dry-run`, and kubeseal can encrypt
# against a saved certificate instead of asking the cluster for one:
#
#   kubeseal --controller-name sealed-secrets-controller \
#            --controller-namespace kube-system --fetch-cert > sealed-secrets.pem
#   SEALED_SECRETS_CERT=sealed-secrets.pem ./seal-db-secret.sh
#
# The certificate is a public key — keeping a copy is safe, and it is what lets
# this run while the cluster is unreachable.
#
# Produces db-sealedsecret.yaml (safe to commit). One Secret with two keys:
# `password` is what the postgres container initialises itself with, `url` is
# the DSN Grappa connects with. They must agree, which is why they are sealed
# together from one variable rather than maintained separately.
set -euo pipefail
: "${POSTGRES_PASSWORD:?export POSTGRES_PASSWORD to the password to seal}"
cd "$(dirname "$0")"

# The password is interpolated into a postgres:// URL, where @ : / ? # and %
# change what the URL means. Rather than percent-encode one copy and not the
# other, refuse anything that would need it.
if [[ "$POSTGRES_PASSWORD" =~ [^A-Za-z0-9._~-] ]]; then
    echo "refusing: POSTGRES_PASSWORD must use only A-Z a-z 0-9 . _ ~ -" >&2
    echo "it goes into a connection URL, where other characters are delimiters" >&2
    exit 1
fi

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

seal=(kubeseal --format yaml)
if [[ -n "${SEALED_SECRETS_CERT:-}" ]]; then
    seal+=(--cert "$SEALED_SECRETS_CERT")
else
    seal+=(--controller-name sealed-secrets-controller --controller-namespace kube-system)
fi

cat <<EOF | "${seal[@]}" > db-sealedsecret.yaml
apiVersion: v1
kind: Secret
metadata:
    name: grappa-db
    namespace: openeo
type: Opaque
data:
    password: $(b64 "$POSTGRES_PASSWORD")
    url: $(b64 "postgres://grappa:${POSTGRES_PASSWORD}@postgres:5432/grappa")
EOF

echo "Wrote db-sealedsecret.yaml (encrypted, safe to commit)."
echo "Now uncomment it in kustomization.yaml, then commit + push."
