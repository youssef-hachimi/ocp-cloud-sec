#!/bin/bash
###############################################################################
# PHASE 1: SIEM VALIDATION - RECONNAISSANCE & PORT SCANNING ATTACKS
# Cloud Security Project - Kali Linux Attack Scripts
# 
# Target VMs:
#   - Debian VM    (suricata-debian)
#   - Ubuntu VM    (suricata-ubuntu)  
#   - Windows 10 VM (wazuh-win10)
#
# Expected Detections:
#   - Suricata: ET SCAN Potential Port Scan
#   - Wazuh: Suricata IDS alerts, OSSEC syslog
###############################################################################

set -e

# =============================================================================
# CONFIGURATION - Update these with your actual VM IPs
# =============================================================================
DEBIAN_IP="192.168.1.101"    # Update with actual Debian VM IP
UBUNTU_IP="192.168.1.102"    # Update with actual Ubuntu VM IP  
WINDOWS_IP="192.168.1.103"   # Update with actual Windows 10 VM IP
WAZUH_IP="192.168.1.100"     # Update with actual Wazuh server IP

RESULTS_DIR="/root/attack-results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "========================================================================"
echo "  CLOUD SECURITY PROJECT - PHASE 1: SIEM VALIDATION"
echo "  Attack Category: Reconnaissance & Port Scanning"
echo "  Start Time: $(date)"
echo "  Results Directory: $RESULTS_DIR"
echo "========================================================================"

# =============================================================================
# ATTACK 1.1: TCP SYN Port Scan (Stealth Scan)
# =============================================================================
echo ""
echo "[1.1] TCP SYN Port Scan against Ubuntu target..."
echo "      Tool: nmap -sS"
echo "      Expected: Suricata 'ET SCAN Potential Port Scan' alert"

nmap -sS -p 1-1000 --open -T4 \
     -oN "$RESULTS_DIR/01_syn_scan_ubuntu.txt" \
     "$UBUNTU_IP" 2>&1 | tee "$RESULTS_DIR/01_syn_scan_ubuntu_live.log"

echo "[1.1] Complete. Waiting 30 seconds for alert generation..."
sleep 30

# =============================================================================
# ATTACK 1.2: Full TCP Connect Scan with Service Detection
# =============================================================================
echo ""
echo "[1.2] Full TCP Connect Scan with Service Version Detection..."
echo "      Tool: nmap -sV -sC -O"
echo "      Expected: Multiple Suricata scan alerts, OS detection"

nmap -sT -sV -sC -O -p 1-1000 --open \
     -oN "$RESULTS_DIR/02_full_scan_debian.txt" \
     "$DEBIAN_IP" 2>&1 | tee "$RESULTS_DIR/02_full_scan_debian_live.log"

echo "[1.2] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 1.3: ICMP Ping Sweep (Network Discovery)
# =============================================================================
echo ""
echo "[1.3] ICMP Ping Sweep across target subnet..."
echo "      Tool: nmap -sn"
echo "      Expected: Suricata ICMP flood/network scan alerts"

# Get subnet from target IP (assumes /24)
SUBNET="${DEBIAN_IP%.*}.0/24"
nmap -sn -PE -PP -PM \
     -oN "$RESULTS_DIR/03_ping_sweep.txt" \
     "$SUBNET" 2>&1 | tee "$RESULTS_DIR/03_ping_sweep_live.log"

echo "[1.3] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 1.4: Aggressive Scan (All-in-One)
# =============================================================================
echo ""
echo "[1.4] Aggressive Scan against Windows 10 target..."
echo "      Tool: nmap -A (OS + Version + Script + Traceroute)"
echo "      Expected: Multiple high-severity Suricata alerts"

nmap -A -T4 -p 1-500 \
     -oN "$RESULTS_DIR/04_aggressive_scan_windows.txt" \
     "$WINDOWS_IP" 2>&1 | tee "$RESULTS_DIR/04_aggressive_scan_windows_live.log"

echo "[1.4] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 1.5: UDP Scan
# =============================================================================
echo ""
echo "[1.5] UDP Port Scan against Ubuntu target..."
echo "      Tool: nmap -sU (top 100 UDP ports)"
echo "      Expected: Suricata UDP scan detection"

nmap -sU --top-ports 100 \
     -oN "$RESULTS_DIR/05_udp_scan_ubuntu.txt" \
     "$UBUNTU_IP" 2>&1 | tee "$RESULTS_DIR/05_udp_scan_ubuntu_live.log"

echo "[1.5] Complete."

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "========================================================================"
echo "  RECONNAISSANCE ATTACKS COMPLETE"
echo "  Results saved to: $RESULTS_DIR"
echo "  End Time: $(date)"
echo ""
echo "  NEXT STEPS:"
echo "  1. Check Wazuh Dashboard for alerts"
echo "  2. Verify Suricata logs on each target: /var/log/suricata/fast.log"
echo "  3. Run verification script: ./verify-detection.sh"
echo "========================================================================"

# List all result files
echo ""
echo "Generated files:"
ls -la "$RESULTS_DIR/"
