resource "proxmox_virtual_environment_vm" "talos_cp" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  description = "Talos control-plane / single-node k8s (managed by Terraform)"
  tags        = ["talos", "kubernetes", "terraform"]

  # Single-node cluster: everything depends on this VM coming back after a
  # host reboot (matches `qm set 100 -onboot 1` applied by hand).
  on_boot = true

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
    # With hostpci passthrough QEMU pins all guest RAM, so vm_memory must leave
    # headroom for the Proxmox host itself (20480 on the 32 GB box).
    dedicated = var.vm_memory
    floating  = 0 # ballooning is meaningless with pinned memory
  }

  # PCIe passthrough of the Radeon 780M iGPU (vfio-bound on the host) for
  # Vulkan LLM inference in-cluster. Requires machine = q35.
  machine = "q35"

  hostpci {
    device = "hostpci0"
    id     = "0000:c4:00.0"
    pcie   = true
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
