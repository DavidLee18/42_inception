Vagrant.configure("2") do |config|
  config.vm.box      = "debian/bookworm64"
  config.vm.hostname = "inception"

  # Host-only network — all container ports are reachable from the host at
  # this IP without individual port-forward rules (including FTP passives).
  # Add to your HOST /etc/hosts before running `make`:
  #   echo "192.168.56.10  jaehylee.42.fr" | sudo tee -a /etc/hosts
  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "inception"
    vb.memory = 4096
    vb.cpus   = 2
    # Use the host DNS resolver so the VM can reach the internet for Docker packages.
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
  end

  # The project root is synced to /vagrant inside the VM.
  # Secrets written under /vagrant/srcs/secrets/ are mirrored to the host,
  # so they survive a `vagrant destroy` and are not re-generated on the next
  # `vagrant up` (Ansible uses force: no for those files).

  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook           = "ansible/playbook.yml"
    ansible.compatibility_mode = "2.0"
  end

  config.vm.post_up_message = <<~MSG
    ─────────────────────────────────────────────────────────────────
    VM ready.  Complete setup on your HOST machine:

      echo "192.168.56.10  jaehylee.42.fr" | sudo tee -a /etc/hosts

    Then SSH in and start the stack:

      vagrant ssh
      cd /vagrant && make

    Default secrets are in srcs/secrets/ — edit before the eval if
    you want non-default credentials.

    To wipe everything and start fresh:

      vagrant destroy -f && vagrant up
    ─────────────────────────────────────────────────────────────────
  MSG
end
