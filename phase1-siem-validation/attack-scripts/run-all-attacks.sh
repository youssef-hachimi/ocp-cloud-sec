#!/bin/bash
###############################################################################
# PHASE 1: MASTER SCRIPT - RUN ALL SIEM VALIDATION ATTACKS
# Cloud Security Project
#
# Usage: sudo ./run-all-attacks.sh
# Requires: Kali Linux with nmap, hydra, nikto, gobuster/dirb, curl
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_RESULTS="/root/attack-results/master-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$MASTER_RESULTS"

echo "========================================================================"
echo "  CLOUD SECURITY PROJECT - PHASE 1: SIEM VALIDATION"
echo "  MASTER ATTACK SCRIPT"
echo ""
echo "  This script will execute all attack categories:"
echo "    1. Reconnaissance & Port Scanning"
echo "    2. Brute Force & Authentication Attacks"
echo "    3. Web Application Attacks (after OCP deployment)"
echo "    4. Malicious Payloads & Exploit Simulation"
echo ""
echo "  IMPORTANT: Ensure you have permission to test these targets!"
echo "========================================================================"
echo ""
read -p "Enter Wazuh Dashboard URL (e.g., https://wazuh.yourdomain.com): " WAZUH_URL
read -p "Enter your test subnet (e.g., 192.168.1.0/24): " TEST_SUBNET
echo ""
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Create summary log
SUMMARY_LOG="$MASTER_RESULTS/attack-summary.log"
echo "SIEM Validation Attack Summary" > "$SUMMARY_LOG"
echo "Started: $(date)" >> "$SUMMARY_LOG"
echo "Wazuh URL: $WAZUH_URL" >> "$SUMMARY_LOG"
echo "======================================" >> "$SUMMARY_LOG"

# Function to run attack script and log results
run_attack_category() {
    local script_name=$1
    local category_name=$2
    
    echo ""
    echo "========================================================================"
    echo "  EXECUTING: $category_name"
    echo "========================================================================"
    
    start_time=$(date +%s)
    
    if bash "$SCRIPT_DIR/$script_name" 2>&1 | tee "$MASTER_RESULTS/${script_name%.sh}.master.log"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo "[PASS] $category_name completed in ${duration}s" | tee -a "$SUMMARY_LOG"
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo "[WARN] $category_name finished with warnings in ${duration}s" | tee -a "$SUMMARY_LOG"
    fi
    
    echo "Waiting 60 seconds between attack categories..."
    sleep 60
}

# Run all attack categories
run_attack_category "01-reconnaissance-scans.sh" "Reconnaissance & Port Scanning"
run_attack_category "02-brute-force-attacks.sh" "Brute Force & Authentication Attacks"

# Check if OCP app is deployed before running web attacks
read -p "Is the OCP web application deployed? (yes/no): " OCP_READY
if [ "$OCP_READY" == "yes" ]; then
    read -p "Enter OCP app URL (e.g., https://app.yourdomain.com): " OCP_URL
    # Update the web attack script with the correct URL
    sed -i "s|OCP_APP_URL=.*|OCP_APP_URL=\"$OCP_URL\"|" "$SCRIPT_DIR/03-web-application-attacks.sh"
    run_attack_category "03-web-application-attacks.sh" "Web Application Attacks"
else
    echo "[SKIP] Web application attacks - OCP not yet deployed" | tee -a "$SUMMARY_LOG"
fi

run_attack_category "04-payloads-and-exploits.sh" "Malicious Payloads & Exploit Simulation"

# Generate final summary
echo "" >> "$SUMMARY_LOG"
echo "======================================" >> "$SUMMARY_LOG"
echo "Completed: $(date)" >> "$SUMMARY_LOG"

echo ""
echo "========================================================================"
echo "  ALL ATTACK CATEGORIES COMPLETE"
echo "  Results: $MASTER_RESULTS"
echo "  Summary: $SUMMARY_LOG"
echo ""
echo "  IMMEDIATE NEXT STEPS:"
echo "  1. Open Wazuh Dashboard: $WAZUH_URL"
echo "  2. Navigate to Security Events module"
echo "  3. Run verification: sudo ./verify-detection.sh"
echo "  4. Fill out detection matrix: ../detection-matrix/matrix-template.md"
echo "========================================================================"

# List all generated logs
echo ""
echo "Generated files:"
find "$MASTER_RESULTS" -type f | sort
