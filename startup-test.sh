#!/bin/bash
# TEST STARTUP
# Run once on a fresh Ubuntu droplet as root.
set -e

DEPLOY_USER="deploy"
REPO_DIR="/home/${DEPLOY_USER}/houseforce-infra"

if [ "$(swapon --show | wc -l)" -le 1 ]; then
  echo "Setting up 2GB swap space..."
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile 2>/dev/null || true
  swapon /swapfile 2>/dev/null || true
  if ! grep -q '/swapfile' /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
  sysctl vm.swappiness=10
  if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then echo 'vm.swappiness=10' >> /etc/sysctl.conf; fi
fi

if ! command -v docker &> /dev/null; then
  apt-get update -y
  apt-get install -y docker.io docker-compose-v2
  systemctl enable docker
  systemctl start docker
fi

if ! id "$DEPLOY_USER" &>/dev/null; then useradd -m -s /bin/bash "$DEPLOY_USER"; fi
usermod -aG docker "$DEPLOY_USER"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$CURRENT_DIR" != "$REPO_DIR" ]; then
  mkdir -p "$REPO_DIR"
  cp -a "$CURRENT_DIR/." "$REPO_DIR/"
fi
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$REPO_DIR"

DEPLOY_SSH="/home/${DEPLOY_USER}/.ssh"
mkdir -p "$DEPLOY_SSH"
if [ -f /root/.ssh/authorized_keys ]; then
  cp /root/.ssh/authorized_keys "$DEPLOY_SSH/authorized_keys"
elif [ -n "$SUDO_USER" ] && [ -f "/home/${SUDO_USER}/.ssh/authorized_keys" ]; then
  cp "/home/${SUDO_USER}/.ssh/authorized_keys" "$DEPLOY_SSH/authorized_keys"
fi
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$DEPLOY_SSH"
chmod 700 "$DEPLOY_SSH"
chmod 600 "$DEPLOY_SSH/authorized_keys" 2>/dev/null || true

if [ ! -f "${REPO_DIR}/.env" ]; then
  echo "=== Test Environment Setup ==="
  read -p "Enter GitHub username: " GITHUB_OWNER
  read -s -p "Enter GitHub PAT (read:packages) for Watchtower: " GITHUB_TOKEN; echo
  read -p "Enter Test Domain [test.houseforce.es]: " DOMAIN; DOMAIN=${DOMAIN:-test.houseforce.es}
  read -p "Enter Let's Encrypt Email (for SSL certs): " ACME_EMAIL
  read -s -p "Enter password for Traefik dashboard (user: admin): " TRAEFIK_PASSWORD; echo
  
  TRAEFIK_HASH=$(docker run --rm httpd:alpine htpasswd -bnBC 10 admin "${TRAEFIK_PASSWORD}" | sed -e 's/\$/\$\$/g')
  WATCHTOWER_TOKEN=$(openssl rand -hex 32)
  
  echo "Generating Houseforce secure keys..."
  HOUSEFORCE_STRAPI_APP_KEYS="$(openssl rand -base64 16),$(openssl rand -base64 16)"
  HOUSEFORCE_STRAPI_API_TOKEN_SALT=$(openssl rand -base64 16)
  HOUSEFORCE_STRAPI_ADMIN_JWT_SECRET=$(openssl rand -base64 16)
  HOUSEFORCE_STRAPI_TRANSFER_TOKEN_SALT=$(openssl rand -base64 16)
  HOUSEFORCE_STRAPI_JWT_SECRET=$(openssl rand -base64 16)
  HOUSEFORCE_NEXTAUTH_SECRET=$(openssl rand -base64 32)

  echo "Generating Test Database credentials..."
  DATABASE_NAME="strapi_$(openssl rand -hex 4)"
  DATABASE_USERNAME="strapi_$(openssl rand -hex 4)"
  DATABASE_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')
  
  echo "=== Google SSO Configuration ==="
  read -p "Enter Google Client ID (Test): " GOOGLE_CLIENT_ID
  read -s -p "Enter Google Client Secret (Test): " GOOGLE_CLIENT_SECRET; echo
  
  cat <<EOF > "${REPO_DIR}/.env"
GITHUB_OWNER=${GITHUB_OWNER}
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
TRAEFIK_DASHBOARD_AUTH=${TRAEFIK_HASH}
WATCHTOWER_TOKEN=${WATCHTOWER_TOKEN}

HOUSEFORCE_STRAPI_APP_KEYS=${HOUSEFORCE_STRAPI_APP_KEYS}
HOUSEFORCE_STRAPI_API_TOKEN_SALT=${HOUSEFORCE_STRAPI_API_TOKEN_SALT}
HOUSEFORCE_STRAPI_ADMIN_JWT_SECRET=${HOUSEFORCE_STRAPI_ADMIN_JWT_SECRET}
HOUSEFORCE_STRAPI_TRANSFER_TOKEN_SALT=${HOUSEFORCE_STRAPI_TRANSFER_TOKEN_SALT}
HOUSEFORCE_STRAPI_JWT_SECRET=${HOUSEFORCE_STRAPI_JWT_SECRET}
NEXTAUTH_SECRET=${HOUSEFORCE_NEXTAUTH_SECRET}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}

DATABASE_NAME=${DATABASE_NAME}
DATABASE_USERNAME=${DATABASE_USERNAME}
DATABASE_PASSWORD=${DATABASE_PASSWORD}
EOF
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "${REPO_DIR}/.env"
  chmod 600 "${REPO_DIR}/.env"
else
  source "${REPO_DIR}/.env"
  read -s -p "Enter GitHub PAT to login Watchtower (or press enter to skip): " GITHUB_TOKEN; echo
fi

mkdir -p "${REPO_DIR}/traefik"
touch "${REPO_DIR}/traefik/acme.json"
chmod 600 "${REPO_DIR}/traefik/acme.json"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${REPO_DIR}/traefik"

su - "$DEPLOY_USER" -c "mkdir -p ~/.docker && if [ ! -f ~/.docker/config.json ]; then echo '{}' > ~/.docker/config.json; fi"
if [ -n "$GITHUB_TOKEN" ]; then
  su - "$DEPLOY_USER" -c "echo '${GITHUB_TOKEN}' | docker login ghcr.io -u '${GITHUB_OWNER}' --password-stdin"
fi

# Test deployment injects the test override file
su - "$DEPLOY_USER" -c "cd ${REPO_DIR} && docker compose pull && docker compose -f docker-compose.yml -f docker-compose.test.yml up -d"
su - "$DEPLOY_USER" -c "docker image prune -af"

echo "Test Setup Complete!"
