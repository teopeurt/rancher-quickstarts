# Rancher resources

# Initialize Rancher server
resource "rancher2_bootstrap" "admin" {
  depends_on = [
    helm_release.rancher_server
  ]

  provider = rancher2.bootstrap

  password  = var.admin_password
  telemetry = true
}

# Create custom managed cluster for quickstart
# https://registry.terraform.io/providers/rancher/rancher2/latest/docs/resources/cluster#rke_config
# https://jmrobles.medium.com/how-to-setup-hetzner-load-balancer-on-a-kubernetes-cluster-2ce79ca4a27b
# https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/internal/annotation/load_balancer.go#L13
resource "rancher2_cluster" "quickstart_workload" {
  provider = rancher2.admin

  name        = var.workload_cluster_name
  description = "Custom workload cluster created by Rancher quickstart"

  rke_config {
    network {
      plugin  = var.rke_network_plugin
      options = var.rke_network_options
    }
    kubernetes_version = var.workload_kubernetes_version
  }
  windows_prefered_cluster = var.windows_prefered_cluster
}
