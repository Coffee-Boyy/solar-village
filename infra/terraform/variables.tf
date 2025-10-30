variable "do_token" { type = string }
variable "hz_token" { type = string }

variable "ssh_pubkey" { type = string }         # your workstation/public deploy key
variable "dns_email"  { type = string }         # email for ACME (Traefik)
variable "dns_provider" { type = string }       # e.g. "cloudflare"
variable "dns_api_token" { type = string }      # for ACME DNS-01

variable "region_map" {
  type = map(object({
    provider = string    # "do" or "hz"
    region   = string    # e.g., "sfo3" for DO, "ash" for HZ (us-east)
    name     = string    # node name
    private_ip = string  # WireGuard/private later; reserve for future
  }))
  # Example (set via tfvars):
  # do-a, do-b, hz-a, hz-b
}

variable "image"     {
  type = string
  default = "ubuntu-24-04-x64"
}
variable "size_do"   {
  type = string
  default = "s-2vcpu-4gb"
}
variable "type_hz"   {
  type = string
  default = "cpx21"
}
