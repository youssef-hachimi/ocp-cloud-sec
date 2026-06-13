# SIEM Detection Matrix - Cloud Security Project

## Project Information
- **Date**: ___________
- **Tester**: ___________
- **Wazuh Version**: ___________
- **Suricata Version**: ___________
- **Network Range**: ___________

## Target Inventory

| VM Name | OS | IP Address | Role | Wazuh Agent | Suricata |
|---------|-----|-----------|------|-------------|----------|
| suricata-debian | Debian 12 | | Target + Sensor | Yes | Yes |
| suricata-ubuntu | Ubuntu 22.04 | | Target + Sensor | Yes | Yes |
| wazuh-win10 | Windows 10 | | Target | Yes | No |
| kali-linux | Kali Linux | | Attacker | No | No |
| wazuh-server | Ubuntu 22.04 (Azure) | | SIEM Server | No | No |

---

## Detection Matrix

### Category 1: Reconnaissance & Port Scanning

| Attack Type | Tool | Source | Target | Suricata Detected | Wazuh Alert | Severity | Evidence Screenshot |
|------------|------|--------|--------|------------------|-------------|----------|-------------------|
| TCP SYN Scan | `nmap -sS` | Kali | Ubuntu | Yes / No | Yes / No | Low | |
| Full TCP Connect | `nmap -sT -sV` | Kali | Debian | Yes / No | Yes / No | Low | |
| ICMP Ping Sweep | `nmap -sn` | Kali | Subnet | Yes / No | Yes / No | Info | |
| Aggressive Scan | `nmap -A` | Kali | Windows | Yes / No | Yes / No | Medium | |
| UDP Scan | `nmap -sU` | Kali | Ubuntu | Yes / No | Yes / No | Low | |
| OS Detection | `nmap -O` | Kali | All | Yes / No | Yes / No | Low | |

**Expected Suricata Rules:**
- ET SCAN Potential Port Scan
- ET SCAN NMAP OS Detection Probe
- ET SCAN ICMP PING NMAP
- ET SCAN Possible NMAP User-Agent

**Expected Wazuh Rules:**
- 5701: Attempt to login using a non-existent user
- 5710: Attempt to login using an invalid user

---

### Category 2: Brute Force & Authentication Attacks

| Attack Type | Tool | Source | Target | Suricata Detected | Wazuh Alert | Severity | Evidence Screenshot |
|------------|------|--------|--------|------------------|-------------|----------|-------------------|
| SSH Brute Force | `hydra` | Kali | Ubuntu | Yes / No | Yes / No | High | |
| SSH Brute Force | `hydra` | Kali | Debian | Yes / No | Yes / No | High | |
| FTP Brute Force | `hydra` | Kali | Ubuntu | Yes / No | Yes / No | Medium | |
| Manual Failed Logins | `ssh` | Kali | Ubuntu | No | Yes / No | Medium | |
| RDP Brute Force | `hydra` | Kali | Windows | N/A | Yes / No | High | |
| SMB Brute Force | `hydra` | Kali | Windows | N/A | Yes / No | High | |

**Expected Suricata Rules:**
- ET SCAN Possible SSH Brute Force
- ET SCAN Potential FTP Brute Force

**Expected Wazuh Rules:**
- 5712: SSH brute force trying to get access
- 5503: Login failed
- 5710: Attempt to login using invalid user

---

### Category 3: Web Application Attacks

| Attack Type | Tool | Source | Target | Suricata Detected | Wazuh Alert | Severity | Evidence Screenshot |
|------------|------|--------|--------|------------------|-------------|----------|-------------------|
| Vulnerability Scan | `nikto` | Kali | OCP App | Yes / No | Yes / No | Medium | |
| Directory Brute Force | `gobuster` | Kali | OCP App | Yes / No | Yes / No | Medium | |
| SQL Injection | `curl` | Kali | OCP App | Yes / No | Yes / No | High | |
| XSS Attempts | `curl` | Kali | OCP App | Yes / No | Yes / No | Medium | |
| HTTP Flood | `curl loop` | Kali | OCP App | Yes / No | Yes / No | Medium | |
| Suspicious User-Agent | `curl -A` | Kali | OCP App | Yes / No | Yes / No | Low | |

**Expected Suricata Rules:**
- ET WEB_SERVER/Web Application Scan
- ET WEB_SERVER Possible SQL Injection
- ET WEB_SERVER Possible XSS Attempt
- ET WEB_Malicious User-Agent

**Expected Wazuh Rules:**
- 31103: Apache access from unknown user
- Web error log analysis

---

### Category 4: Malicious Payloads & Exploit Simulation

| Attack Type | Tool | Source | Target | Suricata Detected | Wazuh Alert | Severity | Evidence Screenshot |
|------------|------|--------|--------|------------------|-------------|----------|-------------------|
| Reverse Shell | `curl` | Kali | OCP App | Yes / No | Yes / No | Critical | |
| Log4Shell | `curl` | Kali | OCP App | Yes / No | Yes / No | Critical | |
| Shellshock | `curl -H` | Kali | OCP App | Yes / No | Yes / No | Critical | |
| Path Traversal | `curl` | Kali | OCP App | Yes / No | Yes / No | High | |
| Command Injection | `curl` | Kali | OCP App | Yes / No | Yes / No | Critical | |

**Expected Suricata Rules:**
- ET EXPLOIT Possible Reverse Shell Command
- ET EXPLOIT Apache Log4j RCE Attempt
- ET EXPLOIT Shellshock Bash CVE-2014-6271
- ET WEB_SERVER Possible Remote File Inclusion

**Expected Wazuh Rules:**
- 100205: Log4j RCE attempt
- Custom rules for reverse shell patterns

---

## Overall Detection Statistics

| Metric | Count |
|--------|-------|
| Total Attack Types Tested | |
| Successfully Detected by Suricata | / |
| Successfully Detected by Wazuh | / |
| Critical Severity Detections | |
| High Severity Detections | |
| Medium Severity Detections | |
| Low Severity Detections | |
| Undetected Attacks (Blind Spots) | |

## Blind Spot Analysis

| Undetected Attack | Reason | Mitigation |
|------------------|--------|------------|
| | | |
| | | |

## Recommendations

1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

---

## Screenshots Checklist

- [ ] Wazuh Dashboard - Agent List (all agents active)
- [ ] Wazuh Dashboard - Security Events Overview
- [ ] Suricata alerts filtered view
- [ ] SSH Brute Force detection detail
- [ ] Port scan detection detail
- [ ] Web attack detection detail
- [ ] Log4Shell/Critical exploit detection
- [ ] Detection matrix completed with Yes/No filled
