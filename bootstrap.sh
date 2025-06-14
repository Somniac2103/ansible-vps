#!/bin/bash

# ----------------------------
# Rev 1: Hardened Bootstrap Script
# ----------------------------

# Safe scripting practices
set -euo pipefail
IFS=$'\n\t'
trap 'echo -e "\n❌ Script failed on line $LINENO. Exiting." >&2' ERR

# ----------------------------
# Step 1: Prompt for username
# ----------------------------
read -rp "👤 Enter the username to create on the server: " USERNAME
if [[ -z "$USERNAME" || "$USERNAME" =~ [^a-zA-Z0-9_-] ]]; then
  echo "❌ Invalid username. Use only letters, numbers, dashes, or underscores."
  exit 1
fi

# ----------------------------
# Step 2: Validate target input
# ----------------------------
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "❌ Usage: $0 root@<server_ip>"
  exit 1
fi
SERVER_IP="$(echo "$TARGET" | cut -d@ -f2)"
echo "🔧 Bootstrapping server: $SERVER_IP with user '$USERNAME'"

# ----------------------------
# Step 3: SSH key setup
# ----------------------------
KEY="$HOME/.ssh/id_ed25519"
if [[ ! -f "$KEY" ]]; then
  echo "🗝️  Generating SSH key..."
  ssh-keygen -t ed25519 -f "$KEY" -N ""
else
  echo "🔐 SSH key already exists."
fi

# Start ssh-agent and add key
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$KEY" || true

# Clean old host fingerprint
ssh-keygen -R "$SERVER_IP" 2>/dev/null || true
ssh-keyscan -H "$SERVER_IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null

# ----------------------------
# Step 4: Push key to root
# ----------------------------
echo "📤 Pushing public key to server root account..."
ssh-copy-id -i "$KEY.pub" "$TARGET" || {
  echo "❌ SSH key push failed"
  exit 1
}

# ----------------------------
# Step 5: Remote server setup
# ----------------------------
ssh "$TARGET" bash -s -- "$USERNAME" <<'EOF'
set -euo pipefail
USERNAME="$1"

echo "🔒 Disabling root SSH access and password..."
passwd -l root || true
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

if ! id "$USERNAME" &>/dev/null; then
  echo "➕ Creating user: $USERNAME"
  adduser --disabled-password --gecos "" "$USERNAME"
  usermod -aG sudo "$USERNAME"
else
  echo "⚠️  User $USERNAME already exists."
fi

echo "🔑 Setting up SSH for $USERNAME"
mkdir -p /home/$USERNAME/.ssh
cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys

echo "📦 Installing packages..."
apt update -y
apt install -y python3 python3-pip git unzip curl software-properties-common sudo

echo "📁 Preparing Ansible directory..."
mkdir -p /opt/ansible
chown -R $USERNAME:$USERNAME /opt/ansible

echo "🔁 Restarting SSH..."
systemctl restart sshd
EOF

# ----------------------------
# Step 6: Clone Ansible project
# ----------------------------
echo "⬇️ Cloning Ansible project..."
rm -rf ansible-tmp
if ! git clone https://github.com/Somniac2103/ansible-vps.git ansible-tmp; then
  echo "❌ Git clone failed"
  exit 1
fi

# ----------------------------
# Step 7: Copy project to server
# ----------------------------
echo "📂 Copying project to server..."
scp -r ansible-tmp/* "$USERNAME@$SERVER_IP:/opt/ansible/"

# ----------------------------
# Step 8: Patch inventory file
# ----------------------------
echo "🛠️ Updating inventory username..."
ssh "$USERNAME@$SERVER_IP" "sed -i 's/__USERNAME__/$USERNAME/' /opt/ansible/inventory.yml"

# ----------------------------
# Step 9: Local cleanup
# ----------------------------
echo "🧹 Cleaning up local files..."
rm -rf ansible-tmp

# ----------------------------
# Finished
# ----------------------------
echo "✅ Bootstrap complete. Ansible is ready for: $USERNAME@$SERVER_IP"
