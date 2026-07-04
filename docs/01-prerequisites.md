# 01 — Prerequisites

You deploy **from your workstation** (WSL) to the Proxmox host over the network.
Nothing in this repo runs *on* the Proxmox node directly.

## 1. Tools on the deploy machine

```bash
bash scripts/install-tools.sh          # terraform, talosctl, kubectl -> ~/.local/bin (remote clients)
cd infra/ansible && uv sync            # ansible-core + kubernetes libs (managed by uv)
```

> Why not `apt install terraform`? The HashiCorp apt repo is what produced the
> `Malformed entry ... hashicorp.list` error. We skip apt and drop a pinned
> binary in `~/.local/bin` instead — reproducible and sudo-free. If you already
> broke the apt list, remove it: `sudo rm /etc/apt/sources.list.d/hashicorp.list`.

## 2. Proxmox credentials (for Terraform)

Local-only setup, so we just use username + password (no API token). Put your
existing PVE login in `terraform.tfvars`:

```hcl
proxmox_username = "root@pam"                    # realm required
proxmox_password = "your-pve-root-password"
```

No SSH to the node is needed — every resource here is API-only (image download,
VM create, empty disk).

## 3. Decide the node's static IP

Pick a **free** address on your LAN outside the DHCP pool (e.g. `192.168.1.50`),
plus its gateway. You'll put these in `terraform.tfvars` — Talos pins them into
the machine config so the cluster endpoint never moves.

## 5. Confirm names in the PVE UI

- Node name (e.g. `pve`)
- ISO datastore (usually `local`)
- VM disk datastore (usually `local-lvm`)
- Network bridge (usually `vmbr0`)

Next: [02 — Proxmox & Talos](02-proxmox-and-talos.md)
