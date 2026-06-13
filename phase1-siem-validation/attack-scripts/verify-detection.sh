#!/bin/bash
###############################################################################
# PHASE 1: DETECTION VERIFICATION SCRIPT
# Run this on the Wazuh Server (Ubuntu in Azure) to verify alerts
###############################################################################

WAZUH_API="https://localhost:55000"
WAZUH_USER="wazuh-wui"
WAZUH_PASSWORD=""  # Will prompt

echo "========================================================================"
echo "  WAZUH DETECTION VERIFICATION"
echo "========================================================================"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root or with sudo"
    exit 1
fi

# Get credentials
echo -n "Enter Wazuh API password: "
read -s WAZUH_PASSWORD
echo ""

echo ""
echo "[1] Checking Wazuh Manager status..."
systemctl is-active wazuh-manager && echo "    [OK] wazuh-manager is running" || echo "    [FAIL] wazuh-manager is not running"
systemctl is-active wazuh-dashboard && echo "    [OK] wazuh-dashboard is running" || echo "    [FAIL] wazuh-dashboard is not running"
systemctl is-active wazuh-indexer && echo "    [OK] wazuh-indexer is running" || echo "    [FAIL] wazuh-indexer is not running"

echo ""
echo "[2] Recent Suricata alerts from agents..."
echo "    Command: grep -i suricata /var/ossec/logs/alerts/alerts.log | tail -20"
grep -i "suricata\|suricata" /var/ossec/logs/alerts/alerts.log 2>/dev/null | tail -20 || echo "    No suricata alerts found in local log"

echo ""
echo "[3] Recent authentication failure alerts..."
echo "    Checking for SSH brute force (rule 5712)..."
grep -E "5712|5503|5710" /var/ossec/logs/alerts/alerts.log 2>/dev/null | tail -10 || echo "    No auth alerts found"

echo ""
echo "[4] Alert statistics (last 24 hours)..."
echo "    Total alerts:"
grep -c "Alert:" /var/ossec/logs/alerts/alerts.log 2>/dev/null || echo "    N/A"

echo ""
echo "[5] Connected agents..."
/var/ossec/bin/agent_control -lc 2>/dev/null || echo "    Run '/var/ossec/bin/agent_control -lc' manually"

echo ""
echo "[6] Check specific rule IDs mentioned in project:"
RULE_IDS=("5712" "5503" "5710" "31103" "100205")
for rule_id in "${RULE_IDS[@]}"; do
    count=$(grep -c "$rule_id" /var/ossec/logs/alerts/alerts.log 2>/dev/null || echo "0")
    echo "    Rule $rule_id: $count occurrences"
done

echo ""
echo "[7] API Token generation (for dashboard verification)..."
TOKEN=$(curl -s -u "$WAZUH_USER:$WAZUH_PASSWORD" -k -X GET "$WAZUH_API/security/user/authenticate" 2>/dev/null | grep -o '"token":"[^"]*' | cut -d'"' -f4)
if [ -n "$TOKEN" ]; then
    echo "    [OK] API token obtained"
    echo ""
    echo "[8] Recent security events via API..."
    curl -s -k -H "Authorization: Bearer $TOKEN" \
         "$WAZUH_API/manager/logs?limit=20&sort=-timestamp" 2>/dev/null | head -100 || echo "    API query failed"
else
    echo "    [WARN] Could not obtain API token - check credentials"
fi

echo ""
echo "========================================================================"
echo "  VERIFICATION COMPLETE"
echo ""
echo "  MANUAL VERIFICATION STEPS:"
echo "  1. Open Wazuh Dashboard in browser"
echo "  2. Go to: Security Events > Events"
echo "  3. Apply filters:"
echo "     - rule.groups:suricata (for IDS alerts)"
echo "     - rule.id:5712 (for SSH brute force)"
echo "     - rule.groups:web (for web attacks)"
echo "  4. Check timestamps match attack execution times"
echo "  5. Take screenshots for detection matrix"
echo "========================================================================"
