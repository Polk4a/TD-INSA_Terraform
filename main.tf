locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  database_ips = [for vm in values(var.vms) : vm.ip if vm.role == "database"]

  db_host = coalesce(var.wp_db_host, one(local.database_ips), "sti-db01")

  db_allowed_hosts = [for c in var.db_allowed_cidrs : "${cidrhost(c, 0)}/${cidrnetmask(c)}"]

  wp_salt_names = [
    "AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
    "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT",
  ]

  wp_config = templatefile("${path.module}/wp-config.php.tpl", {
    db_name     = var.wp_db_name
    db_user     = var.wp_db_user
    db_password = var.wp_db_password
    db_host     = local.db_host
    salts = join("\n", [
      for k in local.wp_salt_names : "define( '${k}', '${sha512("${var.wp_db_password}:${k}")}' );"
    ])
  })

  db_env = templatefile("${path.module}/db.env.tpl", {
    db_name       = var.wp_db_name
    db_user       = var.wp_db_user
    db_password   = var.wp_db_password
    allowed_hosts = join(" ", local.db_allowed_hosts)
  })

  tpl_vars = {
    ci_user         = var.ci_user
    ssh_public_key  = local.ssh_public_key
    wp_version      = var.wp_version
    bootstrap_sh    = indent(6, file("${path.module}/wp-bootstrap.sh"))
    nginx_conf      = indent(6, file("${path.module}/nginx-wordpress.conf"))
    wp_config_php   = indent(6, local.wp_config)
    db_bootstrap_sh = indent(6, file("${path.module}/db-bootstrap.sh"))
    db_conf         = indent(6, file("${path.module}/mariadb-sti.cnf"))
    db_env          = indent(6, local.db_env)
  }

  user_data = {
    for name, vm in var.vms : name => templatefile(
      "${path.module}/user-data-${vm.role}.yml.tpl",
      merge(local.tpl_vars, { hostname = name })
    )
  }

  snippet_file = { for name in keys(var.vms) : name => "${name}-user-data.yml" }
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
  from = macaddress.wp["sti-wp01"]
  to   = macaddress.vm["sti-wp01"]
}

moved {
  from = macaddress.wp["sti-wp02"]
  to   = macaddress.vm["sti-wp02"]
}

moved {
  from = opnsense_kea_dhcpv4_reservation.debian_clone
  to   = opnsense_kea_dhcpv4_reservation.wp["sti-wp01"]
}

moved {
  from = opnsense_kea_dhcpv4_reservation.wp["sti-wp01"]
  to   = opnsense_kea_dhcpv4_reservation.vm["sti-wp01"]
}

moved {
  from = opnsense_kea_dhcpv4_reservation.wp["sti-wp02"]
  to   = opnsense_kea_dhcpv4_reservation.vm["sti-wp02"]
}

moved {
  from = proxmox_vm_qemu.debian_clone
  to   = proxmox_vm_qemu.wp["sti-wp01"]
}

moved {
  from = proxmox_vm_qemu.wp["sti-wp01"]
  to   = proxmox_vm_qemu.vm["sti-wp01"]
}

moved {
  from = proxmox_vm_qemu.wp["sti-wp02"]
  to   = proxmox_vm_qemu.vm["sti-wp02"]
}

resource "terraform_data" "upload_snippet" {
  for_each = var.vms

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

  # Le snippet contient le mot de passe de la base : lisible par root uniquement
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /var/lib/vz/snippets/${local.snippet_file[each.key]}"
    ]
  }
}

resource "macaddress" "vm" {
  for_each = var.vms
#  prefix = [52, 54, 00]
}

resource "opnsense_kea_dhcpv4_reservation" "vm" {
  for_each = var.vms

  subnet_id   = "4f275fc3-7f2d-4bdb-b8a7-eb794075aa7f"
  ip_address  = each.value.ip
  mac_address = lower(macaddress.vm[each.key].address)
  hostname    = coalesce(each.value.dhcp_label, each.key)
  description = "Static IP for ${coalesce(each.value.dhcp_label, each.key)}"
}

resource "proxmox_vm_qemu" "vm" {
  for_each = var.vms

  name        = each.key
  target_node = "pve"

  depends_on  = [terraform_data.upload_snippet, opnsense_kea_dhcpv4_reservation.vm]

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
  tags      = each.value.role

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
    macaddr   = upper(macaddress.vm[each.key].address)
  }
}

resource "opnsense_firewall_filter" "db_from_web_only" {
  for_each = var.db_firewall_interface == null || length(local.database_ips) == 0 ? toset([]) : toset(var.db_allowed_cidrs)

  description = "MariaDB - VLAN web uniquement (${each.value})"

  interface = {
    interface = [var.db_firewall_interface]
  }

  filter = {
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "TCP"
    source      = { net = each.value }
    destination = { net = local.database_ips[0], port = "3306" }
  }
}

output "vms" {
  description = "Rôle, IP, MAC et vmid de chaque VM (à réutiliser pour le backend HAProxy)"
  value = {
    for name, vm in var.vms : name => {
      role = vm.role
      ip   = vm.ip
      mac  = upper(macaddress.vm[name].address)
      vmid = vm.vmid
    }
  }
}

output "wp_db_host" {
  description = "Hôte MariaDB écrit dans wp-config.php des WordPress"
  value       = local.db_host
}
