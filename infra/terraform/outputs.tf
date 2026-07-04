output "node_ip" {
  description = "Static IP of the Talos node"
  value       = var.node_ip
}

output "maintenance_ip" {
  description = "DHCP address Talos used in maintenance mode (for debugging)"
  value       = local.maintenance_ip
}

output "kubeconfig" {
  description = "Write to a file with: terraform output -raw kubeconfig > ~/.kube/homelab.yaml"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Write to a file with: terraform output -raw talosconfig > ~/.talos/config"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}
