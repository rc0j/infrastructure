locals {
  dns_records = {
    "centreon-prod" = "192.168.100.7"
    "orion"         = "192.168.100.20"
    "pi"            = "192.168.100.21"
    "node01"        = "192.168.100.98"
    "bitwarden"     = "192.168.100.99"
    "dns"           = "192.168.100.97"
    "jellyfin"      = "192.168.100.100"
    "komodo"        = "docker"
    "docker"        = "192.168.100.101"
    "orion-node02"  = "192.168.100.122"
    "node02"        = "192.168.100.126"
  }
}

resource "adguard_rewrite" "domain" {
  for_each = local.dns_records
  domain   = each.key
  answer   = each.value
}
