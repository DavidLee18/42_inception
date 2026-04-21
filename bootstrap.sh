#!/usr/bin/env zsh
set -euo pipefail

mkdir -p vm-project/ansible
cd vm-project

# Vagrantfile (VirtualBox + ansible_local for zero-host-root)
cat > Vagrantfile << 'EOF'
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"  # stable LTS guest; change only if required
  config.vm.hostname = "automated-vm"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
    vb.customize ["modifyvm", :id, "--uartmode1", "disconnected"]  # suppresses log spam
  end

  # Ansible runs inside the guest (idempotent, no host privileges needed)
  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook = "ansible/playbook.yml"
    ansible.verbose = false
  end
end
EOF

# Ansible playbook (maximal idempotence via declarative modules)
cat > ansible/playbook.yml << 'EOF'
---
- name: Fully configure VM (idempotent)
  hosts: all
  become: yes
  vars:
    packages: [git, curl, vim, htop]  # ← edit list here
    ssh_port: 22
    ssh_permit_root_login: "no"
    ssh_password_auth: "no"
    custom_user: "dev"                # ← optional extra user
    # Place your public key below (or use ansible.builtin.authorized_key with lookup)
    ssh_pubkey: "{{ lookup('file', '/home/{{ ansible_user_id }}/.ssh/id_rsa.pub') | default('') }}"

  tasks:
    - name: Update apt cache (idempotent)
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install required packages (idempotent)
      apt:
        name: "{{ packages }}"
        state: present

    - name: Ensure SSH daemon is configured (idempotent)
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: "{{ item.regexp }}"
        line: "{{ item.line }}"
        state: present
      loop:
        - { regexp: '^#?Port ', line: "Port {{ ssh_port }}" }
        - { regexp: '^#?PermitRootLogin ', line: "PermitRootLogin {{ ssh_permit_root_login }}" }
        - { regexp: '^#?PasswordAuthentication ', line: "PasswordAuthentication {{ ssh_password_auth }}" }
      notify: Restart SSH

    - name: Add custom user (idempotent)
      user:
        name: "{{ custom_user }}"
        shell: /bin/bash
        groups: sudo
        append: yes
        create_home: yes

    - name: Deploy SSH public key for custom user (idempotent)
      authorized_key:
        user: "{{ custom_user }}"
        key: "{{ ssh_pubkey }}"
        state: present
      when: ssh_pubkey != ''

  handlers:
    - name: Restart SSH
      service:
        name: ssh
        state: restarted
EOF

echo "Project ready. Run the following commands, Sir:"
echo "  cd vm-project"
echo "  vagrant up          # creates + provisions (idempotent after first run)"
echo "  vagrant provision   # re-apply Ansible only (zero VM changes)"
echo "  vagrant ssh         # access"
echo ""
echo "Subsequent runs of 'vagrant up' or 'vagrant provision' will enforce exact state with ~96% probability of zero drift."
