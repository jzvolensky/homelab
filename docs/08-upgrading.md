# 08 — Upgrading Talos & Kubernetes

How to upgrade the `talosctl` client, the Talos OS on the node, and the Kubernetes
version, and what tends to break in **this** setup.

There are three separate upgrades. Do them in this order, one at a time:

| # | What | Command | Reboots node? |
|---|------|---------|---------------|
| 1 | `talosctl` client (your machine) | `scripts/install-tools.sh` | no |
| 2 | Talos OS (the node) | `talosctl upgrade --image factory.talos.dev/installer/<schematic>:<ver>` | **yes** |
| 3 | Kubernetes | `talosctl upgrade-k8s --to <k8s-ver>` | no (rolling restart of control plane) |

!!! danger "The one rule: always upgrade with the factory installer + our schematic"
    The extensions (`cloudflared`, `tailscale`, `amdgpu`, `qemu-guest-agent`, …) are
    baked into the **installer image**, not the machine config. If you upgrade with
    the plain `ghcr.io/siderolabs/installer:<ver>` image, or a freshly-clicked
    schematic on factory.talos.dev, the node comes back **without** them. Nothing
    errors. The `ext-*` services just disappear and the Cloudflare tunnel goes
    down.

    Our schematic is the `talos_schematic_id` in `infra/terraform/terraform.tfvars`:

    ```
    f11afbd117671ca02048b2230f9fec5a9ca54cf02ffc689eaedcf1f642daeb80
    ```

    This happened on 2026-11-12: the v1.13 → v1.14.6 upgrade used a new schematic
    `ef909f…` that only had `amdgpu` + `qemu-guest-agent`, which dropped cloudflared and
    tailscale. The fix was to run the upgrade again to the same version with the
    right image.

## 0. Before you start

```bash
export TALOSCONFIG=~/.talos/config
export KUBECONFIG=~/.kube/homelab.yaml
N=192.168.1.250

# 1. Write down the current state so you can compare afterwards
talosctl -n $N version
talosctl -n $N get extensions          # <- the list you must still have afterwards
talosctl -n $N services | grep ext-
kubectl get nodes -o wide

# 2. Back up etcd (single node: there is no other member to recover from)
talosctl -n $N etcd snapshot ~/talos-backups/etcd-$(date +%F).snapshot
```

Check the inputs:

- **Is the schematic still what you think?** Ask the Image Factory:
  ```bash
  curl -s https://factory.talos.dev/schematics/f11afbd117671ca02048b2230f9fec5a9ca54cf02ffc689eaedcf1f642daeb80
  ```
  It should list `cloudflared`, `tailscale`, `amdgpu`, `qemu-guest-agent` (and the rest).
- **Are all those extensions built for the target version?** An extension that
  was dropped upstream would make the installer fail, or silently go missing:
  ```bash
  curl -s https://factory.talos.dev/version/<target>/extensions/official | grep -o '"name":"[^"]*"'
  ```
