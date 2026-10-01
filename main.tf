locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  ssh_private_key_path = trimsuffix(var.ssh_public_key_path, ".pub")

  database_ips = [for vm in values(var.vms) : vm.ip if vm.role == "database"]
  haproxy_ips  = [for vm in values(var.vms) : vm.ip if vm.role == "haproxy"]
  lb_ip        = one(local.haproxy_ips)

  db_host = coalesce(var.wp_db_host, one(local.database_ips), "sti-db01")

  ansible_groups = [
    for role in ["database", "wordpress", "haproxy"] : {
      role  = role
      hosts = { for name, vm in var.vms : name => vm.ip if vm.role == role }
    }
  ]

  db_allowed_hosts = [for c in var.db_allowed_cidrs : "${cidrhost(c, 0)}/${cidrnetmask(c)}"]

  ansible_vars = {
    wp_db_name                = var.wp_db_name
    wp_db_user                = var.wp_db_user
    wordpress_version         = var.wp_version
    wordpress_db_host         = local.db_host
    wordpress_only_from_proxy = var.wp_only_from_proxy
    database_allowed_hosts    = local.db_allowed_hosts
    haproxy_stats_cidrs       = var.lb_stats_cidrs
  }

  user_data = {
    for name, vm in var.vms : name => templatefile("${path.module}/user-data.yml.tpl", {
      hostname       = name
      ci_user        = var.ci_user
      ssh_public_key = local.ssh_public_key
    })
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

resource "local_file" "ansible_inventory" {
  filename             = "${path.module}/ansible/inventory.ini"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/inventory.tpl", {
    groups      = local.ansible_groups
    ci_user     = var.ci_user
    private_key = local.ssh_private_key_path
    jump_host   = var.ansible_jump_host
  })

  depends_on = [proxmox_vm_qemu.vm]
}

resource "local_file" "ansible_vars" {
  filename             = "${path.module}/ansible/group_vars/all/terraform.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = join("\n", [
    "---",
    "# GÉNÉRÉ par Terraform (main.tf) : ne pas éditer, réécrit à chaque terraform apply.",
    yamlencode(local.ansible_vars),
  ])
}

resource "local_sensitive_file" "ansible_secrets" {
  filename             = "${path.module}/ansible/group_vars/all/secrets.yml"
  file_permission      = "0600"
  directory_permission = "0755"

  content = join("\n", [
    "---",
    "# GÉNÉRÉ par Terraform (main.tf) : secret, ne jamais committer.",
    yamlencode({ wp_db_password = var.wp_db_password }),
  ])
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
  description = "Rôle, IP, MAC et vmid de chaque VM de la plateforme"
  value = {
    for name, vm in var.vms : name => {
      role = vm.role
      ip   = vm.ip
      mac  = upper(macaddress.vm[name].address)
      vmid = vm.vmid
    }
  }
}

output "lb_url" {
  description = "Point d'entrée unique du site (HAProxy) ; null sans VM haproxy"
  value       = local.lb_ip == null ? null : "http://${local.lb_ip}/"
}

output "lb_stats_url" {
  description = "Page d'état d'HAProxy (nœuds UP/DOWN, répartition) ; null si désactivée"
  value       = local.lb_ip == null || length(var.lb_stats_cidrs) == 0 ? null : "http://${local.lb_ip}:8404/stats"
}

output "wp_db_host" {
  description = "Hôte MariaDB écrit dans wp-config.php des WordPress"
  value       = local.db_host
}
