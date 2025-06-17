#!/bin/bash

# ----------------------------
# Rev 1: Hardened Bootstrap Script
# ----------------------------

# Safe scripting practices
set -euo pipefail
IFS=$'\n\t'
trap 'echo -e "\n❌ Script failed on line $LINENO. Exiting." >&2' ERR

# ----------------------------
# Step 0: Logging Setup
# ----------------------------
LOGDIR="$HOME/bootstrap-logs"
mkdir -p "$LOGDIR"
chmod 700 "$LOGDIR"

LOGFILE="$LOGDIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1



# ----------------------------
# Step 1: Prompt for username and password
# ----------------------------

# Prompt for username
read -rp "👤 Enter the username to create on the server: " USERNAME
if [[ -z "$USERNAME" || "$USERNAME" =~ [^a-zA-Z0-9_-] ]]; then
  echo "❌ Invalid username. Use only letters, numbers, dashes, or underscores."
  exit 1
fi

# Prompt for password (hidden)
read -rsp "🔑 Enter a password for user '$USERNAME': " USER_PASSWORD
echo
read -rsp "🔁 Confirm password: " USER_PASSWORD_CONFIRM
echo

# Validate password
if [[ -z "$USER_PASSWORD" || "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
  echo "❌ Passwords do not match or are empty."
  exit 1
fi

# ----------------------------
# Help and Verify Flag Handler
# ----------------------------
if [[ "${1:-}" == "--help" ]]; then
  echo "🔧 Hardened Bootstrap Script"
  echo "Usage: $0 root@<server_ip or hostname>"
  echo ""
  echo "Options:"
  echo "  --verify      Only verify server state without changing anything"
  echo "  --help        Show this help message"
  exit 0
fi

if [[ "${1:-}" == "--verify" ]]; then
  echo "🔍 VERIFY MODE: Checking system state only..."
  echo "--------------------------------------------"

  echo -n "🔒 Root password locked: "
  passwd -S root | grep -q ' L ' && echo "✅ Yes" || echo "❌ No"

  echo -n "🚫 PermitRootLogin disabled in sshd_config: "
  grep -Ei '^PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config && echo "✅" || echo "❌"

  echo -n "🔐 PasswordAuthentication disabled: "
  grep -Ei '^PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config && echo "✅" || echo "❌"

  echo -n "🧷 Root SSH key removed: "
  [ ! -f /root/.ssh/authorized_keys ] && echo "✅" || echo "❌ Still exists"

  echo "🧰 Installed tool versions:"
  for tool in python3 pip3 git curl ansible; do
    echo -n " - $tool: "
    if command -v "$tool" >/dev/null; then
      echo -n "✅ "
      "$tool" --version 2>&1 | head -n1
    else
      echo "❌ Not installed"
    fi
  done

  echo "🗂️  Tool paths:"
  for tool in python3 pip3 git curl ansible; do
    echo " - $tool: $(command -v $tool || echo '❌ Not found')"
  done

  exit 0
fi

# ----------------------------
# Step 2: Validate target input
# ----------------------------
TARGET="${1:-}"
if [[ -z "$TARGET" || ! "$TARGET" =~ ^[a-zA-Z0-9._%-]+@[0-9a-zA-Z.-]+$ ]]; then
  echo "❌ Usage: $0 root@<server_ip or hostname>"
  exit 1
fi

# Extract user and server IP/host
SERVER_USER="$(echo "$TARGET" | cut -d@ -f1)"
SERVER_IP="$(echo "$TARGET" | cut -d@ -f2)"

echo "🔧 Bootstrapping server: $SERVER_IP with user '$USERNAME'"

# Clean specific fingerprint if exists
echo "🧹 Removing old SSH fingerprint for $SERVER_IP"
ssh-keygen -R "$SERVER_IP" >/dev/null 2>&1 || true

# Clean specific fingerprint if exists
echo "🧹 Removing old SSH fingerprint for $SERVER_IP"
ssh-keygen -R "$SERVER_IP" >/dev/null 2>&1 || true

# Ensure ~/.ssh and known_hosts are ready
mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
chmod 700 "$HOME/.ssh"
chmod 644 "$HOME/.ssh/known_hosts"

# Add fresh fingerprint
echo "📡 Scanning SSH fingerprint for trust..."
ssh-keyscan -H "$SERVER_IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null


# Add fresh fingerprint
echo "📡 Scanning SSH fingerprint for trust..."
ssh-keyscan -H "$SERVER_IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null


# ----------------------------
# Step 3: SSH key setup
# ----------------------------
# Generate a unique key filename to avoid collisions
while :; do
  RAND_SUFFIX="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8 || true)"
  KEY_ID="id_ed25519_$RAND_SUFFIX"
  KEY="$HOME/.ssh/$KEY_ID"
  [[ ! -f "$KEY" && ! -f "$KEY.pub" ]] && break
done

echo "🗝️  Generating SSH key: $KEY"
ssh-keygen -t ed25519 -f "$KEY" -N ""

# Start ssh-agent and add key
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$KEY" || true


# Remove any existing fingerprint (optional safety)
ssh-keygen -R "$SERVER_IP" 2>/dev/null || true

# Add new host key without hashing
ssh-keyscan "$SERVER_IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null

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
ssh "$TARGET" bash -s -- "$USERNAME" "$USER_PASSWORD" <<'EOF'
set -euo pipefail

USERNAME="$1"
USER_PASSWORD="$2"

# --- Create user if it doesn't exist ---
if ! id "$USERNAME" &>/dev/null; then
  echo "➕ Creating user: $USERNAME"
  useradd -m -s /bin/bash -G sudo "$USERNAME"
  echo "$USERNAME:$USER_PASSWORD" | chpasswd
else
  echo "⚠️  User $USERNAME already exists."
fi
passwd -S "$USERNAME"

echo "🔕 Cleaning shell init files to prevent SCP issues..."

# Disable output in non-interactive shells
BASHRC="/home/$USERNAME/.bashrc"
PROFILE="/home/$USERNAME/.profile"

touch "$BASHRC" "$PROFILE"
chown $USERNAME:$USERNAME "$BASHRC" "$PROFILE"

# Ensure NO echo, figlet, banner, printf, etc. run
sed -i '/^\s*echo/d' "$BASHRC"
sed -i '/^\s*printf/d' "$BASHRC"
sed -i '/^\s*figlet/d' "$BASHRC"
sed -i '/^\s*banner/d' "$BASHRC"

# Guard the entire file with: if interactive shell
sed -i '1i[[ $- != *i* ]] && return' "$BASHRC"

# Optional: remove global MOTD, if causing problems
rm -f /etc/update-motd.d/* /etc/motd /etc/profile.d/*-motd.sh 2>/dev/null || true

# Backup existing key (if any)
if [ -f /home/$USERNAME/.ssh/authorized_keys ]; then
  echo "📁 Backing up existing authorized_keys..."
  mv /home/$USERNAME/.ssh/authorized_keys /home/$USERNAME/.ssh/authorized_keys.bak
fi

# Overwrite with known-good key
echo "🔑 Installing new authorized_keys from root"
# Ensure .ssh directory exists and is not a file
if [ -f /home/$USERNAME/.ssh ]; then
  echo "⚠️  Found a file where .ssh directory should be. Removing it."
  rm -f /home/$USERNAME/.ssh
fi

mkdir -p /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh

cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys


echo "🛡️ Checking if it's safe to disable root SSH access..."

if id "$USERNAME" &>/dev/null && \
   getent passwd "$USERNAME" | grep -q '/home/' && \
   [ -f /home/$USERNAME/.ssh/authorized_keys ] && \
   [ -f /root/.ssh/authorized_keys ] && \
   grep -q 'ssh-' /home/$USERNAME/.ssh/authorized_keys && \
   cmp -s /home/$USERNAME/.ssh/authorized_keys /root/.ssh/authorized_keys && \
   [ "$(stat -c "%a" /home/$USERNAME/.ssh)" = "700" ] && \
   [ "$(stat -c "%a" /home/$USERNAME/.ssh/authorized_keys)" = "600" ]; then

  echo "✅ SSH key setup for $USERNAME is valid and secure."
  echo "🔒 Locking root password..."
  passwd -l root

  echo "🚫 Disabling PermitRootLogin in sshd_config..."
  if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  else
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  fi

  echo "🚫 Disabling PasswordAuthentication in sshd_config..."
  if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  else
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  fi

if [ -f /root/.ssh/authorized_keys ]; then
  echo "🧷 Backing up root's SSH key before deletion..."
  cp /root/.ssh/authorized_keys /root/.ssh/authorized_keys.bak
  chmod 600 /root/.ssh/authorized_keys.bak
  echo "🧹 Removing root's SSH key..."
  rm -f /root/.ssh/authorized_keys
else
  echo "ℹ️ No root SSH key found to delete."
fi

  echo "🔁 Restarting SSH service..."
  systemctl restart ssh

else
  echo "⚠️  Conditions for safe root SSH lockout not met. Skipping SSH hardening."
fi

echo "♻️ Skipping purge of system packages to avoid dependency conflicts on Ubuntu Noble."
echo "📦 Ensuring required packages are (re)installed..."

echo "🔄 Updating package index..."
apt update -y

echo "📦 Reinstalling required packages..."

apt install -y --no-install-recommends\
  software-properties-common \
  python3 \
  python3-pip \
  git \
  unzip \
  curl \
  sudo

echo "➕ Adding official Ansible PPA..."
add-apt-repository --yes --update ppa:ansible/ansible

echo "📦 Installing Ansible fresh from PPA..."
apt install -y ansible

echo "✅ Final tool versions:"
python3 --version
pip3 --version
git --version
curl --version
ansible --version | head -n1

echo "🧭 Verifying tool paths:"
for tool in python3 pip3 git curl ansible; do
  echo " - $tool: $(command -v $tool || echo 'Not found ❌')"
done


echo "📁 Preparing Ansible directory..."

echo "🧨 Clearing old content from /opt/ansible..."
rm -rf /opt/ansible/* || true  # Clear contents but keep the directory

echo "🔧 Ensuring /opt/ansible exists with correct ownership..."
mkdir -p /opt/ansible
chown -R $USERNAME:$USERNAME /opt/ansible
chmod -R 755 /opt/ansible


echo "🧪 Validating SSH configuration..."
sshd -t || { echo "❌ SSH config test failed! Not restarting."; exit 1; }
echo "🔁 Restarting SSH..."
systemctl restart ssh
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

echo "🧽 Removing .git folder to prevent SCP issues..."
rm -rf ansible-tmp/.git

# ----------------------------
# Step 7: Copy project to server
# ----------------------------

echo "📂 Copying project to server..."
if ! scp -r -o LogLevel=QUIET \
          -o UserKnownHostsFile=/dev/null \
          -o StrictHostKeyChecking=no \
          -o PreferredAuthentications=publickey \
          -o PubkeyAuthentication=yes \
          -o SendEnv=NONE \
          ansible-tmp/ "$USERNAME@$SERVER_IP:/opt/ansible/"; then
  echo "❌ SCP failed — check file permissions or SSH key setup"
  exit 1
fi

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

echo "🧾 Saving access credentials for backup..."

# Create secure credentials directory
CREDS_DIR="$HOME/server-creds"
mkdir -p "$CREDS_DIR"
chmod 700 "$CREDS_DIR"

# Filename
CREDS_FILE="$CREDS_DIR/server-access-${USERNAME}@${SERVER_IP}-$(date +%Y%m%d-%H%M).txt"

# Write credentials and note
{
  echo "🔐 SSH Access Info"
  echo "=================="
  echo "Username      : $USERNAME"
  echo "Server IP     : $SERVER_IP"
  echo "SSH Login     : ssh $USERNAME@$SERVER_IP"
  echo "Key Filename  : $KEY"
  echo ""
  echo "🗝️ Private Key Used:"
  echo "------------------"
  cat "$KEY"
  echo ""
  echo "📌 NOTE: Move this file to a secure, encrypted location after setup."
  echo "📄 Log file for this session:"
  echo "$LOGFILE"
} > "$CREDS_FILE"

chmod 600 "$CREDS_FILE"

echo ""
echo "✅ Credentials saved to: $CREDS_FILE"
echo ""
echo "⚠️  IMPORTANT: Please move this file to a secure location (e.g., encrypted USB, password vault, offline backup)."
echo ""
echo "📄 Log saved to: $LOGFILE"
echo "🏁 Bootstrap complete. Ansible is ready for: $USERNAME@$SERVER_IP"