- **Read the release notes** for the target Talos version
  (<https://github.com/siderolabs/talos/releases>). Look for config fields that
  were deprecated or removed, and for the supported Kubernetes range.

## 1. Upgrade the talosctl client

`talosctl` should be the **same version as the node or newer**. An older client
may not understand newer resources, and some commands refuse to run.

1. Bump `TALOS_VERSION` in `scripts/install-tools.sh`.
2. Run it:
   ```bash
   bash scripts/install-tools.sh
   talosctl version --client --short
   ```

!!! warning "The client's default installer is the plain one"
    Running `talosctl upgrade` **without** `--image` uses
    `ghcr.io/siderolabs/installer:<client-version>`, the image without extensions.
    So upgrading the client and then running a bare `talosctl upgrade` is exactly
    how extensions get lost. Always pass `--image`.

## 2. Upgrade Talos on the node

Go **one minor version at a time** (1.13 → 1.14 → 1.15). Patch versions within a
minor are fine to jump.

```bash
SCHEMATIC=f11afbd117671ca02048b2230f9fec5a9ca54cf02ffc689eaedcf1f642daeb80
TARGET=v1.14.6

talosctl -n $N upgrade \
  --image factory.talos.dev/installer/$SCHEMATIC:$TARGET \
  --preserve \
  --wait --timeout 20m
```

- `--preserve` keeps `/var` (etcd, hostPath data under `/var/mnt`, container
  images). On a single node this is **not optional**. Without it you lose etcd.
- The node reboots, so **everything is down for a few minutes**: the website,
  Argo CD, the LLM. There is no second node to fail over to.
- The first pull of a new `schematic:version` combination can take a few minutes
  while the Image Factory builds it.

Upgrading to the same version you're already on is allowed. That's how you add
back extensions you lost, or switch to a different schematic.

### Verify

```bash
talosctl -n $N version                     # Tag: <TARGET>
talosctl -n $N get extensions              # same list as before the upgrade
talosctl -n $N services | grep ext-        # ext-cloudflared / ext-tailscale Running
talosctl -n $N logs ext-cloudflared | tail # "Registered tunnel connection"
talosctl -n $N logs ext-tailscale   | tail
talosctl -n $N health
kubectl get nodes -o wide                  # INTERNAL-IP must be 192.168.1.250
```

Then from outside, load the public site and check that the node shows as
connected on <https://login.tailscale.com/admin/machines>.

## 3. Upgrade Kubernetes

Each Talos release supports a range of Kubernetes versions (see its release
notes). Upgrade Talos first, then Kubernetes.

```bash
# Dry run: shows what will change, including deprecated API usage
talosctl -n $N upgrade-k8s --to <k8s-ver> --dry-run

talosctl -n $N upgrade-k8s --to <k8s-ver>
kubectl version
kubectl get nodes
```

`upgrade-k8s` doesn't reboot. It rolls the apiserver, controller-manager,
scheduler, kube-proxy and kubelet one at a time. Expect a short API blip.
Kubernetes also only moves **one minor per step**.

Afterwards, check the GitOps side:

```bash
kubectl -n argocd get applications          # all Synced / Healthy
kubectl get pods -A | grep -v -E 'Running|Completed'
```

Apps that use removed Kubernetes APIs show up here as `OutOfSync`/`Degraded`. The
`--dry-run` above should have warned you about them.

## 4. Keep the repo in sync

After a successful upgrade, update these so a rebuild doesn't quietly **downgrade**
or drop extensions:

- [ ] `talos_version` in `infra/terraform/terraform.tfvars` (and `.example`)
- [ ] `TALOS_VERSION` in `scripts/install-tools.sh`
- [ ] the version in the upgrade example in `docs/06-talosctl-cheatsheet.md`
- [ ] if you changed the schematic: `talos_schematic_id` in tfvars, plus the IDs
      mentioned in docs 05, 06, 07 and this page

!!! note "Don't `terraform apply` to upgrade"
    Terraform only creates the cluster. Changing `talos_version` there doesn't
    upgrade a running node, and an apply could try to replace the ISO or VM.
    Upgrades are always done with `talosctl`. The tfvars only record the version
    for the next rebuild.

## What to watch out for in this setup

| Risk | Why it bites here | Check |
|------|-------------------|-------|
| **Extensions lost** | wrong installer image (see top) | `talosctl get extensions` |
| **Tunnel down after upgrade** | cloudflared is a node extension, not a pod | `talosctl services \| grep ext-cloudflared` |
| **ExtensionServiceConfig missing** | they're applied out-of-band (not by Terraform). They survive upgrades, but not a rebuild or `reset` | `talosctl get extensionserviceconfigs`; re-apply from `infra/talos/extension-services/*.yaml` ([05](05-talos-extensions.md)) |
| **NodePorts on the tailscale IP** | if `machine.kubelet.nodeIP.validSubnets` is lost, kubelet may pick the tailscale address, and cloudflared → Traefik breaks (2026-07-28 outage) | `kubectl get nodes -o wide` shows `192.168.1.250` |
| **hostPath `read-only file system`** | needs the `/var/mnt` `extraMounts` from the controlplane patch | an app pod using `/var/mnt` starts |
| **iGPU gone** | `amdgpu` extension missing, or the kernel/firmware changed | `talosctl dmesg \| grep -i amdgpu`; `/dev/dri` exists ([07](07-igpu-passthrough.md)) |
| **etcd lost** | forgot `--preserve` on a single node | always pass it; take a snapshot first |
| **Removed config fields** | new Talos minor drops a deprecated field, so apply/upgrade fails | release notes; `talosctl validate` on the patch |

## Rolling back

If the node comes up broken after a Talos upgrade:

```bash
talosctl -n $N rollback      # boots the previous installed version
```

That only works for the **OS** upgrade, and only one step back. For Kubernetes,
run `upgrade-k8s` again with the previous version. To recover etcd from scratch,
use the snapshot from step 0 (`talosctl bootstrap --recover-from=<snapshot>`).
