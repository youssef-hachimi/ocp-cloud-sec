#!/bin/bash
###############################################################################
# SSL CERTIFICATE SETUP - Let's Encrypt for Custom Domains
# Cloud Security Project - Phase 3
#
# This script sets up free SSL certificates for:
#   - wazuh.yourdomain.com (Wazuh Dashboard)
#   - app.yourdomain.com (OCP Web App - Azure handles this)
#
# Prerequisites:
#   - Domain DNS A record points to this server's public IP
#   - Nginx installed and configured
#   - Port 80 open for Let's Encrypt validation
#
# Usage:
#   sudo ./setup-ssl.sh yourdomain.com
###############################################################################

set -e

DOMAIN="${1:-yourdomain.com}"
WAZUH_SUBDOMAIN="wazuh.$DOMAIN"
APP_SUBDOMAIN="app.$DOMAIN"
EMAIL="${2:-admin@$DOMAIN}"

echo "========================================================================"
echo "  SSL Certificate Setup - Let's Encrypt"
echo ""
echo "  Domain: $DOMAIN"
echo "  Wazuh:  $WAZUH_SUBDOMAIN"
echo "  App:    $APP_SUBDOMAIN"
echo "  Email:  $EMAIL"
echo "========================================================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root or with sudo"
    exit 1
fi

# =============================================================================
# STEP 1: Install Certbot
# =============================================================================
echo ""
echo "[Step 1/5] Installing Certbot..."

if ! command -v certbot &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq certbot python3-certbot-nginx
fi

echo "  Certbot version: $(certbot --version)"

# =============================================================================
# STEP 2: Validate DNS
# =============================================================================
echo ""
echo "[Step 2/5] Validating DNS records..."

WAZUH_IP=$(dig +short "$WAZUH_SUBDOMAIN" 2>/dev/null || echo "")
SERVER_IP=$(curl -s ifconfig.me)

if [ -z "$WAZUH_IP" ]; then
    echo "  [WARN] DNS record for $WAZUH_SUBDOMAIN not found"
    echo "  [INFO] Please create an A record: $WAZUH_SUBDOMAIN -> $SERVER_IP"
    read -p "Press Enter after DNS is configured, or Ctrl+C to abort..."
else
    echo "  $WAZUH_SUBDOMAIN resolves to: $WAZUH_IP"
    echo "  Server public IP: $SERVER_IP"
    
    if [ "$WAZUH_IP" != "$SERVER_IP" ]; then
        echo "  [WARN] DNS IP doesn't match server IP!"
        read -p "Press Enter to continue anyway, or Ctrl+C to abort..."
    fi
fi

# =============================================================================
# STEP 3: Obtain SSL Certificate
# =============================================================================
echo ""
echo "[Step 3/5] Obtaining SSL certificate..."

certbot certonly \
    --nginx \
    -d "$WAZUH_SUBDOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --rsa-key-size 4096 \
    --must-staple

echo "  Certificate obtained for $WAZUH_SUBDOMAIN"

# =============================================================================
# STEP 4: Update Nginx Configuration with SSL paths
# =============================================================================
echo ""
echo "[Step 4/5] Updating Nginx configuration..."

# Update the placeholder paths in nginx config
sed -i "s|yourdomain.com|$DOMAIN|g" /etc/nginx/sites-available/wazuh 2>/dev/null || true

# Test nginx configuration
nginx -t

# Reload nginx
systemctl reload nginx

echo "  Nginx configured and reloaded"

# =============================================================================
# STEP 5: Setup Auto-Renewal
# =============================================================================
echo ""
echo "[Step 5/5] Setting up certificate auto-renewal..."

# Test auto-renewal
certbot renew --dry-run

# Add cron job for auto-renewal
CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'"
(crontab -l 2>/dev/null | grep -v "certbot renew" || true; echo "$CRON_JOB") | crontab -

echo "  Auto-renewal configured (daily at 3:00 AM)"

# =============================================================================
# COMPLETE
# =============================================================================
echo ""
echo "========================================================================"
echo "  SSL SETUP COMPLETE!"
echo ""
echo "  Certificates location:"
echo "    /etc/letsencrypt/live/$DOMAIN/"
echo ""
echo "  Wazuh Dashboard: https://$WAZUH_SUBDOMAIN"
echo ""
echo "  Certificate will auto-renew. To check:"
echo "    sudo certbot certificates"
echo "    sudo certbot renew --dry-run"
echo ""
echo "  FOR AZURE APP (app.$DOMAIN):"
echo "  1. Go to Azure Portal > App Service > Custom Domains"
echo "  2. Add hostname: $APP_SUBDOMAIN"
echo "  3. Validate with A/CNAME record"
echo "  4. Add SSL binding (Managed Certificate - Free)"
echo "========================================================================"
