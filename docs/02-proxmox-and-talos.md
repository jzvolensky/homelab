# 02 — Provision Proxmox VM + Talos cluster

## How Talos differs from a normal VM (read this first)

Talos is an **immutable, API-managed OS**. There is **no SSH, no shell, no
package manager, and no cloud-init** in the Debian sense. You don't "configure a
server" — you hand Talos a declarative *machine config* (YAML) over its API and
it reconciles to that state. This is why there's Terraform + a Talos provider but
no cloud-init user-data and no Ansible touching the node.

### What plays the role cloud-init would have?

The Talos **machine config**. Two ways to deliver it:

| Delivery | How it works | Used here? |
|----------|--------------|------------|
| **Over the API** (this repo) | VM boots the ISO into *maintenance mode*, Terraform pushes the config to it | ✅ default — simplest, most robust |
| **nocloud** (cloud-init datasource) | Config baked onto a Proxmox cloud-init drive; Talos reads it on boot | alternative, if you want zero manual apply |

We use the API path because the `siderolabs/talos` provider automates it end to
end (apply → install → bootstrap → kubeconfig).

## The provisioning flow

```
Image Factory ISO ──► Proxmox VM (maintenance mode, DHCP)
        │                    │  qemu-guest-agent reports IP
        │                    ▼
   terraform apply ──► push machine config ──► Talos installs to disk ──► reboot
                                                        │
                              static node_ip ──► bootstrap etcd ──► kubeconfig
```

## Run it

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform plan
terraform apply
```

Expect `apply` to pause while Talos installs and reboots; the provider retries
`bootstrap`/`kubeconfig` until the API is up. If it times out, re-run
`terraform apply` — it's idempotent.

## Grab your credentials

```bash
mkdir -p ~/.kube ~/.talos
terraform output -raw kubeconfig  > ~/.kube/homelab.yaml
terraform output -raw talosconfig > ~/.talos/config

export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes -o wide
talosctl -n <node_ip> health
talosctl -n <node_ip> dashboard      # live node dashboard
```

## About the Talos image (Image Factory)

The ISO is built by [factory.talos.dev](https://factory.talos.dev) with the
`siderolabs/qemu-guest-agent` extension so Proxmox can read the VM's IP (Terraform
needs it during first apply). To add more extensions (e.g. `iscsi-tools` for
Longhorn, GPU drivers), generate a new schematic there and update
`talos_schematic_id` in `terraform.tfvars`.

## Day-2 with talosctl

```bash
talosctl -n <node_ip> upgrade --image factory.talos.dev/installer/<schematic>:<version>
talosctl -n <node_ip> upgrade-k8s --to <k8s-version>
talosctl -n <node_ip> get members
```

Next: [03 — GitOps bootstrap](03-gitops-bootstrap.md)
