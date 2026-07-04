#!/usr/bin/env bash
# Re-seal the GitHub OAuth client secret against THIS cluster's sealed-secrets key.
# The old repo's SealedSecret ciphertext will NOT decrypt here (new cluster = new key).
#
#   export KUBECONFIG=~/.kube/homelab.yaml
#   export GITHUB_CLIENT_SECRET='<client secret from the GitHub OAuth app>'
#   ./reseal-github-oauth.sh
#
# Produces github-oauth-sealedsecret.yaml (safe to commit). The resulting Secret is
# labeled part-of: argocd so Argo CD's $github-oauth:dex.github.clientSecret works.
set -euo pipefail
: "${GITHUB_CLIENT_SECRET:?export GITHUB_CLIENT_SECRET to your GitHub OAuth app client secret}"
cd "$(dirname "$0")"

kubectl create secret generic github-oauth -n argocd \
  --from-literal=dex.github.clientSecret="$GITHUB_CLIENT_SECRET" \
  --dry-run=client -o yaml \
| kubectl label --local -f - app.kubernetes.io/part-of=argocd --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system --format yaml \
> github-oauth-sealedsecret.yaml

echo "Wrote github-oauth-sealedsecret.yaml (encrypted, safe to commit)."
echo "Now uncomment it in kustomization.yaml, then commit + push."
