terraform {
  required_version = ">= 1.6"

  required_providers {
    # bpg is the actively-maintained Proxmox provider. Do NOT use telmate/proxmox.
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.60.0"
    }
    # Generates the Talos machine config, applies it over the Talos API,
    # bootstraps etcd, and pulls the kubeconfig back out.
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0"
    }
  }
}
