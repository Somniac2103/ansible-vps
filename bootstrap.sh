#!/bin/bash

# Prompt for username
read -p "👤 Enter the username to create on the server: " USERNAME

# Check for target host
TARGET="$1"
if [[ -z "$TARGET" ]]; then
  echo "❌ Usage: $0 root@<server_ip>"
  exit 1
fi

echo "🔧 Bootstrapping server: $TARGET with user '$USERNAME'"

# Ensure SSH key exists
KEY="$HOME/.ssh/id_ed25519"
if [[ ! -f "$KEY" ]]; then
  echo "🗝️  Generating new SSH key..."
  ssh-keygen -t ed25519 -f "$KEY" -N ""
else
  echo "🔐 SSH key already exists."
fi

# Push SSH key to root user
echo "📤 Pushing public key to server root account..."
ssh-keygen -R "$(echo $TARGET | cut -d@ -f2)" 2>/dev/null
ssh-copy-id -i "$KEY.pub" "$TARGET" || exit 1

# Prepare server
ssh "$TARGET" bash -s <<EOF
echo "🚫 Disabling root SSH login and locking root password..."
passwd -l root

echo "➕ Creating user: $USERNAME..."
adduser --disabled-password --gecos "" $USERNAME
usermod -aG sudo $USERNAME

echo "🔐 Copying root's authorized_keys to $USERNAME..."
mkdir -p /home/$USERNAME/.ssh
cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

echo "📦 Installing base packages..."
apt update && apt install -y python3 python3-pip software-properties-common unzip curl git sudo sshpass

echo "📁 Preparing Ansible directory..."
mkdir -p /opt/ansible
chown -R $USERNAME:$USERNAME /opt/ansible
EOF

# Clone GitHub repo to temp folder on local
echo "⬇️ Cloning project from GitHub..."
rm -rf ansible-tmp
git clone https://github.com/Somniac2103/ansible-vps.git ansible-tmp

# Send to server
echo "📂 Copying Ansible project files to server..."
scp -r ansible-tmp/* "$TARGET:/opt/ansible/"

# Replace placeholder username in inventory file
ssh "$TARGET" "sed -i 's/__USERNAME__/$USERNAME/' /opt/ansible/inventory.yml"

echo "✅ Bootstrap complete. You may now run Ansible playbooks from your local machine targeting $USERNAME@$(echo $TARGET | cut -d@ -f2)"
