#!/bin/bash

# ----------------------------
# Rev 2: Secure Bootstrap Phase 1
# ----------------------------

set -euo pipefail
IFS=$'\n\t'
trap 'echo -e "\n\n❌ Script failed on line $LINENO. Check log: $LOGFILE" >&2' ERR

# ----------------------------
# Logging Setup
# ----------------------------
LOGDIR="$HOME/bootstrap-logs"
mkdir -p "$LOGDIR"
chmod 700 "$LOGDIR"
LOGFILE="$LOGDIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# ----------------------------
# 🌐 User Input & Validation
# ----------------------------

read -rp "🌐 Enter server IP address: " SERVER_IP
while ! [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; do
  echo "❌ Invalid IP format. Use something like 192.168.1.10"
  read -rp "🌐 Enter server IP address: " SERVER_IP
done

read -rp "👤 Enter NEW sudo username to create: " NEW_USER
while ! [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; do
  echo "❌ Invalid username. Use lowercase letters, digits, _ or - (max 32 chars, start with a letter or underscore)."
  read -rp "👤 Enter NEW sudo username to create: " NEW_USER
done

read -rsp "🔑 Enter password for new user '$NEW_USER': " NEW_PASS
echo
while [[ ${#NEW_PASS} -lt 8 || ! "$NEW_PASS" =~ [A-Z] || ! "$NEW_PASS" =~ [a-z] || ! "$NEW_PASS" =~ [0-9] ]]; do
  echo "❌ Password must be at least 8 characters and include upper-case, lower-case, and a digit."
  read -rsp "🔑 Enter password for new user '$NEW_USER': " NEW_PASS
  echo
done

read -rsp "🛡️  Enter root password for $SERVER_IP: " ROOT_PASS
echo
while [[ -z "$ROOT_PASS" ]]; do
  echo "❌ Root password cannot be empty."
  read -rsp "🛡️  Enter root password for $SERVER_IP: " ROOT_PASS
  echo
done

read -rp "📦 Enter Git HTTPS repo URL for Phase 2: " GIT_REPO
while ! [[ "$GIT_REPO" =~ ^https:\/\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+(\.git)?$ ]]; do
  echo "❌ Invalid Git URL. Use HTTPS format like https://github.com/user/repo.git"
  read -rp "📦 Enter Git HTTPS repo URL for Phase 2: " GIT_REPO
done

# ----------------------------
# Generate SSH Key
# ----------------------------
KEY_PATH="$HOME/.ssh/${NEW_USER}_id_ed25519"
if [[ ! -f "$KEY_PATH" ]]; then
  echo "🗝️  Generating SSH key for $NEW_USER..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
fi

# ----------------------------
# SSH Setup with sshpass
# ----------------------------
echo "🔗 Connecting as root@$SERVER_IP to create user and install packages..."

PUBKEY_CONTENT=$(cat "$KEY_PATH.pub")

sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no root@"$SERVER_IP" bash -s -- "$NEW_USER" "$NEW_PASS" "$PUBKEY_CONTENT" <<'EOS'
set -euo pipefail
USERNAME="$1"
USERPASS="$2"
PUBKEY="$3"

# Create user with adduser (creates home dir by default)
adduser --disabled-password --gecos "" "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd
usermod -aG sudo "$USERNAME"

# Configure sudo access
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$USERNAME

# Setup SSH directory
mkdir -p /home/$USERNAME/.ssh
echo "$PUBKEY" > /home/$USERNAME/.ssh/authorized_keys
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
EOS

# ----------------------------
# SSH Hardening & Ansible Install
# ----------------------------
echo "🛡️ Hardening SSH and preparing Ansible on server..."
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o BatchMode=yes "$NEW_USER@$SERVER_IP" sudo bash -s -- <<'EOSH'
set -euo pipefail

# Test SSH key login before locking down
echo "🧪 Testing SSH key login BEFORE disabling password auth..."
if ssh -i "$HOME/.ssh/${USERNAME}_id_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=no "$USERNAME@localhost" 'echo "✅ SSH key login test successful."' ; then
    echo "✅ SSH key works. Proceeding with SSH hardening."
else
    echo "❌ SSH key login failed. Aborting hardening to avoid lockout."
    exit 1
fi

# Now harden SSH
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
passwd -l root

# Install dependencies
apt update && apt install -y software-properties-common git curl sudo python3 python3-pip
add-apt-repository --yes --update ppa:ansible/ansible
apt install -y ansible

# Restart SSH
systemctl restart ssh

echo "⏳ Waiting 5 seconds for SSH to restart..."
sleep 5
EOSH

# ----------------------------
# Clone Git Repo to /tmp
# ----------------------------
echo "📁 Cloning repo to /tmp/bootstrap-phase2..."
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o BatchMode=yes "$NEW_USER@$SERVER_IP" bash -s -- "$GIT_REPO" <<'EOGIT'
REPO="$1"
rm -rf /tmp/bootstrap-phase2
mkdir -p /tmp/bootstrap-phase2
git clone "$REPO" /tmp/bootstrap-phase2
EOGIT

# ----------------------------
# Validation & Report
# ----------------------------
echo "🔍 Validating setup..."

echo "🔐 Checking SSH key login for user: $NEW_USER@$SERVER_IP..."
if ssh -i "$KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$NEW_USER@$SERVER_IP" 'echo "✅ SSH key login successful."' ; then
    SSH_STATUS="✅ SSH key login working"
else
    SSH_STATUS="❌ SSH key login failed"
fi

echo "👮 Verifying Ansible installation..."
ANSIBLE_VERSION=$(ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o BatchMode=yes "$NEW_USER@$SERVER_IP" 'ansible --version | head -n 1' 2>/dev/null || echo "❌ Ansible not found")

echo "🔍 Checking root login is disabled..."
if ssh -i "$KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$NEW_USER@$SERVER_IP" 'grep -q "^PermitRootLogin no" /etc/ssh/sshd_config'; then
  ROOT_STATUS="✅ Root login disabled"
else
  ROOT_STATUS="❌ Root login still enabled"
fi

echo "🔍 Checking password login is disabled..."
if ssh -i "$KEY_PATH" -o BatchMode=yes "$NEW_USER@$SERVER_IP" 'grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config'; then
  PASSWD_STATUS="✅ Password login disabled"
else
  PASSWD_STATUS="❌ Password login still enabled"
fi

echo "📦 Checking Git repo exists in /tmp..."
if ssh -i "$KEY_PATH" -o BatchMode=yes "$NEW_USER@$SERVER_IP" '[ -d /tmp/bootstrap-phase2 ]'; then
  REPO_STATUS="✅ Repo cloned to /tmp/bootstrap-phase2"
else
  REPO_STATUS="❌ Repo not found at /tmp/bootstrap-phase2"
fi

# ----------------------------
# Save Final Report Locally
# ----------------------------
CREDS_FILE="$HOME/server-creds/${NEW_USER}@${SERVER_IP}-$(date +%Y%m%d-%H%M).txt"
mkdir -p "$HOME/server-creds"
chmod 700 "$HOME/server-creds"

cat > "$CREDS_FILE" <<EOF
🔐 Secure Server Bootstrap Complete
===================================
Username      : $NEW_USER
Server IP     : $SERVER_IP
SSH Key       : $KEY_PATH
Login Command : ssh -i $KEY_PATH $NEW_USER@$SERVER_IP

📁 Repo cloned: $REPO_STATUS
🔐 SSH key login: $SSH_STATUS
🚫 Root login:    $ROOT_STATUS
🔒 Password login: $PASSWD_STATUS
🛠  Ansible:      $ANSIBLE_VERSION
📄 Log file: $LOGFILE
EOF
chmod 600 "$CREDS_FILE"

echo ""
echo "✅ Bootstrap Phase 1 complete. Info saved to: $CREDS_FILE"
echo "🚀 You can now proceed with Phase 2 using Ansible on $NEW_USER@$SERVER_IP"

