#!/bin/bash

set -e

TARGET="$1"

if [ -z "$TARGET" ]; then
  echo "❌ Usage: $0 user@hostname"
  exit 1
fi

echo "🔧 Bootstrapping server: $TARGET"

### 🔐 SSH Key Setup ###
echo "🔐 Checking for SSH key..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "🗝️  Generating new SSH key..."
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
fi

echo "📤 Pushing public key to server..."
ssh-copy-id -i ~/.ssh/id_ed25519.pub "$TARGET"

### 🔒 Initial SSH Hardening ###
echo "🚫 Disabling root password login and locking root password..."
ssh "$TARGET" << 'EOSSH'
  # Disable SSH password login for root
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  
  # Lock root password entirely
  passwd -l root

  # Restart SSH service
  echo "🔁 Restarting SSH service..."
  systemctl restart ssh || systemctl restart sshd
EOSSH


### 🧰 System Setup ###
ssh "$TARGET" bash -s <<'EOF'
  set -e

  echo "📦 Updating system and installing base packages..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-pip \
    software-properties-common \
    unzip \
    curl \
    git \
    sudo \
    sshpass

  echo "✅ Base packages installed."

  echo "📁 Creating directory for Ansible..."
  mkdir -p /opt/ansible
EOF

echo "📂 Copying Ansible project files to server..."
rsync -av --exclude='.git' --exclude='*.pyc' ./ "$TARGET:/opt/ansible"

echo "🚀 Bootstrap complete. You may now run Ansible playbooks from your local machine targeting $TARGET"
