# ==========================================================
# PROXMOX FIREWALL
# ==========================================================
#
# Design:
#   - Cluster firewall enabled
#   - VM firewalls use default-deny inbound policy
#   - Each VM gets its own Security Group
#   - Security Groups explicitly allow required services
#   - Outbound traffic is allowed by default
#
# ==========================================================


# ==========================================================
# 1. CLUSTER FIREWALL - BASELINE
# ==========================================================

resource "proxmox_virtual_environment_cluster_firewall" "datacenter_fw" {
  enabled       = true
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
}

# ==========================================================
# 2. SECURITY GROUP - VAULTWARDEN
# ==========================================================

resource "proxmox_virtual_environment_cluster_firewall_security_group" "vaultwarden_sg" {
  name    = "vaultwarden-sg"
  comment = "Default-deny inbound profile for Vaultwarden"


  # --------------------------------------------------------
  # INBOUND
  # --------------------------------------------------------

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    comment = "Allow SSH"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8000"
    comment = "Allow Vaultwarden"
    log     = "info"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "icmp"
    comment = "Allow ICMP"
    log     = "info"
  }

  # --------------------------------------------------------
  # OUTBOUND
  # --------------------------------------------------------

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Allow outbound traffic"
    log     = "info"
  }
}

# ==========================================================
# 3. APPLY VAULTWARDEN FIREWALL
# ==========================================================

resource "proxmox_virtual_environment_firewall_options" "vaultwarden_policy" {
  node_name    = "orion"
  vm_id        = 19299
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_rules" "vaultwarden_vm_rules" {
  node_name = "orion"
  vm_id     = 19299

  rule {
    type           = "in"
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.vaultwarden_sg.name
    comment        = "Attach Vaultwarden Security Group"
  }
}

# ==========================================================
# 4. SECURITY GROUP - VLNODE01 / NGINX PROXY MANAGER
# ==========================================================

resource "proxmox_virtual_environment_cluster_firewall_security_group" "vlnode01_sg" {
  name    = "vlnode01-sg"
  comment = "Default-deny inbound profile for Nginx Proxy Manager"


  # --------------------------------------------------------
  # INBOUND
  # --------------------------------------------------------

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    comment = "Allow SSH"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "icmp"
    comment = "Allow ICMP"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    comment = "Allow HTTP"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    comment = "Allow HTTPS"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "81"
    comment = "Allow Nginx Proxy Manager admin"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8080"
    comment = "Allow PHPIPAM"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "161"
    comment = "Allow SNMP"
    log     = "info"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "8090"
    comment = "Allow Wallabag (temporary)"
    log     = "info"
  }

  rule {
    type  = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "5984"
    comment = "Allow Obsidian Sync"
    log     = "info"
  }

  rule {
    type  = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "22000"
    comment = "Allow Syncthing"
    log     = "info"
  }

  rule {
    type  = "in"
    action = "ACCEPT"
    proto  = "udp"
    dport  = "22000"
    comment = "Allow Syncthing"
    log     = "info"
  }

  rule {
    type  = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "8384"
    comment = "Allow Syncthing web UI"
    log     = "info"
  }

  # --------------------------------------------------------
  # OUTBOUND
  # --------------------------------------------------------

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Allow outbound traffic"
    log     = "info"
  }
  
}



# ==========================================================
# 5. APPLY VLNODE01 FIREWALL
# ==========================================================

resource "proxmox_virtual_environment_firewall_options" "vlnode01_policy" {
  node_name    = "orion"
  vm_id        = 19298
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_rules" "vlnode01_vm_rules" {
  node_name = "orion"
  vm_id     = 19298

  rule {
    type           = "in"
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.vlnode01_sg.name
    comment        = "Attach VLNODE01 Security Group"
  }
}

# ==========================================================
# 6. IMMICH SECURITY GROUP
# ==========================================================
resource "proxmox_virtual_environment_cluster_firewall_security_group" "immich_sg" {
  name    = "immich-sg"
  comment = "Default-deny inbound profile for Immich"
  
  # --------------------------------------------------------
  # INBOUND
  # --------------------------------------------------------

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    comment = "Allow SSH"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "2283"
    comment = "Allow Immich"
    log     = "info"
  }
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "icmp"
    comment = "Allow ICMP"
    log     = "info"
  }
  
  # --------------------------------------------------------
  # OUTBOUND
  # --------------------------------------------------------

  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Allow outbound traffic"
    log     = "info"
  }

}

# ==========================================================
# 7. APPLY IMMICH FIREWALL
# ==========================================================

resource "proxmox_virtual_environment_firewall_options" "immich_policy" {
  node_name    = "orion"
  vm_id        = 192104
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_rules" "immich_vm_rules" {
  node_name = "orion"
  vm_id     = 192104

  rule {
    type           = "in"
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.immich_sg.name
    comment        = "Attach Immich Security Group"
  }
}

# ==========================================================
# 8. SECURITY GROUP - ADGUARD HOME (Primary NODE - CRITICAL)
# ==========================================================
resource "proxmox_virtual_environment_cluster_firewall_security_group" "adguard_sg" {
  name    = "adguard-sg"
  comment = "Default-deny inbound profile for AdGuard Home"

  # --------------------------------------------------------
  # INBOUND
  # --------------------------------------------------------

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    comment = "Allow SSH"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3000"
    comment = "Allow AdGuard Home web UI"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "53"
    comment = "Allow DNS TCP queries to AdGuard Home"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "53"
    comment = "Allow DNS UDP queries to AdGuard Home"
    log     = "info"
  }

  rule { 
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "161"
    comment = "Allow SNMP"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "icmp"
    comment = "Allow ICMP"
    log     = "info"
  }

  # --------------------------------------------------------
  # OUTBOUND
  # --------------------------------------------------------
  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "Allow outbound traffic"
    log     = "info"
  }
}

resource "proxmox_virtual_environment_firewall_options" "adguard_policy" {
  node_name    = "orion"
  vm_id        = 192105
  enabled      = true
  input_policy = "DROP"
}

resource "proxmox_virtual_environment_firewall_rules" "adguard_vm_rules" {
  node_name = "orion"
  vm_id     = 192105

  rule {
    type           = "in"
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.adguard_sg.name
    comment        = "Attach AdGuard Security Group"
  }
}