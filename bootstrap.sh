#!/bin/bash

set -e

TARGET="$1"

if [ -z "$TARGET" ]; then
  echo "❌ Usage: $0 user@hostname"
  exit 1
fi

echo "🔧 Bootstrapping server: $TARGET"

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

  # Optional: create ansible user if you're not using root (skip if using root)
  # useradd -m -s /bin/bash ansible
  # echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible

  echo "📁 Creating directory for Ansible..."
  mkdir -p /opt/ansible
EOF

echo "📂 Copying Ansible project files to server..."
rsync -av --exclude='.git' --exclude='*.pyc' ./ "$TARGET:/opt/ansible"


echo "🚀 Bootstrap complete. You may now run Ansible playbooks from your local machine targeting $TARGET"
