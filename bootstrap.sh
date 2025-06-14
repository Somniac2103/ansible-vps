#!/bin/bash

set -e

TARGET="$1"
REPO_URL="https://github.com/Somniac2103/ansible-vps.git"
INVENTORY_PATH="./inventory.yml"

if [ -z "$TARGET" ]; then
  echo "❌ Usage: $0 root@hostname"
  exit 1
fi

read -p "👤 Enter the username to create on the server: " USERNAME
if [ -z "$USERNAME" ]; then
  echo "❌ Username cannot be empty"
  exit 1
fi

echo "🔧 Bootstrapping server: $TARGET with user '$USERNAME'"

### 🔐 SSH Key Setup ###
echo "🔐 Checking for SSH key..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "🗝️  Generating new SSH key..."
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
fi

echo "📤 Pushing public key to server root account..."
ssh-copy-id -i ~/.ssh/id_ed25519.pub "$TARGET"

### 🔒 SSH Hardening & User Creation ###
ssh "$TARGET" bash -s <<EOF
set -e

echo "🚫 Disabling root SSH login and locking root password..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
passwd -l root
systemctl restart ssh || systemctl restart sshd

echo "👤 Creating user '$USERNAME'..."
id $USERNAME &>/dev/null || useradd -m -s /bin/bash $USERNAME

echo "🔑 Configuring SSH access for '$USERNAME'..."
mkdir -p /home/$USERNAME/.ssh
cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME

echo "🔧 Enforcing SSH key login..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd

echo "📦 Installing base packages..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3 python3-pip software-properties-common unzip curl git sudo sshpass

echo "📁 Preparing Ansible directory..."
mkdir -p /opt/ansible
chown -R $USERNAME:$USERNAME /opt/ansible
EOF

### ⬇️ Clone GitHub Repo ###
echo "⬇️ Cloning project from GitHub..."
rm -rf ./ansible-tmp
git clone "$REPO_URL" ./ansible-tmp

echo "📂 Copying files to remote server..."
rsync -av --exclude='.git' ./ansible-tmp/ "$USERNAME@${TARGET#*@}:/opt/ansible"

### 📝 Update inventory with username ###
echo "✍️ Updating inventory.yml with username '$USERNAME'..."
sed -i "s/ansible_user: __USERNAME__/ansible_user: $USERNAME/" "$INVENTORY_PATH"

echo "✅ Bootstrap complete. You can now run Ansible using inventory.yml."
