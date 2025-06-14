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
echo "🚫 Fully disabling root SSH login and locking root account..."
ssh "$TARGET" << 'EOSSH'
  # Fully disable root login over SSH
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

  # Lock root password (already in place)
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

echo "👤 Creating secure 'somniac' user with SSH access only..."
ssh "$TARGET" bash -s <<'EOSSH'
  # Create user if it doesn't exist
  if ! id somniac &>/dev/null; then
    useradd -m -s /bin/bash somniac
  fi

  # Copy root's authorized_keys for somniac
  mkdir -p /home/somniac/.ssh
  cp /root/.ssh/authorized_keys /home/somniac/.ssh/authorized_keys
  chown -R somniac:somniac /home/somniac/.ssh
  chmod 700 /home/somniac/.ssh
  chmod 600 /home/somniac/.ssh/authorized_keys

  # Give somniac passwordless sudo
  echo "somniac ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/somniac

  # Enforce key-based login only
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

  systemctl restart ssh || systemctl restart sshd
EOSSH


echo "🚀 Bootstrap complete. You may now run Ansible playbooks from your local machine targeting $TARGET"
