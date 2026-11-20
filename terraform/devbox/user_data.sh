#!/bin/bash
# Runs once, as root, on first boot. Log: /var/log/cloud-init-output.log
set -euxo pipefail

apt-get update -y
apt-get install -y ca-certificates curl git unzip jq openssl

# AWS CLI v2 (scripts read/write secrets in SSM Parameter Store)
snap install aws-cli --classic

# Docker Engine + compose plugin (official convenience script)
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable --now docker

# Node.js 22 LTS (for Medusa later)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# 4 GB swap as a safety net for Medusa builds (lesson learned from the sandbox OOM)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "DEVBOX READY" > /var/tmp/devbox-ready
