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
  - nginx
  - php-fpm
  - php-cli
  - php-mysql
  - php-curl
  - php-gd
  - php-intl
  - php-mbstring
  - php-xml
  - php-zip

write_files:
  - path: /opt/wp-provision/wp-bootstrap.sh
    permissions: '0700'
    content: |
      ${bootstrap_sh}
  - path: /opt/wp-provision/nginx-wordpress.conf
    permissions: '0644'
    content: |
      ${nginx_conf}
  - path: /opt/wp-provision/wp-config.php
    permissions: '0600'
    content: |
      ${wp_config_php}

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - [ /opt/wp-provision/wp-bootstrap.sh, "${wp_version}" ]
