# PKI + secrets for the cluster (CA, tokens, certs). Stored in Terraform state,
# so keep state private (see backend note in README / .gitignore).
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Discover the address Talos reports over qemu-guest-agent while it sits in
# maintenance mode (DHCP). We push the first machine config to this address;
# the config itself then pins the permanent static IP (var.node_ip).
locals {
  agent_ipv4 = flatten(proxmox_virtual_environment_vm.talos_cp.ipv4_addresses)
  maintenance_ip = try(
    [for ip in local.agent_ipv4 : ip if ip != "127.0.0.1" && !startswith(ip, "169.254.")][0],
    null
  )
}

# Render the control-plane machine config from the patch template.
data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.node_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = [
    templatefile("${path.module}/patches/controlplane.yaml.tftpl", {
      node_ip       = var.node_ip
      node_cidr     = var.node_cidr
      gateway       = var.gateway
      install_disk  = var.install_disk
      schematic_id  = var.talos_schematic_id
      talos_version = var.talos_version
      # Match the NIC by its actual MAC (lowercased to match how Talos reports it).
      mac_address = lower(proxmox_virtual_environment_vm.talos_cp.network_device[0].mac_address)
    })
  ]
}

# Apply the config to the node while it's in maintenance mode. After this Talos
# installs to disk, reboots, and comes up at the static node_ip.
resource "talos_machine_configuration_apply" "cp" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = local.maintenance_ip
  endpoint                    = local.maintenance_ip

  depends_on = [proxmox_virtual_environment_vm.talos_cp]
}

# Bootstrap etcd exactly once. Targets the permanent static IP (node is rebooted
# into its installed state by now). The provider retries while the API warms up.
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
  endpoint             = var.node_ip

  depends_on = [talos_machine_configuration_apply.cp]
}

# Pull the kubeconfig once the control plane is healthy.
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
  endpoint             = var.node_ip

  depends_on = [talos_machine_bootstrap.this]
}

# talosconfig for talosctl (day-2 node management, upgrades, dashboards).
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.node_ip]
  nodes                = [var.node_ip]
}
