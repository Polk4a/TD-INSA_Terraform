# Plateforme WordPress : Terraform + cloud-init + Ansible

HAProxy → 2 × nginx + WordPress → MariaDB, sur Proxmox, avec des IP fixes réservées dans Kea (OPNsense).

| VM | Rôle | IP | vmid |
|---|---|---|---|
| `sti-lb01` | HAProxy : point d'entrée (port 80), page d'état (port 8404) | `10.0.0.180` | 123 |
| `sti-wp01`, `sti-wp02` | nginx + php-fpm + WordPress | `10.0.0.140`, `10.0.0.160` | 120, 121 |
| `sti-db01` | MariaDB partagée | `10.0.0.170` | 122 |

- **Terraform** crée les VM (clone de `debian-cloudinit`, MAC générée, réservation Kea) puis écrit l'inventaire et les variables d'Ansible.
- **cloud-init** se limite à la préparation de base (nom d'hôte, utilisateur, clé SSH, Python).
- **Ansible** installe et configure les logiciels (rôles `database`, `wordpress`, `haproxy`) et peut être rejoué à volonté.

## Prérequis

- Proxmox avec le modèle `debian-cloudinit` ; OPNsense avec Kea et une clé API.
- Terraform, Ansible (testé avec ansible-core 2.19) et une clé SSH `~/.ssh/id_ed25519`.
- Un `terraform.tfvars` (ignoré par git) :

```hcl
pm_api_url          = "https://<proxmox>:8006/api2/json"
pm_api_token_id     = "root@pam!terraform"
pm_api_token_secret = "…"
opnsense_uri        = "https://<opnsense>"
opnsense_api_key    = "…"
opnsense_api_secret = "…"
wp_db_password      = "…"   # 12 caractères minimum : lettres, chiffres, . _ -
```

## Déploiement

```bash
terraform init && terraform apply     # VM, puis ansible/inventory.ini et ansible/group_vars/

cd ansible
ansible-galaxy collection install -r requirements.yml    # une seule fois (community.mysql)
ansible-playbook site.yml                                # base → WordPress → HAProxy
```

Si les VM ne sont pas joignables directement depuis ce poste, renseigner `ansible_jump_host`
(ex : `root@192.168.122.220`) puis relancer `terraform apply`.

## Vérifier

```bash
curl -sI "$(terraform output -raw lb_url)" | head -1       # le site répond via HAProxy
for i in 1 2 3 4; do curl -sI "$(terraform output -raw lb_url)" | grep -i x-served-by; done   # alternance wp01 / wp02
```

État des nœuds : `terraform output lb_stats_url`.

## Exploiter

| Action | Commande |
|---|---|
| Ajouter un nœud WordPress | une ligne de plus dans `vms` (`var.tf`), puis `terraform apply` et `ansible-playbook site.yml` |
| Simuler sans rien modifier, voir les écarts | `ansible-playbook site.yml --check --diff` |
| Ne reconfigurer qu'une VM | `ansible-playbook site.yml --limit sti-wp01` |

## Fichiers

```
main.tf  var.tf  provider.tf    Terraform (la table var.vms décrit toutes les VM)
user-data.yml.tpl               cloud-init de base, commun aux VM
inventory.tpl                   modèle de l'inventaire Ansible
ansible/
  site.yml  ansible.cfg  requirements.yml
  roles/{database,wordpress,haproxy}/
  inventory.ini                 généré par Terraform, ignoré par git
  group_vars/all/               généré par Terraform, ignoré par git (secrets.yml en 0600)
```

## Secrets

Jamais dans git : `terraform.tfvars`, `*.tfstate` (le mot de passe de la base y figure aussi),
`ansible/inventory.ini`, `ansible/group_vars/`.
