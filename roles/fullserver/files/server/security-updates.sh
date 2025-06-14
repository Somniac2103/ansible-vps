#!/bin/bash
echo "🔐 Running security updates at $(date)"
sudo apt update && sudo apt upgrade -y
