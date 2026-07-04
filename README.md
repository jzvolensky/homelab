# homelab

Infrastructure-as-code for a **single-node Talos Linux Kubernetes** cluster on
Proxmox, deployed remotely from a workstation, with GitOps (Argo CD) on top.

Replaces the old 3-VM Proxmox setup with one robust, reproducible node.

## Stack

| Layer | Tool | Role |
|-------|------|------|
| Provision | **Terraform** (`bpg/proxmox` + `siderolabs/talos`) | create the VM, generate & apply Talos config, bootstrap the cluster |
| OS | **Talos Linux** | immutable, API-managed Kubernetes OS — no SSH, no cloud-init |
| Day-2 bootstrap | **Ansible** (via `uv`) | install Argo CD + sealed-secrets into the fresh cluster |
| Apps | **Argo CD** + Kustomize | everything else, GitOps from `kubernetes/apps/` |
| Ingress | **Cloudflare Tunnel** (in-cluster) | public website, outbound-only, no port-forwarding |

## Layout

```
homelab/
├── docs/                     step-by-step guides (start at 01)
├── scripts/install-tools.sh  install terraform/talosctl/kubectl on the deploy machine
├── infra/
│   ├── terraform/            Proxmox VM + Talos cluster (the "base image" + provisioning)
│   └── ansible/              day-2 in-cluster bootstrap (uv-managed)
└── kubernetes/
    ├── bootstrap/            Argo CD root app-of-apps
    └── apps/                 GitOps-managed manifests (migrate homelab-deployments here)
```

## Quickstart

```bash
# 0. deploy machine tooling
bash scripts/install-tools.sh
( cd infra/ansible && uv sync )

# 1. provision VM + Talos cluster
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # edit
terraform init && terraform apply
terraform output -raw kubeconfig  > ~/.kube/homelab.yaml
terraform output -raw talosconfig > ~/.talos/config

# 2. bootstrap GitOps
export KUBECONFIG=~/.kube/homelab.yaml
cd ../ansible
uv run ansible-galaxy collection install -r requirements.yml
uv run ansible-playbook bootstrap.yml
```

Full walkthrough in [`docs/`](docs/01-prerequisites.md):

1. [Prerequisites](docs/01-prerequisites.md) — tools, Proxmox API token, static IP
2. [Proxmox & Talos](docs/02-proxmox-and-talos.md) — provisioning, how Talos replaces cloud-init
3. [GitOps bootstrap](docs/03-gitops-bootstrap.md) — Argo CD + sealed-secrets
4. [Cloudflare Tunnel](docs/04-cloudflare-tunnel.md) — expose the website
6. [talosctl cheatsheet](docs/06-talosctl-cheatsheet.md) — day-2 commands: access, check, list, logs, upgrade

## Notes

- **Terraform state holds cluster secrets** (Talos CA/tokens). `*.tfstate` and
  `*.tfvars` are gitignored. Consider a remote encrypted backend later.
- **Storage on Talos:** immutable OS = no host-path by default. Add a CSI
  (local-path-provisioner / Longhorn) as a GitOps app if you need PVCs;
  rustfs/S3 workloads need nothing extra.
- This is a **sketch to iterate on** — versions are pinned but bump them
  deliberately, and verify the `talos_schematic_id` matches your Image Factory
  selection.
