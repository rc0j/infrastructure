terraform { 
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.110.0"
    }
  }
}
provider "proxmox" {
  endpoint = "https://192.168.100.20:8006/"
  insecure = true
  username = "root@pam"
  password = "raif2121"
}

