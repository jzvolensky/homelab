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

- **Storage — an app needs to write to disk?** Three options on Talos:
    1. **hostPath under `/var`** (what `llm/` does for its model cache — fine on
       a single-node cluster). Two requirements, both shown in `llm/`:
        - the path must be under `/var` (e.g. `/var/mnt/<app>`,
          `type: DirectoryOrCreate`) — everything else is immutable OS;
        - the app's namespace needs the label
          `pod-security.kubernetes.io/enforce: privileged`, because Talos
          enforces the `baseline` Pod Security Standard by default and baseline
          **forbids hostPath volumes** (pods get rejected with a PSS error).
    2. **PVCs:** add a CSI (`local-path-provisioner`, Longhorn, OpenEBS) as its
       own app here. Note local-path-provisioner additionally needs a machine
       config patch (kubelet `extraMounts` for its data dir) — that lives in
       Talos land, not in this repo's manifests.
    3. **S3-backed** (rustfs etc.): nothing extra needed.

    example patch for `hostPath`:

    ```bash
    talosctl -n <node> patch mc --patch '{"machine":{"kubelet":{"extraMounts":[{"destination":"/var/mnt/models","type":"bind","source":"/var/mnt/models","options":["bind","rshared","rw"]}]}}}'
    ```
- **NodePorts only answer on the node's *primary* IP** (kube-proxy runs in
  nftables mode). The kubelet's registered IP is therefore pinned to
  `192.168.1.250` in the machine config (`machine.kubelet.nodeIP.validSubnets`,
  also in `infra/terraform/patches/controlplane.yaml.tftpl`). Never let it
  auto-pick: with tailscale on the node a reboot can register the `100.x` IP
  instead, silently moving NodePorts off the LAN IP and breaking the
  cloudflared → Traefik origin (Cloudflare 502 while every pod shows Running —
  see `docs/07-igpu-passthrough.md`). If the node IP ever changes, also restart
  kube-proxy (`kubectl -n kube-system delete pod -l k8s-app=kube-proxy`) — it
  doesn't rebuild its rules on an IP change.
