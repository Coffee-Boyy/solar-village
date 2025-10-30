locals {
  nodes = var.region_map
}

resource "digitalocean_ssh_key" "deployer" {
  name      = "stack-deployer"
  public_key = var.ssh_pubkey
}

# DigitalOcean nodes
resource "digitalocean_droplet" "do_nodes" {
  for_each = {
    for k,v in local.nodes : k => v
    if v.provider == "do"
  }
  name     = each.value.name
  region   = each.value.region
  image    = var.image
  size     = var.size_do
  ssh_keys = [digitalocean_ssh_key.deployer.fingerprint]
  backups  = false
  ipv6     = true

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    dns_email     = var.dns_email
    dns_provider  = var.dns_provider
    dns_api_token = var.dns_api_token
  })
}

# Hetzner nodes
resource "hcloud_ssh_key" "deployer" {
  name = "stack-deployer"
  public_key = var.ssh_pubkey
}

resource "hcloud_server" "hz_nodes" {
  for_each = {
    for k,v in local.nodes : k => v
    if v.provider == "hz"
  }
  name        = each.value.name
  image       = "ubuntu-24.04"
  server_type = var.type_hz
  location    = each.value.region
  ssh_keys    = [hcloud_ssh_key.deployer.id]
  user_data   = templatefile("${path.module}/cloud-init.yaml", {
    dns_email     = var.dns_email
    dns_provider  = var.dns_provider
    dns_api_token = var.dns_api_token
  })
}

output "public_ips" {
  value = {
    do = { for k,v in digitalocean_droplet.do_nodes : k => v.ipv4_address }
    hz = { for k,v in hcloud_server.hz_nodes          : k => v.ipv4_address }
  }
}
