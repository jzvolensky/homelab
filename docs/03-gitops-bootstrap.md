# 03 — GitOps bootstrap (Argo CD)

Once the cluster is up and `kubectl get nodes` shows `Ready`, install the GitOps
layer. After this, Argo CD manages everything else from Git.

```bash
export KUBECONFIG=~/.kube/homelab.yaml
cd infra/ansible
uv sync                                                  # first time only
uv run ansible-galaxy collection install -r requirements.yml
uv run ansible-playbook bootstrap.yml
```

This playbook:

1. installs the **sealed-secrets** controller (so encrypted secrets committed to
   Git can be decrypted in-cluster),
2. installs **Argo CD**,
3. applies the **root app-of-apps** (`kubernetes/bootstrap/root-app.yaml`), which
   points Argo CD at `kubernetes/apps/` in this repo.

## Get the Argo CD admin password + UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080  (user: admin)
```

## Adding apps

Everything under `kubernetes/apps/` is GitOps-managed. Migrate the old
`homelab-deployments` manifests in there and list them in
`kubernetes/apps/kustomization.yaml` — see `kubernetes/apps/README.md`.

## Sealed-secrets note

You'll need to re-seal secrets against **this** cluster's controller (the sealing
key is new). Fetch the public cert once and reuse your existing
`create-sealed-secret.sh` scripts:

```bash
kubeseal --fetch-cert \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system > pub-cert.pem
```

Next: [04 — Cloudflare Tunnel](04-cloudflare-tunnel.md)
