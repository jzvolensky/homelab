# infra/talos — node-level Talos config (day-2)

Config applied directly to the Talos node via `talosctl` (not Terraform, because
these carry secrets we don't want in state/git). The cluster itself is created by
`infra/terraform`; this is for extension services baked into the Talos schematic.

## Extension services

Your Image Factory schematic (`f11afbd...`) includes the **tailscale** and
**cloudflared** extensions. After install they show up as services but sit in
`Waiting` state — they need an `ExtensionServiceConfig` before they start:

```
$ talosctl -n 192.168.1.250 services
ext-tailscale     Waiting   Waiting for extension service config
ext-cloudflared   Waiting   Waiting for extension service config
```

This is harmless — they won't crashloop or block anything.

## How to configure & apply

1. Copy the example, fill in the secret:
   ```bash
   cd infra/talos/extension-services
   cp tailscale.yaml.example tailscale.yaml     # then edit TS_AUTHKEY
   cp cloudflared.yaml.example cloudflared.yaml  # then edit TUNNEL_TOKEN
   ```
   (`*.yaml` here is gitignored; only `*.example` is committed.)

2. Apply to the node — this adds the config document and the service starts
   **without a reboot**:
   ```bash
   export TALOSCONFIG=~/.talos/config
   talosctl -n 192.168.1.250 patch mc --patch @tailscale.yaml
   talosctl -n 192.168.1.250 patch mc --patch @cloudflared.yaml
   ```
   > If `patch mc` complains about the document kind on your Talos version, use:
   > `talosctl -n 192.168.1.250 apply-config --mode=no-reboot --patch @tailscale.yaml`

3. Verify it came up:
   ```bash
   talosctl -n 192.168.1.250 services            # ext-* should go Running/OK
   talosctl -n 192.168.1.250 logs ext-tailscale  # or ext-cloudflared
   talosctl -n 192.168.1.250 get extensionserviceconfig
   ```
   For tailscale, the node should also appear at
   https://login.tailscale.com/admin/machines

## Notes / gotchas

- **These are node services, not Kubernetes pods.** tailscale here = the *node*
  joins your tailnet; cloudflared here = a host-level tunnel. (The alternative —
  running them as Argo CD-managed pods — is in `docs/04-cloudflare-tunnel.md`.)
- **Secret handling:** the token/key ends up in the node's machine config. Keep
  the real `*.yaml` out of git (gitignored). Prefer ephemeral/reusable Tailscale
  keys and scoped Cloudflare tunnels so rotation is easy.
- **Rebuild note:** because these are applied out-of-band (not via Terraform), a
  `terraform destroy`/rebuild of the node loses them — just re-apply from here.
  If you later want them re-applied automatically, they can be added as
  `config_patches` in `infra/terraform/talos.tf` with the secrets sourced from a
  gitignored tfvars.
