terraform {
  backend "local" {
    path = "/var/local/terraform-state/adguard-dns.tfstate"
  }

  required_providers {
    adguard = {
      source  = "gmichels/adguard"
      version = ">= 1.7.0" # testing 1.7.0 else i will revert to previous 1.6
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