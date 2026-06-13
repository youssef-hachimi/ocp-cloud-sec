#!/bin/bash
###############################################################################
# OCP Web Application - Azure Deployment Script
# Cloud Security Project - Phase 2
#
# Prerequisites:
#   - Azure CLI installed and logged in: az login
#   - Active Azure subscription
#   - Custom domain ready (Phase 3)
#
# Usage:
#   chmod +x azure-deploy.sh
#   ./azure-deploy.sh
###############################################################################

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================
RESOURCE_GROUP="rg-ocp-security-project"
LOCATION="eastus"                    # Change to your preferred region
APP_NAME="ocp-app-$(date +%s)"     # Unique app name
APP_SERVICE_PLAN="asp-ocp-project"
DB_SERVER="ocp-mysql-$(date +%s)"
DB_NAME="ocp_db"
DB_USER="ocp_admin"
DB_PASSWORD="$(openssl rand -base64 32)"  # Auto-generated strong password
SKU="B1"                             # Basic tier (change to P1V2 for production)
PHP_VERSION="8.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================================================"
echo "  OCP Web App - Azure Deployment"
echo "========================================================================"
echo ""

# =============================================================================
# STEP 1: Validate Prerequisites
# =============================================================================
echo -e "${YELLOW}[Step 1/8] Validating prerequisites...${NC}"

if ! command -v az &> /dev/null; then
    echo -e "${RED}ERROR: Azure CLI not found. Install from https://aka.ms/installazurecli${NC}"
    exit 1
fi

if ! az account show &> /dev/null; then
    echo -e "${RED}ERROR: Not logged into Azure. Run: az login${NC}"
    exit 1
fi

SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "${GREEN}  Connected to subscription: $SUBSCRIPTION_NAME${NC}"

# =============================================================================
# STEP 2: Create Resource Group
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 2/8] Creating resource group...${NC}"

az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags project="cloud-security" environment="production" managedBy="cli" \
    --output none

echo -e "${GREEN}  Resource group created: $RESOURCE_GROUP${NC}"

# =============================================================================
# STEP 3: Create Azure Database for MySQL (Flexible Server)
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 3/8] Creating Azure Database for MySQL...${NC}"

az mysql flexible-server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DB_SERVER" \
    --location "$LOCATION" \
    --admin-user "$DB_USER" \
    --admin-password "$DB_PASSWORD" \
    --sku-name "Standard_B1s" \
    --tier "Burstable" \
    --storage-size 32 \
    --version "8.0.21" \
    --public-access "0.0.0.0" \
    --database-name "$DB_NAME" \
    --yes \
    --output none

# Get database FQDN
DB_FQDN=$(az mysql flexible-server show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DB_SERVER" \
    --query fullyQualifiedDomainName -o tsv)

echo -e "${GREEN}  MySQL server created: $DB_FQDN${NC}"
echo -e "${YELLOW}  Database password saved to: ./db-credentials.txt${NC}"

# Save credentials
cat > db-credentials.txt << EOF
=== OCP Database Credentials ===
Server: $DB_FQDN
Database: $DB_NAME
Username: $DB_USER
Password: $DB_PASSWORD
=== KEEP THIS FILE SECURE ===
EOF
chmod 600 db-credentials.txt

# =============================================================================
# STEP 4: Create App Service Plan
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 4/8] Creating App Service Plan...${NC}"

az appservice plan create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_SERVICE_PLAN" \
    --location "$LOCATION" \
    --sku "$SKU" \
    --is-linux \
    --output none

echo -e "${GREEN}  App Service Plan created: $APP_SERVICE_PLAN${NC}"

# =============================================================================
# STEP 5: Create Web App
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 5/8] Creating Web App...${NC}"

az webapp create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --plan "$APP_SERVICE_PLAN" \
    --runtime "PHP|$PHP_VERSION" \
    --output none

echo -e "${GREEN}  Web App created: $APP_NAME${NC}"
echo -e "${GREEN}  Default URL: https://$APP_NAME.azurewebsites.net${NC}"

# =============================================================================
# STEP 6: Configure App Settings
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 6/8] Configuring application settings...${NC}"

az webapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --settings \
        DB_HOST="$DB_FQDN" \
        DB_PORT="3306" \
        DB_NAME="$DB_NAME" \
        DB_USER="$DB_USER" \
        DB_PASS="$DB_PASSWORD" \
        APP_ENV="production" \
        BASE_URL="/" \
        APP_URL="https://$APP_NAME.azurewebsites.net" \
        LOG_LEVEL="INFO" \
        VAULT_ENABLED="false" \
    --output none

echo -e "${GREEN}  Application settings configured${NC}"

# Configure PHP settings
az webapp config set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --php-version "$PHP_VERSION" \
    --always-on true \
    --output none

# =============================================================================
# STEP 7: Deploy Application Code
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 7/8] Deploying application code...${NC}"

# Create deployment package
echo "  Creating deployment package..."
cd ..
zip -r "$APP_NAME.zip" app/ -x "*/logs/*" "*/.git/*" > /dev/null 2>&1

# Deploy using ZIP deploy
echo "  Uploading to Azure..."
az webapp deploy \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --src-path "$APP_NAME.zip" \
    --type zip \
    --output none

rm -f "$APP_NAME.zip"
cd azure-deploy

echo -e "${GREEN}  Application deployed successfully${NC}"

# =============================================================================
# STEP 8: Initialize Database
# =============================================================================
echo ""
echo -e "${YELLOW}[Step 8/8] Initializing database...${NC}"

# Allow current IP to access MySQL
MY_IP=$(curl -s ifconfig.me)
echo "  Whitelisting IP: $MY_IP"

az mysql flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DB_SERVER" \
    --rule-name "deploy-$(date +%s)" \
    --start-ip-address "$MY_IP" \
    --end-ip-address "$MY_IP" \
    --output none

# Wait for firewall rule to propagate
echo "  Waiting for firewall rule (15s)..."
sleep 15

# Run schema
mysql -h "$DB_FQDN" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < ../database/schema.sql

echo -e "${GREEN}  Database initialized${NC}"

# Remove deploy IP from firewall (optional - keep if you need DB access)
# az mysql flexible-server firewall-rule delete \
#     --resource-group "$RESOURCE_GROUP" \
#     --name "$DB_SERVER" \
#     --rule-name "deploy-*" \
#     --yes

# =============================================================================
# DEPLOYMENT COMPLETE
# =============================================================================
echo ""
echo "========================================================================"
echo -e "  ${GREEN}DEPLOYMENT COMPLETE!${NC}"
echo ""
echo "  App URL:         https://$APP_NAME.azurewebsites.net"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Database:        $DB_FQDN"
echo ""
echo "  NEXT STEPS:"
echo "  1. Test the application: curl https://$APP_NAME.azurewebsites.net"
echo "  2. Login with: admin / Admin@OCP2024!"
echo "  3. Change default password immediately!"
echo "  4. Continue to Phase 3: Custom domain setup"
echo ""
echo "  Database credentials saved to: ./db-credentials.txt"
echo "========================================================================"

# Save deployment info
cat > deployment-info.txt << EOF
=== OCP Deployment Info ===
Date: $(date)
App Name: $APP_NAME
Resource Group: $RESOURCE_GROUP
Location: $LOCATION
App URL: https://$APP_NAME.azurewebsites.net
Database Server: $DB_FQDN
Database: $DB_NAME
App Service Plan: $APP_SERVICE_PLAN
EOF
