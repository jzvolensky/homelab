# Homelab

Infrastructure-as-code for a **single-node [Talos Linux](https://www.talos.dev/) Kubernetes** cluster on
Proxmox — provisioned remotely, managed by GitOps.

This replaces an old 3-VM Proxmox setup with one robust, reproducible node.

!!! tip "Where to start"
    New here? Read [Prerequisites](01-prerequisites.md) → [Proxmox & Talos](02-proxmox-and-talos.md)
    → [GitOps Bootstrap](03-gitops-bootstrap.md). Day-to-day, the
    [talosctl Cheatsheet](06-talosctl-cheatsheet.md) is your friend.

## The stack

| Layer | Tool | Role |
|-------|------|------|
| Provision | **Terraform** (`bpg/proxmox` + `siderolabs/talos`) | create the VM, generate & apply Talos config, bootstrap the cluster |
| OS | **Talos Linux** | immutable, API-managed Kubernetes OS — no SSH, no cloud-init |
| Day-2 bootstrap | **Ansible** (via `uv`) | install Argo CD + sealed-secrets into the fresh cluster |
| Apps | **Argo CD** + Kustomize | everything else, GitOps from `kubernetes/apps/` |
| Ingress | **Traefik** + **Cloudflare Tunnel** | public services, outbound-only, no port-forwarding |
| Secrets | **sealed-secrets** | encrypted secrets committed safely to a public repo |

## Architecture

```
Proxmox VM ─ Talos (single node) ─ Kubernetes
   ├─ Argo CD (GitOps) ──────── argocd.example.com   (GitHub login, TLS)
   ├─ sealed-secrets ────────── encrypted secrets in Git
   ├─ Traefik ───────────────── ingress for every app
   └─ cloudflared / tailscale ─ node-level Talos extensions
```

## Guides

<div class="grid cards" markdown>

- :material-clipboard-check: **[Prerequisites](01-prerequisites.md)** — tools, Proxmox API access, static IP
- :material-server: **[Proxmox & Talos](02-proxmox-and-talos.md)** — provisioning, how Talos replaces cloud-init
- :material-rocket-launch: **[GitOps Bootstrap](03-gitops-bootstrap.md)** — Argo CD + sealed-secrets
- :material-cloud: **[Cloudflare Tunnel](04-cloudflare-tunnel.md)** — expose services publicly
- :material-puzzle: **[Talos Extensions](05-talos-extensions.md)** — tailscale / cloudflared as node services
- :material-console: **[talosctl Cheatsheet](06-talosctl-cheatsheet.md)** — day-2 commands

</div>
