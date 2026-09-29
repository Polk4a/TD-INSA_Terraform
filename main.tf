locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  wp_salt_names = [
    "AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
    "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT",
  ]

  wp_config = templatefile("${path.module}/wp-config.php.tpl", {
    db_name     = var.wp_db_name
    db_user     = var.wp_db_user
    db_password = var.wp_db_password
    db_host     = var.wp_db_host
    salts = join("\n", [
      for k in local.wp_salt_names : "define( '${k}', '${sha512("${var.wp_db_password}:${k}")}' );"
    ])
  })

  user_data = {
    for name in keys(var.wp_nodes) : name => templatefile("${path.module}/user-data.yml.tpl", {
      hostname       = name
      ci_user        = var.ci_user
      ssh_public_key = local.ssh_public_key
      wp_version     = var.wp_version
      bootstrap_sh   = indent(6, file("${path.module}/wp-bootstrap.sh"))
      nginx_conf     = indent(6, file("${path.module}/nginx-wordpress.conf"))
      wp_config_php  = indent(6, local.wp_config)
    })
  }

  snippet_file = { for name in keys(var.wp_nodes) : name => "${name}-user-data.yml" }
}

moved {
  from = terraform_data.upload_snippet
  to   = terraform_data.upload_snippet["sti-wp01"]
}

moved {
  from = macaddress.vmmac
  to   = macaddress.wp["sti-wp01"]
}

moved {
  from = opnsense_kea_dhcpv4_reservation.debian_clone
  to   = opnsense_kea_dhcpv4_reservation.wp["sti-wp01"]
}

moved {
  from = proxmox_vm_qemu.debian_clone
  to   = proxmox_vm_qemu.wp["sti-wp01"]
}

resource "terraform_data" "upload_snippet" {
  for_each = var.wp_nodes

  triggers_replace = {
    snippet_hash = md5(local.user_data[each.key])
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "192.168.122.220"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/vz/snippets/"
    ]
  }

  provisioner "file" {
    content     = local.user_data[each.key]
    destination = "/var/lib/vz/snippets/${local.snippet_file[each.key]}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /var/lib/vz/snippets/${local.snippet_file[each.key]}"
    ]
  }
}

resource "macaddress" "wp" {
  for_each = var.wp_nodes
#  prefix = [52, 54, 00]
}

resource "opnsense_kea_dhcpv4_reservation" "wp" {
  for_each = var.wp_nodes

  subnet_id   = "4f275fc3-7f2d-4bdb-b8a7-eb794075aa7f"
  ip_address  = each.value.ip
  mac_address = lower(macaddress.wp[each.key].address)
  hostname    = coalesce(each.value.dhcp_label, each.key)
  description = "Static IP for ${coalesce(each.value.dhcp_label, each.key)}"
}

resource "proxmox_vm_qemu" "wp" {
  for_each = var.wp_nodes

  name        = each.key
  target_node = "pve"

  depends_on  = [terraform_data.upload_snippet]

  os_type     = "cloud-init"
  ciuser    = var.ci_user
  sshkeys   = local.ssh_public_key
  clone       = "debian-cloudinit"
  full_clone  = true
  agent       = 1
  start_at_node_boot = true
#  onboot = true
  ipconfig0 = "ip=dhcp"
  cicustom = "user=local:snippets/${local.snippet_file[each.key]}"
  tags      = "wordpress"

  vmid        = each.value.vmid
  memory      = 2048
  skip_ipv6 = true

  cpu {
    cores     = 2
    sockets   = 1
    type      = "host"
  }

  disk {
    slot      = "scsi0" #scsi0/ide2
    size      = "40G"
    type      = "disk" # disk/cloudinit
    storage   = "local-lvm"
  }

  disk {
    slot      = "ide2" #scsi0/ide2
#    size      = "40G"
    type      = "cloudinit" # disk/cloudinit
    storage   = "local-lvm"
  }

  network {
    id        = 0
    model     = "virtio"
    bridge    = "vmbr1"
    macaddr   = upper(macaddress.wp[each.key].address)
  }
}

output "wp_nodes" {
  description = "IP, MAC et vmid de chaque nœud WordPress (à réutiliser pour le backend HAProxy)"
  value = {
    for name, node in var.wp_nodes : name => {
      ip   = node.ip
      mac  = upper(macaddress.wp[name].address)
      vmid = node.vmid
    }
  }
}
