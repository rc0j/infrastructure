# ==========================================================
# 1. CLUSTER MASTER config - baseline
# ==========================================================
resource "proxmox_virtual_environment_cluster_firewall" "datacenter_fw" {
  enabled       = true
  input_policy  = "ACCEPT" 
  output_policy = "ACCEPT" 
}

# ==========================================================
# 2. SECURITY GROUP (Reusable Vaultwarden Profile)
# ==========================================================
resource "proxmox_virtual_environment_cluster_firewall_security_group" "vaultwarden_sg" {
  name    = "vaultwarden-sg"
  comment = "Standard firewall profile for Vaultwarden instances"

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
    type    = "in"
    action  = "ACCEPT"
    comment = "inbound: allow http"
    proto   = "tcp"
    dport   = "80"
    log     = "info"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "inbound: allow https"
    proto   = "tcp"
    dport   = "443"
    log     = "info"
  }

  # --------------------------------------------------------
  # OUTBOUND RULES (Traffic leaving FROM Vaultwarden)
  # --------------------------------------------------------
  rule {
    type    = "out"
    action  = "ACCEPT"
    comment = "outbound: allow everything"
    log     = "info"
  }
}

# ==========================================================
# 3. APPLY TO VM (Options & Attach Security Group)
# ==========================================================
resource "proxmox_virtual_environment_firewall_options" "vaultwarden_policy" {
  node_name    = "orion"
  vm_id        = 19299
  enabled      = true   
  input_policy = "DROP"  # Strictly blocks anything not explicitly allowed below
}

resource "proxmox_virtual_environment_firewall_rules" "vaultwarden_vm_rules" {
  node_name = "orion"
  vm_id     = 19299

  # Attach the Security Group to the VM
  rule {
    type           = "in"
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.vaultwarden_sg.name
    comment        = "Attach Vaultwarden Security Group"
  }
}