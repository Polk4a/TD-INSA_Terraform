# Inventaire Ansible GÉNÉRÉ par Terraform (inventory.tpl) : ne pas éditer à la main,
# il est réécrit à chaque « terraform apply ». Un groupe par rôle de la table var.vms
# (un groupe sans VM reste présent, vide).

%{ for g in groups ~}
[${g.role}]
%{ for name, ip in g.hosts ~}
${name} ansible_host=${ip}
%{ endfor ~}

%{ endfor ~}
[all:vars]
ansible_user=${ci_user}
ansible_ssh_private_key_file=${private_key}
ansible_python_interpreter=/usr/bin/python3
%{ if jump_host != null ~}
ansible_ssh_common_args='-o ProxyJump=${jump_host}'
%{ endif ~}
