Vagrant.configure("2") do |config|
  config.vm.box      = "debian/bookworm64"
  config.vm.hostname = "inception"

# NAT port forwards — no kernel module or root required on cluster host.
# All mappings bind to cluster-PC loopback only (host_ip: "127.0.0.1") so
# nothing is exposed beyond the local machine. These are hypervisor-layer
# forwards, external to the Docker `limbo` network; nginx remains the sole
# 443 entrypoint to the infrastructure as required by the subject.
fwd = ->(guest, host) {
  config.vm.network "forwarded_port",
  guest: guest, host: host,
  host_ip: "127.0.0.1",
  auto_correct: true
}
 
   fwd.call(443,  8443)   # nginx  — WordPress HTTPS
   fwd.call(8080, 8080)   # static — barbell site
   fwd.call(8081, 8081)   # adminer
   fwd.call(9090, 9090)   # prometheus
   fwd.call(3000, 3000)   # grafana
   fwd.call(21,   2121)   # ftp control
   (21100..21110).each { |p| fwd.call(p, p) }   # ftp passive range

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
    VM ready. Start the stack inside the VM:
    
      vagrant ssh
      cd /vagrant && make

    Then on the cluster PC, access services at:

      https://jaehylee.42.fr:8443   (WordPress — self-signed cert)
      http://localhost:8080         (static site)
      http://localhost:8081         (Adminer)
      http://localhost:9090         (Prometheus)
      http://localhost:3000         (Grafana)
      ftp://localhost:2121          (FTP — passive range 21100-21110)

    Domain resolution on the cluster PC (sudoless options):

      # Firefox-only (most reliable, per-profile):
      echo 'user_pref("network.dns.localDomains","jaehylee.42.fr");' \
        >> ~/.mozilla/firefox/*.default*/user.js

      # Or shell-wide via HOSTALIASES (curl + most glibc clients):
      echo 'jaehylee.42.fr localhost' > ~/.hosts
      echo 'export HOSTALIASES=$HOME/.hosts' >> ~/.zshrc
      exec zsh -l

      # Or per-invocation:
      curl -k --resolve jaehylee.42.fr:8443:127.0.0.1 https://jaehylee.42.fr:8443
    
    Default secrets are in srcs/secrets/ — edit before the eval if
    you want non-default credentials.

    To wipe everything and start fresh:

      vagrant destroy -f && vagrant up
    ─────────────────────────────────────────────────────────────────
  MSG
end
