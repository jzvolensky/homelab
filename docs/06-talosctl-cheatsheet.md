# 06 — talosctl cheatsheet

Common `talosctl` commands for this homelab, with real values filled in
(node `192.168.1.250`, cluster `homelab`). Talos has **no SSH/shell** — this CLI
(talking to the node's API on `:50000`) is how you inspect and manage the node.

## 0. Access

The `terraform apply` wrote your client config to `~/.talos/config`. Point talosctl
at it and set the default endpoint/node so you can skip `-n/-e` on every command:

```bash
export TALOSCONFIG=~/.talos/config
talosctl config endpoint 192.168.1.250   # where to reach the API
talosctl config node     192.168.1.250   # which node commands target
talosctl config info                     # show current context
```

If you skip the above, pass them per-command: `-e <endpoint> -n <node>`, e.g.
`talosctl -e 192.168.1.250 -n 192.168.1.250 version`.

> Maintenance mode (fresh node, no config yet) has no certs — add `--insecure`.
> Once installed, the API requires the certs in your talosconfig (no `--insecure`).

Kubernetes access (separate): `export KUBECONFIG=~/.kube/homelab.yaml` — or pull a
fresh one with `talosctl kubeconfig ~/.kube/homelab.yaml`.

## 1. Health & status (trust these over the console summary panel)

```bash
talosctl health                       # full cluster health check
talosctl dashboard                    # live TUI: resources, logs, network (q to quit)
talosctl version                      # client + node Talos version
talosctl get members                  # cluster membership
talosctl services                     # all node services + state (etcd, kubelet, ext-*)
talosctl service etcd                 # detail/status for one service
talosctl get staticpodstatus         # kube-apiserver/controller/scheduler READY state
```

## 2. Inspecting resources (`talosctl get <resource>`)

Talos exposes everything as resources. List types with `talosctl get rd` (or just
`talosctl get <type>`; add `-o yaml` for full detail).

```bash
talosctl get nodename                 # the k8s node name
talosctl get links                    # network interfaces (name, MAC, up/down)
talosctl get addresses                # assigned IPs
talosctl get routes                   # routing table — check a default (0.0.0.0/0) exists!
talosctl get extensions               # installed system extensions (from your schematic)
talosctl get disks                    # block devices
talosctl get mounts                   # mounted filesystems
talosctl get machineconfig -o yaml    # the full applied machine config  (alias: mc)
talosctl get extensionserviceconfig   # config given to ext-* services
```

## 3. Logs & debugging

```bash
talosctl logs kubelet                 # a service's logs   (also: etcd, apid, containerd)
talosctl logs ext-tailscale           # extension service logs
talosctl logs -f kubelet              # follow
talosctl dmesg                        # kernel ring buffer
talosctl dmesg -f                     # follow kernel log
talosctl containers                   # containers Talos runs (system + CRI)
talosctl processes                    # top-like process list
talosctl netstat                      # sockets/connections
```

## 4. Config changes

```bash
# Apply an extra config document (e.g. an ExtensionServiceConfig) without reboot:
talosctl patch mc --patch @infra/talos/extension-services/tailscale.yaml
# Fallback if 'patch mc' rejects the doc kind:
talosctl apply-config --mode=no-reboot --patch @<file>.yaml

# Apply a full machine config (staged / immediate / with reboot):
talosctl apply-config -f controlplane.yaml --mode=auto

# Interactively edit the live machine config:
talosctl edit machineconfig
```

> In this repo the machine config is generated and applied by **Terraform**
> (`infra/terraform`). Prefer changing it there and re-applying for anything you
> want to survive a rebuild; use the commands above for ad-hoc/day-2 tweaks.

## 5. Extension services (tailscale / cloudflared)

```bash
talosctl services | grep ext-                 # see ext-tailscale / ext-cloudflared state
talosctl patch mc --patch @infra/talos/extension-services/cloudflared.yaml   # give it config
talosctl logs ext-cloudflared                 # watch it start
```
Full workflow: `infra/talos/extension-services/README.md`.

## 6. Upgrades

```bash
# Upgrade Talos itself — ALWAYS use the FACTORY installer with your schematic,
# else you lose extensions (see docs/02). --preserve keeps etcd on this single node.
talosctl upgrade --preserve \
  --image factory.talos.dev/installer/f11afbd117671ca02048b2230f9fec5a9ca54cf02ffc689eaedcf1f642daeb80:v1.13.5

# Upgrade the Kubernetes version (separate from Talos):
talosctl upgrade-k8s --to 1.36.0
```

## 7. Lifecycle (careful)

```bash
talosctl reboot                       # graceful reboot
talosctl shutdown                     # power off
talosctl etcd status                  # etcd health/members
talosctl etcd snapshot db.snapshot    # back up etcd  (do this before risky changes)

# DESTRUCTIVE — wipes the node back to maintenance mode. Only for a rebuild:
# talosctl reset --graceful=false --reboot
```

## 8. Quick troubleshooting map (things we actually hit)

| Symptom | Command to check | What "good" looks like |
|---------|------------------|------------------------|
| "network unreachable" / NTP fails | `talosctl get routes` | a `0.0.0.0/0` default route with a gateway |
| static IP not applied | `talosctl get links` / `get addresses` | your NIC (`ens18`) holds `192.168.1.250` |
| guest agent / extension missing | `talosctl get extensions` | your schematic's extensions listed |
| control plane "down" | `talosctl get staticpodstatus` | apiserver/scheduler/cm `READY=True` |
| is it in maintenance mode? | `talosctl version` (with & without `--insecure`) | insecure works only in maintenance |
