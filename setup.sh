#!/usr/bin/env zsh
mkdir -p "/goinfre/jaehylee/VirtualBox VMs"
VBoxManage setproperty machinefolder "/goinfre/jaehylee/VirtualBox VMs"

# Create the new location under your free space
mkdir -p "/goinfre/jaehylee/.vagrant.d"

# Move any existing (likely empty) Vagrant state if present
if [[ -d "$HOME/.vagrant.d" ]]; then
  mv "$HOME/.vagrant.d" "/goinfre/jaehylee/.vagrant.d.bak" 2>/dev/null || true
fi

# Set for current session
export VAGRANT_HOME="/goinfre/jaehylee/.vagrant.d"

# Make persistent in zsh (tiny addition to ~/.zshrc)
echo 'export VAGRANT_HOME="/goinfre/jaehylee/.vagrant.d"' >> ~/.zshrc
source ~/.zshrc
