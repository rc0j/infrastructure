###########
# Blacklist config
###########
resource "adguard_list_filter" "my_blocklists" {
  name    = "My Custom Blocklists (Managed by tf)"
  enabled = true
  url     = "https://codeberg.org/hagezi/mirror2/raw/branch/main/dns-blocklists/adblock/pro.plus.txt"
}

resource "adguard_list_filter" "filter_61" {
  name    = "AdGuard Filter 61 (Managed by tf)"
  enabled = true
  url     = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_61.txt"
}

resource "adguard_list_filter" "filter_10" {
  name    = "AdGuard Filter 10 (Managed by tf)"
  enabled = true
  url     = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_10.txt"
}

resource "adguard_list_filter" "filter_11" {
  name    = "AdGuard Filter 11 (Managed by tf)"
  enabled = true
  url     = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
}
###########
# Whitelist config
###########
resource "adguard_list_filter" "goodness_main" {
  name = "GoodnessJSON Whitelist"
  url  = "https://raw.githubusercontent.com/GoodnessJSON/PiHole-Whitelist/master/lists/whitelist.txt"
  enabled = true
  whitelist = true
}

resource "adguard_list_filter" "goodness_referral" {
  name = "GoodnessJSON Referral Sites"
  url  = "https://raw.githubusercontent.com/GoodnessJSON/PiHole-Whitelist/master/lists/referral-sites.txt"
  enabled = true
  whitelist = true
}

resource "adguard_list_filter" "goodness_optional" {
  name = "GoodnessJSON Optional List"
  url  = "https://raw.githubusercontent.com/GoodnessJSON/PiHole-Whitelist/master/lists/optional-list.txt"
  enabled = true
  whitelist = true
}

# Personal Mauritius Allowlist
resource "adguard_list_filter" "mauritius_local" {
  name = "Mauritius Allowlist"
  url  = "https://gist.githubusercontent.com/rc0j/b045fbae199959ba3687838e11ace8f5/raw/00126bdda57104361b75d5809dcd94b349edc5f2/mauritius-allowlist"
  enabled = true
  whitelist = true
}

# Additional Personal Gist
resource "adguard_list_filter" "custom_gist" {
  name = "Custom Gist Allowlist"
  url  = "https://gist.githubusercontent.com/rc0j/a88b1f2507bd4a5d2b194332f7d0de7e/raw/7b9517c92bbefa4cb2f6b9a2ffc2cb562b088ad8/gistfile1.txt"
  enabled = true
  whitelist = true
}

# O365 Whitelist
resource "adguard_list_filter" "o365_whitelist" {
  name = "O365 Whitelist"
  url  = "https://raw.githubusercontent.com/obiwantoby/O365Whitlist/refs/heads/main/domains/whitelist.txt"
  enabled = true
  whitelist = true
}
