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

echo "📤 Pushing public key to server root account..."
ssh-copy-id -i ~/.ssh/id_ed25519.pub "$TARGET"

### 🔒 Full SSH Hardening ###
echo "🚫 Disabling root SSH login and locking root password..."
ssh "$TARGET" bash -s << 'EOSSH'
set -e

# Fully disable root SSH login
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable password login entirely
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Lock root account
passwd -l root || true
EOSSH

### 🧰 System Setup ###
ssh "$TARGET" bash -s << 'EOSSH'
set -e

echo "⏳ Waiting for unattended-upgrades to finish..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  sleep 3
done

echo "📦 Installing base packages..."
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

echo "👤 Creating secure user 'somniac'..."
# Create user if not exists
if ! id somniac &>/dev/null; then
  useradd -m -s /bin/bash somniac
fi

# Ensure SSH directory exists
mkdir -p /home/somniac/.ssh

# Copy root's authorized_keys to somniac
cp /root/.ssh/authorized_keys /home/somniac/.ssh/authorized_keys
chown -R somniac:somniac /home/somniac/.ssh
chmod 700 /home/somniac/.ssh
chmod 600 /home/somniac/.ssh/authorized_keys

# Add passwordless sudo
echo "somniac ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/somniac

# Create ansible working dir
mkdir -p /opt/ansible
EOSSH

echo "📂 Copying Ansible project files to server..."
rsync -av --exclude='.git' --exclude='*.pyc' ./ "$TARGET:/opt/ansible"

echo "🔁 Restarting SSH service to apply changes..."
ssh "$TARGET" "systemctl restart ssh || systemctl restart sshd"

echo "🚀 Bootstrap complete. Now login using: ssh somniac@<host>"
