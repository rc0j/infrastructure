terraform {
  required_providers {
    adguard = {
      source  = "gmichels/adguard"
      version = ">= 1.7.0"
    }
  }
}

provider "adguard" {
  host     = "192.168.100.97"
  username = "admin"
  password = "rockwell1234"
  scheme   = "http"
  timeout  = 5
  insecure = false
}