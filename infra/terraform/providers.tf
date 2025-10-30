terraform {
  required_version = ">= 1.6.0"
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean", version = "~> 2.40" }
    hcloud       = { source = "hetznercloud/hcloud",       version = "~> 1.48" }
  }
}

provider "digitalocean" {
  token = var.do_token
}

provider "hcloud" {
  token = var.hz_token
}
