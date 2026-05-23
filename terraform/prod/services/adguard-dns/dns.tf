locals {
  dns_records = {
    "bitwarden"     = "192.168.100.99"
    "centreon-prod" = "192.168.100.7"
    "dns"           = "192.168.100.97"
    "proxy"         = "192.168.100.98"
    "jellyfin"      = "192.168.100.100"
    "orion"         = "192.168.100.20"
    "orion-node02"  = "192.168.100.22"
    "pi"            = "192.168.100.21"
  }
}

resource "adguard_rewrite" "domain" {
  for_each = local.dns_records
  domain   = each.key
  answer   = each.value
}