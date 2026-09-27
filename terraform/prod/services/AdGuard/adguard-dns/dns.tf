locals {
  dns_records = {
    "centreon-prod" = "vlcentreon"
    "vlcentreon"    = "192.168.100.107"
    "vldns0"        = "192.168.100.111"
    "orion"         = "192.168.100.20"
    "node01"        = "192.168.100.98"
    "bitwarden"     = "192.168.100.99"
    "dns"           = "192.168.100.97"
    "jellyfin"      = "192.168.100.100"
    "immich"        = "192.168.100.104"
    "immich-ml"     = "192.168.100.103"
    "orion-node02"  = "192.168.100.122"
  }
}

resource "adguard_rewrite" "domain" {
  for_each = local.dns_records
  domain   = each.key
  answer   = each.value
}
