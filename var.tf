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

variable "vms" {
  description = "VMs de la plateforme, clonées depuis le même template : nom => rôle, vmid et IP fixe (réservation Kea sur OPNsense). Rôles : wordpress, database."
  type = map(object({
    role       = string
    vmid       = number
    ip         = string
    dhcp_label = optional(string) # libellé de la réservation Kea (défaut : le nom de la VM)
  }))

  default = {
    "sti-wp01" = {
      role       = "wordpress"
      vmid       = 120
      ip         = "10.0.0.140"
      dhcp_label = "tf_cloned_debian" # libellé historique, conservé pour ne rien modifier côté OPNsense
    }
    "sti-wp02" = {
      role = "wordpress"
      vmid = 121
      ip   = "10.0.0.160"
    }
    "sti-db01" = {
      role = "database"
      vmid = 122
      ip   = "10.0.0.170"
    }
  }

  validation {
    condition     = alltrue([for name in keys(var.vms) : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name))])
    error_message = "Noms de VM : minuscules, chiffres et tirets uniquement (ex : sti-wp01)."
  }

  validation {
    condition     = alltrue([for vm in values(var.vms) : contains(["wordpress", "database"], vm.role)])
    error_message = "role doit valoir « wordpress » ou « database »."
  }

  validation {
    condition     = alltrue([for vm in values(var.vms) : can(cidrhost("${vm.ip}/32", 0))])
    error_message = "Chaque ip doit être une adresse IPv4 valide."
  }

  validation {
    condition     = length(distinct([for vm in values(var.vms) : vm.ip])) == length(var.vms) && length(distinct([for vm in values(var.vms) : vm.vmid])) == length(var.vms)
    error_message = "Les IP et les vmid doivent être uniques."
  }

  validation {
    condition     = length([for vm in values(var.vms) : vm if vm.role == "database"]) <= 1
    error_message = "Une seule VM au rôle « database » : la base MariaDB est partagée par tous les WordPress."
  }
}

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
  description = "Hôte MariaDB vu par WordPress (avec :port optionnel). Par défaut (null) : l'IP de la VM au rôle « database »."
  type        = string
  default     = null

  validation {
    condition     = var.wp_db_host == null || can(regex("^[A-Za-z0-9.-]+(:[0-9]{1,5})?$", var.wp_db_host))
    error_message = "wp_db_host : hôte ou IP (A-Z a-z 0-9 . -), avec :port optionnel."
  }
}

variable "wp_db_name" {
  description = "Nom de la base WordPress sur MariaDB (créée sur la VM « database »)"
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
  description = "Mot de passe MariaDB de WordPress, à mettre dans terraform.tfvars (hors Git). Utilisé des deux côtés (création du compte sur la base, wp-config.php sur les WordPress). Les clés/sels WordPress en sont dérivés : ils sont donc identiques sur tous les nœuds, indispensable derrière HAProxy en round-robin."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{12,}$", var.wp_db_password))
    error_message = "wp_db_password : 12 caractères minimum, uniquement A-Z a-z 0-9 . _ - (ex : openssl rand -hex 24)."
  }
}

variable "db_allowed_cidrs" {
  description = "Réseaux autorisés à se connecter à MariaDB (« VLAN web » du cours) : le compte WordPress n'existe que pour ces sources. Pour resserrer aux seuls WordPress : [\"10.0.0.140/32\", \"10.0.0.160/32\"]."
  type        = list(string)
  default     = ["10.0.0.0/24"]

  validation {
    condition     = length(var.db_allowed_cidrs) > 0 && alltrue([for c in var.db_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "db_allowed_cidrs : liste non vide de réseaux CIDR IPv4 (ex : 10.0.0.0/24)."
  }
}

variable "db_firewall_interface" {
  description = "Interface OPNsense (ex : \"lan\") sur laquelle créer la règle du cours « MariaDB (TCP 3306) depuis le VLAN web ». Défaut null = aucune règle. Sans effet tant que les VM partagent le même sous-réseau (ce trafic ne traverse pas OPNsense) : utile si la base est placée dans un autre VLAN."
  type        = string
  default     = null
}
