#!/bin/bash

set -e

TARGET_USER="MEGAT"
BASE_DIR="/home/$TARGET_USER"
DOCKER_DIR="$BASE_DIR/docker"

NETWORK_NAME="service_net"
SUBNET="10.1.0.0/16"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== MEGAT SERVER DEPLOY V3 ===${NC}"

# =========================
# ROOT CHECK
# =========================

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Vui lòng chạy script bằng root${NC}"
  exit 1
fi

# =========================
# INPUT
# =========================

echo ""

read -p "Nhập domain chính (vd: pn.id.vn): " DOMAIN
read -p "Nhập Cloudflare Tunnel Token: " CF_TOKEN

if [ -z "$DOMAIN" ] || [ -z "$CF_TOKEN" ]; then
    echo -e "${RED}Lỗi: Domain và Token không được để trống!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Domain:${NC} $DOMAIN"

# =========================
# INSTALL DEPENDENCIES
# =========================

echo ""
echo -e "${GREEN}1. Đang cài Docker CE + Docker Compose Plugin...${NC}"

apt update

apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git

# =========================
# ADD DOCKER REPOSITORY
# =========================

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    chmod a+r /etc/apt/keyrings/docker.gpg
fi

if [ ! -f /etc/apt/sources.list.d/docker.list ]; then

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable
EOF

fi

apt update

# =========================
# INSTALL DOCKER
# =========================

if ! command -v docker &> /dev/null; then

    apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

fi

systemctl enable docker
systemctl start docker

# =========================
# CREATE USER
# =========================

echo ""
echo -e "${GREEN}2. Đang thiết lập người dùng $TARGET_USER...${NC}"

if ! id "$TARGET_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$TARGET_USER"
fi

usermod -aG docker "$TARGET_USER"

# =========================
# CREATE FOLDER STRUCTURE
# =========================

echo ""
echo -e "${GREEN}3. Đang tạo cấu trúc thư mục...${NC}"

mkdir -p "$DOCKER_DIR"

mkdir -p "$BASE_DIR/npm/data"
mkdir -p "$BASE_DIR/npm/letsencrypt"

mkdir -p "$BASE_DIR/portainer/data"

chown -R "$TARGET_USER:$TARGET_USER" "$BASE_DIR"

# =========================
# CREATE NETWORK
# =========================

echo ""
echo -e "${GREEN}4. Đang tạo Docker Network: $NETWORK_NAME...${NC}"

if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then

docker network create \
    --driver bridge \
    --subnet="$SUBNET" \
    "$NETWORK_NAME"

fi

# =========================
# CREATE COMPOSE FILE
# =========================

echo ""
echo -e "${GREEN}5. Đang tạo compose.yml...${NC}"

cat > "$DOCKER_DIR/compose.yml" <<EOF
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

chown "$TARGET_USER:$TARGET_USER" "$DOCKER_DIR/compose.yml"

# =========================
# START SERVICES
# =========================

echo ""
echo -e "${GREEN}6. Đang khởi chạy dịch vụ...${NC}"

cd "$DOCKER_DIR"

docker compose pull
docker compose --profile all up -d

# =========================
# DONE
# =========================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}     MEGAT SERVER ĐÃ SẴN SÀNG          ${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${YELLOW}Docker Version:${NC}"
docker --version

echo ""
echo -e "${YELLOW}Docker Compose Version:${NC}"
docker compose version

echo ""
echo -e "${YELLOW}Cloudflare Tunnel Setup:${NC}"

echo "1. Truy cập Cloudflare Zero Trust"
echo "2. Networks -> Tunnels"
echo "3. Chọn Tunnel của bạn"
echo "4. Vào Public Hostname"
echo ""
echo "Thêm cấu hình:"
echo ""
echo "Subdomain : npm"
echo "Domain    : $DOMAIN"
echo "Type      : HTTP"
echo "URL       : http://npm:81"
echo ""
echo "Sau đó truy cập:"
echo "https://npm.$DOMAIN"
echo ""
echo "Tài khoản mặc định NPM:"
echo "Email    : admin@example.com"
echo "Password : changeme"
echo ""
