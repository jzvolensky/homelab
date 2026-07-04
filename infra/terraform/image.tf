# Download a Talos ISO (built by Image Factory with the qemu-guest-agent
# extension) straight onto the Proxmox node's ISO datastore. The VM boots this
# ISO into Talos "maintenance mode", where it waits for a machine config.
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore
  node_name    = var.proxmox_node
  file_name    = "talos-${var.talos_version}-metal-amd64.iso"
  url          = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/metal-amd64.iso"

  # Talos ISOs are not re-published, so the checksum is stable once pinned.
  overwrite = false
}
