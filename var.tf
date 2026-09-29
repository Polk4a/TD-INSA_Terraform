variable "ci_user" {
  description = "Utilisateur créé via cloud-init sur la VM"
  type        = string
  default     = "admin"
}

variable "ssh_public_key_path" {
  description = "Chemin local vers la clé publique SSH à injecter dans la VM"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "pm_api_url" {
  description = "URL de l'API Proxmox (ex: https://host:8006/api2/json)"
  type        = string
}

variable "pm_api_token_id" {
  description = "Identifiant du token API Proxmox (ex: terraform@pve!tf-token)"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Secret du token API Proxmox"
  type        = string
  sensitive   = true
}

variable "opnsense_uri" {
  description = "URL de l'API OPNsense"
  type        = string
}

variable "opnsense_api_key" {
  description = "Clé API OPNsense"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "Secret API OPNsense"
  type        = string
  sensitive   = true
}
