# ==========================================================
# 1. CLUSTER MASTER config - baseline
# ==========================================================
resource "proxmox_virtual_environment_cluster_firewall" "datacenter_fw" {
  enabled       = true
  input_policy  = "ACCEPT" 
  output_policy = "ACCEPT" 
}

# ==========================================================
# 2. VM SPECIFIC TOGGLE (Vaultwarden Only)
# ==========================================================
resource "proxmox_virtual_environment_firewall_options" "vaultwarden_policy" {
  node_name    = "orion"
  vm_id        = 19299
  enabled      = true   
  input_policy = "DROP"  # Strictly blocks anything not explicitly allowed below
}

# ==========================================================
# 3. VAULTWARDEN RULES BLOCK
# ==========================================================
resource "proxmox_virtual_environment_firewall_rules" "vaultwarden_profile" {
  node_name = "orion"
  vm_id     = 19299

  # --------------------------------------------------------
  # INBOUND RULES (Traffic coming TO Vaultwarden)
  # --------------------------------------------------------
  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "inbound: allow ssh"
    proto   = "tcp"
    dport   = "22"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "inbound: vaultwarden docker host port"
    proto   = "tcp"
    dport   = "8000"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "inbound: allow icmp (ping)"
    proto   = "icmp"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "inbound: allow dns queries (udp 53)"
    proto   = "udp"
    dport   = "53"
    log     = "info"
  }

  rule {
    type =   "in"
    action = "ACCEPT"
    comment = "inbound: allow http"
    proto =  "tcp"
    dport =  "80"
    log =    "info"
  }

  rule {
    type =   "in"
    action = "ACCEPT"
    comment = "inbound: allow https"
    proto =  "tcp"
    dport =  "443"
    log =    "info"
  }

  # --------------------------------------------------------
  # OUTBOUND RULES (Traffic leaving FROM Vaultwarden)
  # --------------------------------------------------------

  # Allow ALL outgoing traffic (Any protocol, any port, any destination)
  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "outbound: allow everything"
    log     = "info"
  }
}