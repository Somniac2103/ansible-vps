#!/bin/bash

# === CONFIGURABLE ===
SERVER="$1"
ANSIBLE_REPO="https://github.com/Somniac2103/ansible-vps.git"
TARGET_DIR="/opt/ansible-vps"
SSH_USER="root"

if [[ -z "$SERVER" ]]; then
  echo "Usage: $0 <user@ip>"
  exit 1
fi

echo "🔧 Bootstrapping server: $SERVER"

ssh "$SERVER" bash -s <<EOF
  echo "🛠 Updating system..."
  apt update && apt upgrade -y

  echo "📦 Installing core packages..."
  apt install -y git curl gnupg python3-pip python3-venv software-properties-common

  echo "🐍 Installing Ansible via pip..."
  pip3 install ansible

  echo "📁 Preparing project directory..."
  mkdir -p $TARGET_DIR
  cd /opt

  echo "📥 Cloning Ansible repository..."
  git clone $ANSIBLE_REPO $TARGET_DIR

  echo "📦 Installing Ansible Galaxy roles..."
  cd $TARGET_DIR
  ansible-galaxy install -r requirements.yml

  echo "🚀 Running Ansible playbook..."
  ansible-playbook site.yml
EOF
