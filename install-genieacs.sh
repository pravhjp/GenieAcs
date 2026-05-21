#!/bin/bash
set -e

# === Colors ===
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
local_ip=$(hostname -I | awk '{print $1}')

# === Banner ===
clear
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}        GenieACS Auto Installer - Ubuntu 22.04 LTS         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}Ubuntu $(lsb_release -d | cut -f2) | IP: ${local_ip}${NC}"
echo -e "${GREEN}============================================================${NC}"
sleep 2

# === Confirmation ===
echo -ne "${YELLOW}Continue GenieACS installation (fresh install Ubuntu 22.04)? (y/n): ${NC}"
read confirm
[ "$confirm" != "y" ] && echo -e "${RED}Cancelled.${NC}" && exit 1

# === Update & install dependencies ===
echo -e "${GREEN}[1/5] Updating system & installing dependencies...${NC}"
apt update -y && apt upgrade -y
apt install -y git curl gnupg apt-transport-https ca-certificates

# === Install Node.js 20 LTS ===
# FIXED: Node.js 18 is end-of-life. Using Node.js 20 (active LTS, supported until 2026)
echo -e "${GREEN}[2/5] Installing Node.js 20 LTS...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs build-essential

# === Install MongoDB 6.0 (for Ubuntu 22.04 Jammy) ===
# FIXED: Original script used MongoDB 4.4 with 'focal' repo -- not compatible with Ubuntu 22.04
# Changed to MongoDB 6.0 with 'jammy' repo which is correct for Ubuntu 22.04
echo -e "${GREEN}[3/5] Installing MongoDB 6.0 (compatible with Ubuntu 22.04 Jammy)...${NC}"
curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | \
    gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-6.0.list
apt update && apt install -y mongodb-org
systemctl enable --now mongod
sleep 2

# === Install GenieACS stable version ===
# FIXED: Pinned to v1.2.9 to avoid breaking changes from newer versions
echo -e "${GREEN}[4/5] Installing GenieACS v1.2.9 (stable)...${NC}"
npm install -g genieacs@1.2.9

# === Create user & directories ===
echo -e "${GREEN}[5/5] Creating GenieACS user & directories...${NC}"
useradd --system --no-create-home --user-group genieacs 2>/dev/null || true
mkdir -p /opt/genieacs/ext /var/log/genieacs
chown -R genieacs:genieacs /opt/genieacs /var/log/genieacs

# === Generate strong JWT Secret automatically ===
# FIXED: Original script used JWT_SECRET='secret' which is extremely weak
# Now auto-generated using openssl on every fresh install
JWT_SECRET=$(openssl rand -hex 32)

# === Environment file ===
cat << EOF > /opt/genieacs/genieacs.env
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_UI_JWT_SECRET=${JWT_SECRET}
GENIEACS_MONGODB_CONNECTION_URL=mongodb://127.0.0.1/genieacs
EOF
chown genieacs:genieacs /opt/genieacs/genieacs.env
chmod 600 /opt/genieacs/genieacs.env

# === Systemd services ===
echo -e "${GREEN}Creating systemd services...${NC}"
for svc in cwmp nbi fs ui; do
cat << EOF > /etc/systemd/system/genieacs-${svc}.service
[Unit]
Description=GenieACS ${svc^^}
After=network.target mongod.service

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-${svc}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
done

# === Enable & start all services ===
systemctl daemon-reload
systemctl enable --now genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui
sleep 3

# === Show installation success ===
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  GenieACS installation complete!${NC}"
echo -e "${YELLOW}  Access UI at: http://$local_ip:3000${NC}"
echo -e "${YELLOW}  JWT Secret saved at: /opt/genieacs/genieacs.env${NC}"
echo -e "${GREEN}============================================================${NC}"

# === OPTION: Restore full parameters ===
echo -ne "${YELLOW}Do you want to install the full parameters of pravhjp? (y/n): ${NC}"
read restore_confirm

if [ "$restore_confirm" == "y" ]; then
    echo -e "${GREEN}? Download and install full parameters...${NC}"
    cd /opt
    rm -rf /opt/genieacs-backup-full
    git clone https://github.com/pravhjp/GenieAcs.git

    echo -e "${YELLOW}?? Stopping the GenieACS service...${NC}"
    systemctl stop genieacs-{cwmp,nbi,fs,ui}

    echo -e "${YELLOW}?? Restoring the GenieACS database...${NC}"
    mongorestore --drop --db genieacs /opt/GenieAcs/Para

    echo -e "${YELLOW}?? Restarting the GenieACS service...${NC}"
    systemctl start genieacs-{cwmp,nbi,fs,ui}

    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}? Restore parameter full successfully installed.${NC}"
    echo -e "${YELLOW}Access the UI on: http://$local_ip:3000${NC}"
    echo -e "${GREEN}============================================================${NC}"
else
    echo -e "${YELLOW}?? Restore parameters skipped.${NC}"
    echo -e "${GREEN}============================================================${NC}"
fi
