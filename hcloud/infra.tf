# DO infrastructure resources

resource "tls_private_key" "global_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "ssh_private_key_pem" {
  filename          = "${path.module}/id_rsa"
  sensitive_content = tls_private_key.global_key.private_key_pem
  file_permission   = "0600"
}

resource "local_file" "ssh_public_key_openssh" {
  filename = "${path.module}/id_rsa.pub"
  content  = tls_private_key.global_key.public_key_openssh
}

# Temporary key pair used for SSH accesss
resource "hcloud_ssh_key" "quickstart_ssh_key" {
  name       = "${var.prefix}-hcloud-ssh-key"
  public_key = tls_private_key.global_key.public_key_openssh
}

resource "hcloud_network" "default" {
  name = "naakwu-net"
  ip_range = "10.0.0.0/8"
}

resource "hcloud_network_subnet" "default" {
  network_id = hcloud_network.default.id
  type = "cloud"
  network_zone = "eu-central"
  ip_range   = "10.0.0.0/8"
}

data "hcloud_image" "ubuntu2004" {
  name = "ubuntu-20.04"
}

# DO droplet for creating a single node RKE cluster and installing the Rancher server
resource "hcloud_server" "rancher_server" {
  name               = "${var.prefix}-rancher-server"
  image              = "ubuntu-20.04"
  server_type        = "cpx21"
  location           = "nbg1"
  ssh_keys           = [hcloud_ssh_key.quickstart_ssh_key.id]

  user_data = templatefile(
    join("/", [path.module, "../cloud-common/files/userdata_rancher_server.template"]),
    {
      docker_version = var.docker_version
      username       = local.node_username
    }
  )

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
    ]

    connection {
      type        = "ssh"
      host        = self.ipv4_address
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
    }
  }
}


# Rancher resources
module "rancher_common" {
  source = "../rancher-common"

  node_public_ip         = hcloud_server.rancher_server.ipv4_address
  node_username          = local.node_username
  ssh_private_key_pem    = tls_private_key.global_key.private_key_pem
  rke_kubernetes_version = var.rke_kubernetes_version

  cert_manager_version = var.cert_manager_version
  rancher_version      = var.rancher_version

  rancher_server_dns = var.rancher_server_dns
  admin_password     = var.rancher_server_admin_password

  workload_kubernetes_version = var.workload_kubernetes_version
  workload_cluster_name       = var.workload_cluster_name
}

# DO droplet for creating a single node workload cluster
resource "hcloud_server" "quickstart_node" {
  name               = "${var.prefix}-quickstart-node"
  image              = "ubuntu-20.04"
  server_type        = "cx21"
  location           = "nbg1"
  ssh_keys           = [hcloud_ssh_key.quickstart_ssh_key.id]

  user_data = templatefile(
    join("/", [path.module, "../cloud-common/files/userdata_quickstart_node.template"]),
    {
      docker_version   = var.docker_version
      username         = local.node_username
      register_command = module.rancher_common.custom_cluster_command
    }
  )

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
    ]

    connection {
      type        = "ssh"
      host        = self.ipv4_address
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
    }
  }
}

resource "hcloud_server" "server" {
  for_each = var.servers

  name        = each.value.name
  image       = each.value.image
  server_type = each.value.server_type
  location    = each.value.location
  backups     = each.value.backups
  ssh_keys    = [hcloud_ssh_key.quickstart_ssh_key.id]


  user_data = templatefile(
    join("/", [path.module, "../cloud-common/files/userdata_quickstart_node.template"]),
    {
      docker_version   = var.docker_version
      username         = local.node_username
      register_command = module.rancher_common.custom_cluster_command
    }
  )

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
    ]

    connection {
      type        = "ssh"
      host        = self.ipv4_address
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
    }
  }
}

resource "hcloud_server_network" "server_network" {
  server_id = hcloud_server.rancher_server.id
  network_id = hcloud_network.default.id
  ip = "10.0.1.5"
}

resource "hcloud_server_network" "server_network_1" {
  server_id = hcloud_server.quickstart_node.id
  network_id = hcloud_network.default.id
  ip = "10.0.1.10"
}

resource "hcloud_server_network" "server_network_2" {
  for_each = var.servers

  network_id = hcloud_network.default.id
  server_id  = hcloud_server.server[each.key].id
  ip         = each.value.private_ip_address
}