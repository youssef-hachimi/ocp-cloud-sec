#!/bin/bash
###############################################################################
# HASHICORP VAULT - PAM INSTALLATION & CONFIGURATION
# Cloud Security Project - Phase 4
#
# This script installs and configures HashiCorp Vault for:
#   - Secret storage (KV v2 engine)
#   - Dynamic database credentials (MySQL)
#   - AppRole authentication for OCP application
#
# Prerequisites:
#   - Ubuntu 22.04 server (can be the Wazuh server or separate VM)
#   - 2GB RAM minimum, 4GB recommended
#   - MySQL/Azure Database accessible from this server
#
# Usage:
#   sudo ./install-vault.sh
###############################################################################

set -e

VAULT_VERSION="1.15.6"
VAULT_USER="vault"
VAULT_DIR="/opt/vault"
VAULT_CONFIG_DIR="/etc/vault.d"
VAULT_DATA_DIR="/opt/vault/data"
DOMAIN="yourdomain.com"  # CHANGE THIS

echo "========================================================================"
echo "  HASHICORP VAULT - PAM INSTALLATION"
echo "  Cloud Security Project - Phase 4"
echo "========================================================================"

# =============================================================================
# STEP 1: Install Vault
# =============================================================================
echo ""
echo "[Step 1/8] Installing HashiCorp Vault v${VAULT_VERSION}..."

apt-get update -qq
apt-get install -y -qq curl unzip jq

# Download and install Vault
cd /tmp
curl -sLo vault.zip "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
unzip -q vault.zip
mv vault /usr/local/bin/
chmod +x /usr/local/bin/vault
rm -f vault.zip

echo "  Vault installed: $(vault version)"

# =============================================================================
# STEP 2: Create Vault User and Directories
# =============================================================================
echo ""
echo "[Step 2/8] Creating Vault user and directories..."

useradd --system --home "$VAULT_DIR" --shell /bin/false "$VAULT_USER" 2>/dev/null || true

mkdir -p "$VAULT_CONFIG_DIR" "$VAULT_DATA_DIR" "$VAULT_DIR/tls"
chown -R "$VAULT_USER:$VAULT_USER" "$VAULT_DIR"
chmod 750 "$VAULT_DATA_DIR"

# =============================================================================
# STEP 3: Generate TLS Certificates
# =============================================================================
echo ""
echo "[Step 3/8] Generating TLS certificates..."

cd "$VAULT_DIR/tls"

# Generate private key and self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout vault.key -out vault.crt \
    -subj "/C=US/ST=State/L=City/O=CloudSecurityProject/CN=vault.${DOMAIN}" \
    -addext "subjectAltName=DNS:vault.${DOMAIN},DNS:localhost,IP:127.0.0.1"

chown "$VAULT_USER:$VAULT_USER" vault.key vault.crt
chmod 600 vault.key
chmod 644 vault.crt

echo "  TLS certificates generated"

# =============================================================================
# STEP 4: Vault Configuration
# =============================================================================
echo ""
echo "[Step 4/8] Creating Vault configuration..."

SERVER_IP=$(curl -s ifconfig.me)

cat > "$VAULT_CONFIG_DIR/vault.hcl" <<EOF
# Vault Configuration - Cloud Security Project
ui = true
api_addr = "https://vault.${DOMAIN}:8200"
cluster_addr = "https://vault.${DOMAIN}:8201"

# Storage backend (file-based for simplicity)
storage "file" {
  path = "${VAULT_DATA_DIR}"
}

# Listener configuration
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "${VAULT_DIR}/tls/vault.crt"
  tls_key_file  = "${VAULT_DIR}/tls/vault.key"
  
  # CORS for dashboard access (restrict in production)
  cors_enabled = true
  cors_allowed_origins = ["https://vault.${DOMAIN}"]
}

# Telemetry (optional)
telemetry {
  disable_hostname = true
  prometheus_retention_time = "30s"
}

# Enable audit logging
EOF

chown "$VAULT_USER:$VAULT_USER" "$VAULT_CONFIG_DIR/vault.hcl"
chmod 640 "$VAULT_CONFIG_DIR/vault.hcl"

echo "  Configuration created"

# =============================================================================
# STEP 5: Systemd Service
# =============================================================================
echo ""
echo "[Step 5/8] Creating systemd service..."

cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=${VAULT_CONFIG_DIR}/vault.hcl

[Service]
User=${VAULT_USER}
Group=${VAULT_USER}
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=${VAULT_CONFIG_DIR}/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vault

echo "  Service created and enabled"

# =============================================================================
# STEP 6: Start Vault and Initialize
# =============================================================================
echo ""
echo "[Step 6/8] Starting Vault and initializing..."

systemctl start vault
sleep 3

# Set environment variable
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="${VAULT_DIR}/tls/vault.crt"

# Wait for Vault to be ready
echo "  Waiting for Vault to start..."
for i in {1..30}; do
    if vault status 2>/dev/null; then
        break
    fi
    echo -n "."
    sleep 1
done

# Check if already initialized
if vault status 2>&1 | grep -q "Initialized.*true"; then
    echo ""
    echo "  Vault is already initialized!"
else
    echo ""
    echo "  Initializing Vault..."
    
    vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > /tmp/vault-init.json
    
    echo ""
    echo "  === VAULT INITIALIZED ==="
    echo "  *** SAVE THESE VALUES SECURELY ***"
    echo ""
    echo "  Unseal Keys:"
    jq -r '.unseal_keys_b64[]' /tmp/vault-init.json | nl
    echo ""
    echo "  Root Token:"
    jq -r '.root_token' /tmp/vault-init.json
    echo ""
    
    # Save to file with restricted permissions
    cp /tmp/vault-init.json "${VAULT_DIR}/vault-init-backup.json"
    chmod 600 "${VAULT_DIR}/vault-init-backup.json"
    
    echo "  Backup saved to: ${VAULT_DIR}/vault-init-backup.json"
