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

# ---------------------------------------------------------------------------
# sti-wp01 : WordPress (nginx + php-fpm) prêt à se brancher sur MariaDB / HAProxy
# ---------------------------------------------------------------------------

variable "wp_version" {
  description = "Version de WordPress téléchargée sur wordpress.org (à garder identique sur tous les nœuds WordPress)"
  type        = string
  default     = "7.1.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.wp_version))
    error_message = "wp_version doit être un numéro de version précis (ex : 7.1.2)."
  }
}

variable "wp_db_host" {
  description = "Nom DNS ou IP de la VM MariaDB (sti-db01), avec :port optionnel. À remplacer par son IP dès qu'elle existe."
  type        = string
  default     = "sti-db01"

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+(:[0-9]{1,5})?$", var.wp_db_host))
    error_message = "wp_db_host : hôte ou IP (A-Z a-z 0-9 . -), avec :port optionnel."
  }
}

variable "wp_db_name" {
  description = "Nom de la base WordPress sur MariaDB (créée plus tard par le rôle database)"
  type        = string
  default     = "wordpress"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]{1,64}$", var.wp_db_name))
    error_message = "wp_db_name : lettres, chiffres et _ uniquement (64 max)."
  }
}

variable "wp_db_user" {
  description = "Utilisateur MariaDB de WordPress"
  type        = string
  default     = "wordpress"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]{1,32}$", var.wp_db_user))
    error_message = "wp_db_user : lettres, chiffres et _ uniquement (32 max)."
  }
}

variable "wp_db_password" {
  description = "Mot de passe MariaDB de WordPress, à mettre dans terraform.tfvars (hors Git). Les clés/sels WordPress en sont dérivés : ils sont donc identiques sur tous les nœuds, indispensable derrière HAProxy en round-robin."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{12,}$", var.wp_db_password))
    error_message = "wp_db_password : 12 caractères minimum, uniquement A-Z a-z 0-9 . _ - (ex : openssl rand -hex 24)."
  }
}

variable "wp_nodes" {
  description = "Nœuds WordPress (nginx + php-fpm), identiques, clonés depuis le même template : nom => vmid + IP fixe (réservation Kea sur OPNsense). Ajouter une entrée = ajouter un nœud."
  type = map(object({
    vmid       = number
    ip         = string
    dhcp_label = optional(string) # libellé de la réservation Kea (défaut : le nom du nœud)
  }))

  default = {
    "sti-wp01" = {
      vmid       = 120
      ip         = "10.0.0.140"
      dhcp_label = "tf_cloned_debian" # libellé historique, conservé pour ne rien modifier côté OPNsense
    }
    "sti-wp02" = {
      vmid = 121
      ip   = "10.0.0.160"
    }
  }

  validation {
    condition     = alltrue([for name in keys(var.wp_nodes) : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name))])
    error_message = "Noms de nœuds : minuscules, chiffres et tirets uniquement (ex : sti-wp01)."
  }

  validation {
    condition     = alltrue([for n in values(var.wp_nodes) : can(cidrhost("${n.ip}/32", 0))])
    error_message = "Chaque ip doit être une adresse IPv4 valide."
  }

  validation {
    condition     = length(distinct([for n in values(var.wp_nodes) : n.ip])) == length(var.wp_nodes) && length(distinct([for n in values(var.wp_nodes) : n.vmid])) == length(var.wp_nodes)
    error_message = "Les IP et les vmid doivent être uniques."
  }
}
