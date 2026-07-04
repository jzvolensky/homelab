# ---------- Proxmox connection ----------
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API URL, including scheme and port, e.g. https://pve.lan:8006/"
}

variable "proxmox_username" {
  type        = string
  description = "PVE user including realm, e.g. root@pam"
  default     = "root@pam"
}

variable "proxmox_password" {
  type        = string
  description = "PVE login password for proxmox_username"
  sensitive   = true
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification (true for a self-signed PVE cert)"
  default     = true
}

variable "proxmox_node" {
  type        = string
  description = "Name of the Proxmox node to deploy on (see PVE UI, e.g. 'pve')"
  default     = "pve"
}

# ---------- Datastores / network ----------
variable "iso_datastore" {
  type        = string
  description = "Datastore that holds ISOs (content type 'iso'), e.g. 'local'"
  default     = "local"
}

variable "vm_datastore" {
  type        = string
  description = "Datastore for the VM's disk, e.g. 'local-lvm'"
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge to attach the VM to"
  default     = "vmbr0"
}

# ---------- Talos image ----------
variable "talos_version" {
  type        = string
  description = "Talos release, e.g. v1.9.5. Check https://github.com/siderolabs/talos/releases"
  default     = "v1.9.5"
}

variable "talos_schematic_id" {
  type        = string
  description = <<-EOT
    Talos Image Factory schematic ID. Generate one at https://factory.talos.dev
    and include the 'siderolabs/qemu-guest-agent' system extension so Proxmox can
    read the VM's IP (this Terraform relies on that during first apply).
    The value below is the stock schematic WITH qemu-guest-agent already selected.
  EOT
  # Schematic for: customization.systemExtensions.officialExtensions = [siderolabs/qemu-guest-agent]
  default = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

# ---------- VM sizing ----------
variable "vm_id" {
  type        = number
  description = "Numeric VMID in Proxmox"
  default     = 200
}

variable "vm_name" {
  type        = string
  description = "VM name and Talos node hostname"
  default     = "talos-cp-01"
}

variable "vm_cpu" {
  type    = number
  default = 6
}

variable "vm_memory" {
  type        = number
  description = "RAM in MiB"
  default     = 16384
}

variable "vm_disk_size" {
  type        = number
  description = "Boot disk size in GiB"
  default     = 200
}

variable "install_disk" {
  type        = string
  description = "Disk Talos installs onto. scsi0 shows up as /dev/sda in the guest."
  default     = "/dev/sda"
}

# ---------- Cluster networking ----------
variable "cluster_name" {
  type    = string
  default = "homelab"
}

variable "node_ip" {
  type        = string
  description = "Static IP assigned to the node via the Talos config (post-install address)"
}

variable "node_cidr" {
  type        = number
  description = "Prefix length for node_ip (e.g. 24 for a /24 subnet)"
  default     = 24
}

variable "gateway" {
  type        = string
  description = "Default gateway on the node's subnet"
}
