#cloud-config
# Préparation de base, identique pour tous les rôles : nom, utilisateur, clé SSH et paquets
# dont Ansible a besoin. Les logiciels (nginx, MariaDB, HAProxy...) sont installés ensuite
# par Ansible : voir ansible/site.yml.
hostname: ${hostname}
manage_etc_hosts: true

users:
  - default
  - name: ${ci_user}
    groups: [sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
package_upgrade: true
packages:
  - vim
  - curl
  - python3
  - python3-apt

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
