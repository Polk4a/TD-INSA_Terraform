#cloud-config
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
  - mariadb-server
  - mariadb-client

# Fichiers déposés en "staging" au premier démarrage (MariaDB n'est pas encore
# installé). db-bootstrap.sh les installe ensuite et crée la base et le compte.
write_files:
  - path: /opt/db-provision/db-bootstrap.sh
    permissions: '0700'
    content: |
      ${db_bootstrap_sh}
  - path: /opt/db-provision/mariadb-sti.cnf
    permissions: '0644'
    content: |
      ${db_conf}
  - path: /opt/db-provision/db.env
    permissions: '0600'
    content: |
      ${db_env}

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - [ /opt/db-provision/db-bootstrap.sh ]
