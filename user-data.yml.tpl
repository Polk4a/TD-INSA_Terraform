#cloud-config
hostname: sti-web01

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

runcmd:
- systemctl enable qemu-guest-agent
- systemctl start qemu-guest-agent
