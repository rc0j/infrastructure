terraform {
  backend "local" {
    path = "/var/local/terraform-state/adguard-dns.tfstate"
  }

  required_providers {
    adguard = {
      source  = "gmichels/adguard"
      version = ">= 1.6.2"
    }
  }
}

provider "adguard" {
  host     = "192.168.100.97"
  username = "admin"
  password = var.adguard_admin_password 
  scheme   = "http"
  timeout  = 5 
  insecure = false 
}

variable "adguard_admin_password" {
  type        = string
  description = "Admin password to login to AdguardHome."
}