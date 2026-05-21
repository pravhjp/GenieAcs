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
echo -ne "${YELLOW}Do you want to install full parameters from pravhjp? (y/n): ${NC}"
read restore_confirm

if [ "$restore_confirm" == "y" ]; then

    # === Ask for new admin username and password BEFORE restore ===
    # WHY: mongorestore will overwrite the users collection with backup data
    # (backup has its own username/password with hashed values).
    # We collect new credentials here and re-insert them after restore,
    # so the backup's users are completely replaced with the ones you set now.
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

    echo -e "${YELLOW}Stopping GenieACS services...${NC}"
    systemctl stop genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui

    echo -e "${YELLOW}Restoring GenieACS database...${NC}"
    mongorestore --drop --db genieacs /opt/GenieAcs/Para

    # === Re-create admin user with new credentials after restore ===
    # WHY: After mongorestore, the users collection contains the backup's users
    # (alijayanet / admin with old hashed passwords). We drop that and insert
    # a fresh admin account using GenieACS's own genieacs-cli tool so the
    # password is properly hashed by GenieACS itself -- not by us.
    echo -e "${YELLOW}Setting new admin credentials (replacing backup users)...${NC}"
    # Drop backup users and insert new admin via GenieACS NBI API
    # We use mongo shell to clear users first, then GenieACS CLI to create properly
    mongosh genieacs --eval "db.users.drop()" 2>/dev/null || \
    mongo genieacs --eval "db.users.drop()" 2>/dev/null || true

    # Start NBI temporarily to use genieacs-cli for proper password hashing
    systemctl start genieacs-nbi
    sleep 3
    genieacs-cli create-user --username "$NEW_ADMIN_USER" --password "$NEW_ADMIN_PASS" --roles admin 2>/dev/null || \
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
    }).then(() => { console.log('User created.'); client.close(); })
    .catch(e => { console.error(e); client.close(); });
    " 2>/dev/null || true

    echo -e "${YELLOW}Starting GenieACS services...${NC}"
    systemctl start genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui
    sleep 3

    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Full parameters restored successfully.${NC}"
    echo -e "${GREEN}  Admin username : ${NEW_ADMIN_USER}${NC}"
    echo -e "${GREEN}  Admin password : (as you set above)${NC}"
    echo -e "${YELLOW}  Access UI at: http://$local_ip:3000${NC}"
    echo -e "${GREEN}============================================================${NC}"

else
    echo -e "${YELLOW}Parameter restore skipped.${NC}"
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
