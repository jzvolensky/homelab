provider "proxmox" {
  endpoint = var.proxmox_endpoint # e.g. "https://192.168.1.200:8006/"
  username = var.proxmox_username # realm required, e.g. "root@pam"
  password = var.proxmox_password # the PVE login password
  insecure = var.proxmox_insecure # true for a self-signed PVE cert

  # No ssh {} block: our resources (API image download, fresh VM, empty disk) are
  # all API-only. If a future resource needs SSH, add an ssh block back here.
}
