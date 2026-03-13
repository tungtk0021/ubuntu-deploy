#!/bin/bash

set -e

TARGET_USER="MEGAT"
BASE_DIR="/home/$TARGET_USER"
DOCKER_DIR="$BASE_DIR/docker"

NETWORK_NAME="service_net"
SUBNET="10.1.0.0/16"

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}=== MEGAT SERVER DEPLOY V2 ===${NC}"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

echo ""
read -p "Nhập domain chính (vd: pn.id.vn): " DOMAIN
read -p "Nhập Cloudflare Tunnel Token: " CF_TOKEN

echo ""
echo "Domain: $DOMAIN"

# =========================
# INSTALL DOCKER
# =========================

echo -e "${GREEN}Installing Docker${NC}"

if ! command -v docker &> /dev/null; then
    apt update
    apt install -y docker.io docker-compose-v2 curl git
fi

systemctl enable docker
systemctl start docker

# =========================
# CREATE USER
# =========================

if ! id "$TARGET_USER" &>/dev/null; then
    useradd -m -s /bin/bash $TARGET_USER
fi

usermod -aG docker $TARGET_USER
usermod -aG sudo $TARGET_USER

# =========================
# CREATE FOLDER STRUCTURE
# =========================

mkdir -p $BASE_DIR/docker
mkdir -p $BASE_DIR/npm/data
mkdir -p $BASE_DIR/npm/letsencrypt
mkdir -p $BASE_DIR/portainer/data
mkdir -p $BASE_DIR/cloudflared

chown -R $TARGET_USER:$TARGET_USER $BASE_DIR

# =========================
# CREATE NETWORK
# =========================

if ! docker network ls | grep -q $NETWORK_NAME; then
docker network create \
--subnet=$SUBNET \
$NETWORK_NAME
fi

# =========================
# CREATE DOCKER COMPOSE
# =========================

cat > $DOCKER_DIR/compose.yml <<EOF
version: "3.9"

networks:
  service_net:
    external: true

services:

  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    profiles:
      - npm
      - all
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - $BASE_DIR/npm/data:/data
      - $BASE_DIR/npm/letsencrypt:/etc/letsencrypt
    networks:
      service_net:
        ipv4_address: 10.1.1.10

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    profiles:
      - portainer
      - all
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $BASE_DIR/portainer/data:/data
    networks:
      service_net:
        ipv4_address: 10.1.1.11

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    profiles:
      - tunnel
      - all
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=$CF_TOKEN
    networks:
      service_net:
        ipv4_address: 10.1.1.12

EOF

chown $TARGET_USER:$TARGET_USER $DOCKER_DIR/compose.yml

# =========================
# START STACK
# =========================

cd $DOCKER_DIR
docker compose --profile all up -d

echo ""
echo -e "${GREEN}=================================${NC}"
echo -e "${GREEN}MEGAT SERVER READY${NC}"
echo -e "${GREEN}=================================${NC}"

echo ""
echo "Nginx Proxy Manager:"
echo "http://SERVER-IP:81"

echo ""
echo "Portainer:"
echo "https://SERVER-IP:9443"

echo ""
echo "Cloudflare Tunnel đã chạy."
echo ""
echo "Tạo DNS trên Cloudflare:"
echo ""
echo "*.$DOMAIN -> tunnel"
