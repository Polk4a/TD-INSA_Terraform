terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07" #3.0.2-rc07
    }
    macaddress = {
      source  = "ivoronin/macaddress"
      version = "0.3.0"
    }
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.26.0"
    }
  }
}

provider "proxmox" {
  pm_api_url                  = var.pm_api_url
  pm_api_token_id             = var.pm_api_token_id
  pm_api_token_secret         = var.pm_api_token_secret
  pm_tls_insecure              = true
  pm_minimum_permission_check = false
}

provider "opnsense" {
  uri            = var.opnsense_uri
  api_key        = var.opnsense_api_key
  api_secret     = var.opnsense_api_secret
  allow_insecure = true
}
