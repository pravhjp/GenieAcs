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

# === Check if ports are already in use ===
echo -e "${GREEN}Checking if required ports are available...${NC}"
for port in 7547 7557 3000; do
    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}Port $port is already in use. Please free up port $port and try again.${NC}"
        exit 1
    fi
done
echo -e "${GREEN}All required ports are available.${NC}"

# === Update & install dependencies ===
echo -e "${GREEN}[1/5] Updating system & installing dependencies...${NC}"
apt update -y && apt upgrade -y
apt install -y git curl gnupg apt-transport-https ca-certificates

# === Install Node.js 20 LTS ===
echo -e "${GREEN}[2/5] Installing Node.js 20 LTS...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs build-essential

# === Install MongoDB 6.0 (for Ubuntu 22.04 Jammy) ===
echo -e "${GREEN}[3/5] Installing MongoDB 6.0 (compatible with Ubuntu 22.04 Jammy)...${NC}"
curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | \
    gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-6.0.list
apt update && apt install -y mongodb-org
systemctl enable --now mongod
sleep 2

# === Install GenieACS stable version ===
echo -e "${GREEN}[4/5] Installing GenieACS v1.2.16 (stable)...${NC}"
npm install -g genieacs@1.2.16

# === Create user & directories ===
echo -e "${GREEN}[5/5] Creating GenieACS user & directories...${NC}"
useradd --system --no-create-home --user-group genieacs 2>/dev/null || true
mkdir -p /opt/genieacs/ext /var/log/genieacs
chown -R genieacs:genieacs /opt/genieacs /var/log/genieacs

# === Generate strong JWT Secret automatically ===
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
echo -e "${YELLOW}  Default ACS URL: http://$local_ip:7547${NC}"
echo -e "${YELLOW}  NBI URL: http://$local_ip:7557${NC}"
echo -e "${YELLOW}  Logs: /var/log/genieacs/${NC}"
echo -e "${YELLOW}  JWT Secret saved at: /opt/genieacs/genieacs.env${NC}"
echo -e "${GREEN}============================================================${NC}"

# === OPTION: Restore full parameters ===
echo -ne "${YELLOW}Do you want to install full parameters from pravhjp? (y/n): ${NC}"
read restore_confirm

if [ "$restore_confirm" == "y" ]; then

    # === Ask for new admin username and password BEFORE restore ===
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${YELLOW}  Set your GenieACS admin login credentials${NC}"
    echo -e "${YELLOW}  These will REPLACE the users from the backup file${NC}"
    echo -e "${GREEN}============================================================${NC}"

    echo -ne "${YELLOW}Enter new admin username: ${NC}"
    read NEW_ADMIN_USER
    while true; do
        echo -ne "${YELLOW}Enter new admin password: ${NC}"
        read -s NEW_ADMIN_PASS
        echo
        echo -ne "${YELLOW}Confirm admin password: ${NC}"
        read -s NEW_ADMIN_PASS2
        echo
        if [ "$NEW_ADMIN_PASS" == "$NEW_ADMIN_PASS2" ]; then
            break
        else
            echo -e "${RED}Passwords do not match. Try again.${NC}"
        fi
    done

    echo -e "${GREEN}Downloading and installing full parameters...${NC}"
    cd /opt
    rm -rf /opt/GenieAcs
    git clone https://github.com/pravhjp/GenieAcs.git

    # Check if backup directory exists
    if [ ! -d "/opt/GenieAcs/acs" ]; then
        echo -e "${RED}Backup directory '/opt/GenieAcs/acs' not found. Restore failed.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Stopping GenieACS services...${NC}"
    systemctl stop genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui

    echo -e "${YELLOW}Restoring GenieACS database...${NC}"
    mongorestore --drop --db genieacs /opt/GenieAcs/acs || {
        echo -e "${RED}Failed to restore database${NC}"
        exit 1
    }

    # === Re-create admin user with new credentials after restore ===
    echo -e "${YELLOW}Setting new admin credentials (replacing backup users)...${NC}"
    
    # Drop backup users
    mongosh genieacs --eval "db.users.drop()" 2>/dev/null || \
    mongo genieacs --eval "db.users.drop()" 2>/dev/null || true

    # Start NBI temporarily to use genieacs-cli for proper password hashing
    systemctl start genieacs-nbi
    sleep 3
    
    # Try to create user using genieacs-cli first
    if genieacs-cli create-user --username "$NEW_ADMIN_USER" --password "$NEW_ADMIN_PASS" --roles admin 2>/dev/null; then
        echo -e "${GREEN}Admin user created successfully using genieacs-cli${NC}"
    else
        # Fallback to Node.js script if genieacs-cli fails
        echo -e "${YELLOW}Falling back to Node.js method for user creation...${NC}"
        node -e "
        const crypto = require('crypto');
        const salt = crypto.randomBytes(64).toString('hex');
        const hash = crypto.scryptSync('$NEW_ADMIN_PASS', salt, 64).toString('hex') +
                     crypto.createHash('sha512').update('$NEW_ADMIN_PASS' + salt).digest('hex');
        const { MongoClient } = require('mongodb');
        const client = new MongoClient('mongodb://127.0.0.1/genieacs');
        client.connect().then(() => {
            return client.db().collection('users').insertOne({
                _id: '$NEW_ADMIN_USER',
                roles: 'admin',
                password: hash,
                salt: salt
            });
        }).then(() => { console.log('User created successfully.'); client.close(); })
        .catch(e => { console.error('Error creating user:', e); client.close(); });
        " 2>/dev/null || echo -e "${RED}Failed to create admin user${RED}"
    fi

    echo -e "${YELLOW}Starting GenieACS services...${NC}"
    systemctl start genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui
    sleep 3

    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Full parameters restored successfully.${NC}"
    echo -e "${GREEN}  Admin username : ${NEW_ADMIN_USER}${NC}"
    echo -e "${GREEN}  Admin password : (as you set above)${NC}"
    echo -e "${YELLOW}  Access UI at: http://$local_ip:3000${NC}"
    echo -e "${YELLOW}  Default ACS URL: http://$local_ip:7547${NC}"
    echo -e "${YELLOW}  NBI URL: http://$local_ip:7557${NC}"
    echo -e "${YELLOW}  Logs: /var/log/genieacs/${NC}"
    echo -e "${GREEN}============================================================${NC}"

else
    echo -e "${YELLOW}Parameter restore skipped.${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${YELLOW}  Access UI at: http://$local_ip:3000${NC}"
    echo -e "${YELLOW}  Default ACS URL: http://$local_ip:7547${NC}"
    echo -e "${YELLOW}  NBI URL: http://$local_ip:7557${NC}"
    echo -e "${YELLOW}  Logs: /var/log/genieacs/${NC}"
    echo -e "${GREEN}============================================================${NC}"
fi

# === Check status of all services ===
echo -e "${GREEN}GenieACS service status:${NC}"
for svc in cwmp nbi fs ui; do
    STATUS=$(systemctl is-active genieacs-${svc} 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        echo -e "  genieacs-${svc}: ${GREEN}RUNNING${NC}"
    else
        echo -e "  genieacs-${svc}: ${RED}${STATUS}${NC}"
    fi
done
echo -e "${GREEN}============================================================${NC}"
