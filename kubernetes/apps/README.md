# kubernetes/apps

Argo CD watches this directory (via `kubernetes/bootstrap/root-app.yaml`) and
syncs whatever `kustomization.yaml` lists. This is the GitOps surface — the
equivalent of `apps/` in the old `homelab-deployments` repo.

## Migrating from homelab-deployments

The old manifests are Talos-compatible as-is (they target
`https://kubernetes.default.svc`). To bring them over:

1. Copy each app directory (`cert-manager/`, `monitoring/`, `tailscale/`,
   `rustfs/`, `webserver/`) into this folder.
2. Add each app's `application.yaml` to `kustomization.yaml`.
3. Commit + push. Argo CD self-heals the rest.

## Talos-specific notes

- **Storage:** Talos has no host-path/local storage by default (immutable OS).
  For PVCs, add a CSI — `local-path-provisioner`, Longhorn, or OpenEBS — as its
  own app here. Workloads backed by rustfs/S3 need nothing extra.
