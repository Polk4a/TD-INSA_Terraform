locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "terraform_data" "upload_snippet" {
  triggers_replace = {
    snippet_hash = md5(templatefile("${path.module}/user-data.yml.tpl", {
      ci_user        = var.ci_user
      ssh_public_key = local.ssh_public_key
    }))
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
    content = templatefile("${path.module}/user-data.yml.tpl", {
      ci_user        = var.ci_user
      ssh_public_key = local.ssh_public_key
    })
    destination = "/var/lib/vz/snippets/user-data.yml"
  }
}

resource "macaddress" "vmmac" {
#  prefix = [52, 54, 00]
}

resource "opnsense_kea_dhcpv4_reservation" "debian_clone" {
  subnet_id   = "4f275fc3-7f2d-4bdb-b8a7-eb794075aa7f"
  ip_address  = "10.0.0.140"
  mac_address = lower(macaddress.vmmac.address)
  hostname    = "tf_cloned_debian"
  description = "Static IP for tf_cloned_debian"
}

resource "proxmox_vm_qemu" "debian_clone" {
  name        = "debian-TerraCloned"
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
  cicustom = "user=local:snippets/user-data.yml"

  vmid        = 120
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
    macaddr   = upper(macaddress.vmmac.address)
  }
}
