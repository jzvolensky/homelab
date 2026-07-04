resource "proxmox_virtual_environment_vm" "talos_cp" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  description = "Talos control-plane / single-node k8s (managed by Terraform)"
  tags        = ["talos", "kubernetes", "terraform"]

  # qemu-guest-agent ships via the Talos schematic extension; this lets Terraform
  # read the VM's DHCP address during maintenance mode (see talos.tf).
  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cpu
    type  = "host" # pass the physical CPU flags through; best perf for a homelab
  }

  memory {
    dedicated = var.vm_memory
  }

  # Boot ISO (Talos maintenance mode). Kept attached; Talos installs to the disk
  # and subsequently boots from it because scsi0 precedes the cdrom in boot order.
  cdrom {
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide3"
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = var.vm_disk_size
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  boot_order = ["scsi0", "ide3"]

  operating_system {
    type = "l26" # Linux 2.6+ / modern kernel
  }

  network_device {
    bridge = var.network_bridge
  }

  # We manage the OS entirely through Talos config, so ignore agent-driven drift.
  lifecycle {
    ignore_changes = [
      cdrom, # avoid churn once the node is installed and booting from disk
    ]
  }
}
