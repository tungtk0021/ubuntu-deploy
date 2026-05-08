#!/bin/bash

set -e

TARGET_USER="MEGAT"
BASE_DIR="/home/$TARGET_USER"
DOCKER_DIR="$BASE_DIR/docker"

NETWORK_NAME="service_net"
SUBNET="10.1.0.0/16"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== MEGAT SERVER DEPLOY V2.1 ===${NC}"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo ""
read -p "Nhập domain chính (vd: pn.id.vn): " DOMAIN
read -p "Nhập Cloudflare Tunnel Token: " CF_TOKEN

if [ -z "$DOMAIN" ] || [ -z "$CF_TOKEN" ]; then
    echo -e "${YELLOW}Lỗi: Domain và Token không được để trống!${NC}"
    exit 1
fi

echo ""
echo "Domain: $DOMAIN"

# =========================
# INSTALL DOCKER
# =========================

echo -e "${GREEN}1. Đang cài đặt Docker và công cụ hỗ trợ...${NC}"

if ! command -v docker &> /dev/null; then
    apt update
    apt install -y docker.io docker-compose-v2 curl git
fi

systemctl enable docker
systemctl start docker

# =========================
# CREATE USER
# =========================

echo -e "${GREEN}2. Đang thiết lập người dùng $TARGET_USER...${NC}"

if ! id "$TARGET_USER" &>/dev/null; then
    useradd -m -s /bin/bash $TARGET_USER
fi

usermod -aG docker $TARGET_USER
usermod -aG sudo $TARGET_USER

# =========================
# CREATE FOLDER STRUCTURE
# =========================

echo -e "${GREEN}3. Đang tạo cấu trúc thư mục...${NC}"

mkdir -p $DOCKER_DIR
mkdir -p $BASE_DIR/npm/data
mkdir -p $BASE_DIR/npm/letsencrypt
mkdir -p $BASE_DIR/portainer/data

chown -R $TARGET_USER:$TARGET_USER $BASE_DIR

# =========================
# CREATE NETWORK
# =========================

echo -e "${GREEN}4. Đang tạo Docker Network: $NETWORK_NAME...${NC}"

if ! docker network ls | grep -q $NETWORK_NAME; then
docker network create \
--subnet=$SUBNET \
$NETWORK_NAME
fi

# =========================
# CREATE DOCKER COMPOSE
# =========================

echo -e "${GREEN}5. Đang tạo file cấu hình compose.yml...${NC}"

cat > $DOCKER_DIR/compose.yml <<EOF
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

networks:
  service_net:
    external: true
EOF

chown $TARGET_USER:$TARGET_USER $DOCKER_DIR/compose.yml

# =========================
# START STACK
# =========================

echo -e "${GREEN}6. Đang khởi chạy các dịch vụ...${NC}"

cd $DOCKER_DIR
docker compose --profile all up -d

echo ""
echo -e "${GREEN}=================================${NC}"
echo -e "${GREEN}MÁY CHỦ MEGAT ĐÃ SẴN SÀNG${NC}"
echo -e "${GREEN}=================================${NC}"

echo ""
echo -e "${YELLOW}LƯU Ý QUAN TRỌNG TRÊN CLOUDFLARE DASHBOARD:${NC}"
echo "1. Truy cập Cloudflare Zero Trust -> Networks -> Connectors"
echo "2. Chọn tab Cloudflare Tunnels -> Configure -> Public Hostname"
echo "3. Thêm hostname mới:"
echo "   - Subdomain: npm"
echo "   - Domain: $DOMAIN"
echo "   - Service Type: HTTP"
echo "   - URL: npm:81 (Để vào trang quản trị NPM)"
echo ""
echo "Sau khi xong, bạn có thể truy cập NPM tại: http://npm.$DOMAIN"
echo "Tài khoản mặc định NPM: admin@example.com / changeme"
echo ""
