# 07 — iGPU passthrough (Radeon 780M → Talos → `/dev/dri`)

Passes the host's Radeon 780M iGPU into the Talos VM so pods can run Vulkan
workloads — built for LLM inference (`kubernetes/apps/llm`). Done 2026-07-28.

## What is set where

| Setting | Lives in | Value |
|---|---|---|
| GPU bound to vfio, amdgpu blacklisted | Proxmox host: `/etc/modules`, `/etc/modprobe.d/vfio.conf` | `ids=1002:15bf` |
| Machine type, GPU device, pinned RAM | VM 100 config (`qm set`, mirrored in `infra/terraform/vm.tf`) | `q35`, `hostpci0: 0000:c4:00.0,pcie=1`, `memory 20480`, `balloon 0`, `onboot 1` |
| amdgpu driver + firmware | Talos schematic `f11afbd…` (already includes the `amdgpu` extension) | `/dev/dri` on the node |
| Kubelet node IP pin (see gotcha below) | Machine config (`patch mc`) + `infra/terraform/patches/controlplane.yaml.tftpl` | `validSubnets: [192.168.1.250/32]` |
| GPU workload | `kubernetes/apps/llm/` | privileged pod, mounts `/dev/dri`, image `llama.cpp:server-vulkan` |

!!! warning "Point of no return"
    The 780M is the **only** GPU in the box. Once vfio owns it, the host's HDMI
    console is dead for good — Proxmox is reachable only via web UI (`:8006`) /
    SSH. Confirm both work before rebooting.

## 1. Proxmox host — bind the GPU to vfio

```bash
lspci -nn | grep -Ei 'vga|display'   # → c4:00.0 ... Phoenix1 [1002:15bf]
dmesg | grep -i "AMD-Vi"             # IOMMU already enabled by default — no
                                     # kernel cmdline change was needed
```

Each function of `c4:00.*` sits in its own IOMMU group (`dmesg | grep iommu`),
so only the VGA function gets passed — the sibling USB controllers stay with
the host.

```bash
cat >> /etc/modules <<'EOF'
vfio
vfio_iommu_type1
vfio_pci
EOF

cat > /etc/modprobe.d/vfio.conf <<'EOF'
options vfio-pci ids=1002:15bf
softdep amdgpu pre: vfio-pci
blacklist amdgpu
EOF

update-initramfs -u -k all && reboot
```

**Verify** after reboot:

```bash
lspci -nnk -s c4:00.0    # → Kernel driver in use: vfio-pci
```

## 2. VM — q35, hostpci, pinned memory

!!! note "Why 20480 MB"
    With a hostpci device QEMU **pins all guest RAM**. A 32 GB guest on the
    32 GB host cannot start; 20 GB leaves ~4 GB for Proxmox + the GPU's GTT.

```bash
qm shutdown 100                                # wait for: status: stopped
qm set 100 -machine q35                        # PCIe passthrough wants q35
qm set 100 -hostpci0 0000:c4:00.0,pcie=1
qm set 100 -memory 20480
qm set 100 -balloon 0                          # meaningless with pinned RAM
qm set 100 -onboot 1                           # single node — must self-start
qm start 100
```

Mirrored in `infra/terraform/vm.tf` — Terraform (Windows PC) must pull that
change **and** set `vm_memory = 20480` in tfvars before its next apply, or it
reverts all of this.

**Verify** (from the Mac, ~2 min after boot):

```bash
talosctl -n 192.168.1.250 get pcidevices | grep -iE "display|vga"
# → 0000:01:00.0 ... Advanced Micro Devices, Inc. [AMD/ATI]  Phoenix1
```

## 3. Talos — amdgpu driver

The schematic (`f11afbd…`) already ships the `amdgpu` extension, so nothing was
changed here. If a future schematic is rebuilt, it must keep **all** installed
extensions (`talosctl get extensions`) plus `siderolabs/amdgpu` — dropping
cloudflared/tailscale kills the tunnel.

**Verify:**

```bash
talosctl -n 192.168.1.250 ls /dev/dri            # → card0, renderD128
talosctl -n 192.168.1.250 dmesg | grep -i amdgpu
# → "VRAM: 2048M", "GTT: ~10000M", firmware loading via PSP
```

GPU memory budget = 2 GB VRAM (BIOS UMA carve) + ~10 GB GTT (half of guest
RAM) ≈ **12 GB** for model + KV cache. Both are the same DRAM on an APU — for
bigger models raise BIOS UMA or the `amdgpu.gttsize=` kernel arg, don't chase
speed there.

## 4. Kubernetes — the workload

See `kubernetes/apps/llm/README.md`. The one check that matters (Vulkan falls
back to CPU **silently**):

```bash
kubectl -n llm logs deploy/llama-server | grep -i vulkan
# → ggml_vulkan: Found 1 Vulkan devices ... PHOENIX (RADV)
```

## Gotcha: the q35 change moved the NodePorts (502 outage)

The q35 switch renumbers the PCI bus → interface enumeration changes → kubelet
(node IP never pinned) re-registered with the **tailscale** IP → kube-proxy
(nftables mode serves NodePorts **only on the primary IP**) moved 30080/30443
off the LAN IP → cloudflared's origin `192.168.1.250:30080` refused →
Cloudflare 502 on every public site, while `kubectl get pods -A` showed
everything Running.

Diagnosis path: `talosctl logs ext-cloudflared` (showed `dial tcp
192.168.1.250:30080: connect: refused`) + `kubectl get nodes -o wide`
(INTERNAL-IP was `100.x.x.x`).

Fix (now permanent in the tftpl template):

```bash
talosctl -n 192.168.1.250 patch mc --patch \
  '{"machine":{"kubelet":{"nodeIP":{"validSubnets":["192.168.1.250/32"]}}}}'
# then restart kube-proxy — it does NOT rebuild rules on an IP change:
kubectl -n kube-system delete pod -l k8s-app=kube-proxy
```

!!! warning "AMD iGPU reset quirk"
    APUs don't always reset cleanly across VM restarts. If the pod hits Vulkan
    init errors after a VM reboot, reboot the **Proxmox host** — that's the
    known fix, not a k8s problem.