fi

# =============================================================================
# STEP 7: Configure Vault (Secrets Engine, Auth, Policies)
# =============================================================================
echo ""
echo "[Step 7/8] Configuring Vault..."

echo ""
echo "  Please provide the Vault root token to continue configuration:"
read -s -p "Root Token: " ROOT_TOKEN
echo ""

export VAULT_TOKEN="$ROOT_TOKEN"

# Unseal if needed
SEALED=$(vault status -format=json 2>/dev/null | jq -r '.sealed')
if [ "$SEALED" == "true" ]; then
    echo "  Vault is sealed. Please provide 3 unseal keys:"
    for i in 1 2 3; do
        read -s -p "Unseal Key $i: " UNSEAL_KEY
        vault operator unseal "$UNSEAL_KEY" > /dev/null
        echo ""
    done
fi

echo "  Enabling KV secrets engine v2..."
vault secrets enable -path=secret -version=2 kv 2>/dev/null || echo "    KV engine already enabled"

echo "  Enabling AppRole auth method..."
vault auth enable approle 2>/dev/null || echo "    AppRole already enabled"

echo "  Creating OCP policy..."
vault policy write ocp-app - <<EOFPOLICY
# OCP Application Policy
path "secret/data/ocp/*" {
  capabilities = ["read", "list"]
}

path "secret/data/ocp/database" {
  capabilities = ["read"]
}

path "database/creds/ocp-app" {
  capabilities = ["read"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}
EOFPOLICY

echo "  Creating admin policy..."
vault policy write admin - <<EOFPOLICY
# Admin Policy - Full Access
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOFPOLICY

echo "  Creating OCP AppRole..."
vault write auth/approle/role/ocp-app \
    token_policies="ocp-app" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=24h \
    secret_id_num_uses=100

echo "  Reading AppRole credentials..."
vault read -format=json auth/approle/role/ocp-app/role-id > "${VAULT_DIR}/ocp-approle.json"
ROLE_ID=$(vault read -field=role_id auth/approle/role/ocp-app/role-id)
vault write -f -format=json auth/approle/role/ocp-app/secret-id >> "${VAULT_DIR}/ocp-approle.json"
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/ocp-app/secret-id)

echo ""
echo "  === APPROLE CREDENTIALS ==="
echo "  Role ID:    $ROLE_ID"
echo "  Secret ID:  $SECRET_ID"
echo ""

echo "  Storing sample secret..."
vault kv put secret/ocp/database \
    host="$(grep DB_HOST /tmp/db-env.txt 2>/dev/null || echo 'localhost')" \
    port="3306" \
    db_name="ocp_db" \
    username="ocp_app" \
    password="$(openssl rand -base64 24)" \
    description="OCP Application Database Credentials"

echo "  Configuration complete!"

# =============================================================================
# STEP 8: Configure Database Secrets Engine (Optional - Advanced)
# =============================================================================
echo ""
echo "[Step 8/8] Configuring Database Secrets Engine (Optional)..."

read -p "Enable dynamic MySQL credentials? (yes/no): " ENABLE_DB
if [ "$ENABLE_DB" == "yes" ]; then
    echo "  Enabling database secrets engine..."
    vault secrets enable database 2>/dev/null || echo "    Already enabled"
    
    read -p "Enter MySQL admin username: " MYSQL_ADMIN
    read -s -p "Enter MySQL admin password: " MYSQL_PASS
    echo ""
    read -p "Enter MySQL host: " MYSQL_HOST
    
    echo "  Configuring MySQL connection..."
    vault write database/config/ocp-mysql \
        plugin_name=mysql-database-plugin \
        allowed_roles="ocp-app" \
        connection_url="{{username}}:{{password}}@tcp(${MYSQL_HOST}:3306)/" \
        username="$MYSQL_ADMIN" \
        password="$MYSQL_PASS" \
        max_open_connections=10 \
        max_connection_lifetime="1h"
    
    echo "  Creating dynamic credential role..."
    vault write database/roles/ocp-app \
        db_name=ocp-mysql \
        creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT,INSERT,UPDATE,DELETE ON ocp_db.* TO '{{name}}'@'%';" \
        default_ttl="1h" \
        max_ttl="24h"
    
    echo "  Testing dynamic credentials..."
    vault read database/creds/ocp-app
    
    echo "  Dynamic database credentials configured!"
fi

# =============================================================================
# COMPLETE
# =============================================================================
echo ""
echo "========================================================================"
echo "  VAULT INSTALLATION COMPLETE!"
echo ""
echo "  Vault UI:    https://vault.${DOMAIN}:8200"
echo "  API:         https://vault.${DOMAIN}:8200/v1/"
echo ""
echo "  CREDENTIALS SAVED TO:"
echo "    Root token backup: ${VAULT_DIR}/vault-init-backup.json"
echo "    AppRole creds:     ${VAULT_DIR}/ocp-approle.json"
echo ""
echo "  NEXT STEPS:"
echo "  1. Setup DNS A record: vault.${DOMAIN} -> $(curl -s ifconfig.me)"
echo "  2. Configure firewall: ufw allow 8200/tcp"
echo "  3. Update OCP app with VAULT_ENABLED=true"
echo "  4. Test integration: curl -X POST \$VAULT_ADDR/v1/auth/approle/login"
echo ""
echo "  IMPORTANT: Store unseal keys and root token securely!"
echo "  They are required to unseal Vault after restart."
echo "========================================================================"
