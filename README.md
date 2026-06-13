# Cloud Security Project - Complete Implementation Package

## Quick Start

This package contains everything needed to complete your cloud security internship project across 4 phases.

### What's Included

```
cloud-security-project/
├── phase1-siem-validation/          # SIEM testing with Kali Linux
│   ├── attack-scripts/              # Ready-to-run attack scripts
│   │   ├── 01-reconnaissance-scans.sh
│   │   ├── 02-brute-force-attacks.sh
│   │   ├── 03-web-application-attacks.sh
│   │   ├── 04-payloads-and-exploits.sh
│   │   ├── run-all-attacks.sh       # Master attack launcher
│   │   └── verify-detection.sh      # Wazuh alert verification
│   ├── detection-matrix/
│   │   └── matrix-template.md       # Fill during testing
│   └── wazuh-custom-rules/
│       └── local_rules.xml          # Enhanced detection rules
│
├── phase2-ocp-webapp/               # OCP PHP Web Application
│   ├── app/                         # Full PHP source code
│   │   ├── config/config.php
│   │   ├── public/                  # Web root
│   │   ├── src/
│   │   │   ├── utils/               # Database, Auth, Security, Logger
│   │   │   └── views/               # Login, Dashboard
│   │   └── ...
│   ├── database/schema.sql          # MySQL schema + seed data
│   └── azure-deploy/
│       └── azure-deploy.sh          # One-command Azure deployment
│
├── phase3-custom-domain/            # Custom domain + SSL
│   ├── nginx-configs/
│   │   └── wazuh-dashboard-proxy.conf
│   ├── ssl-scripts/
│   │   └── setup-ssl.sh             # Let's Encrypt automation
│   └── dns-records/
│       └── template.md              # DNS configuration guide
│
├── phase4-vault-pam/                # HashiCorp Vault PAM
│   ├── vault-config/
│   │   └── install-vault.sh         # Vault installation + config
│   └── app-integration/
│       └── vault-client.php         # PHP Vault client for OCP
│
└── docs/
    └── project-master-guide.md      # Complete implementation guide
```

## Execution Order

### Phase 1: Validate SIEM (Start Here)

```bash
# On Kali Linux:

# 1. Update IP addresses in scripts:
nano phase1-siem-validation/attack-scripts/01-reconnaissance-scans.sh

# 2. Make scripts executable:
chmod +x phase1-siem-validation/attack-scripts/*.sh

# 3. Run all attacks:
cd phase1-siem-validation/attack-scripts
sudo ./run-all-attacks.sh

# 4. Verify detections on Wazuh server:
scp verify-detection.sh wazuh-server:/tmp/
ssh wazuh-server "sudo bash /tmp/verify-detection.sh"

# 5. Fill detection matrix:
nano phase1-siem-validation/detection-matrix/matrix-template.md

# 6. Install custom rules on Wazuh server:
scp wazuh-custom-rules/local_rules.xml wazuh-server:/tmp/
ssh wazuh-server "sudo cp /tmp/local_rules.xml /var/ossec/etc/rules/ && sudo systemctl restart wazuh-manager"
```

### Phase 2: Deploy OCP Web App

```bash
# Prerequisites: Azure CLI installed, logged in (az login)

# 1. Deploy to Azure:
cd phase2-ocp-webapp/azure-deploy
chmod +x azure-deploy.sh
./azure-deploy.sh

# 2. Note the generated app URL and credentials

# 3. Test:
curl https://<app-name>.azurewebsites.net
# Login: admin / Admin@OCP2024!
```

### Phase 3: Configure Custom Domain

```bash
# On Wazuh server (Ubuntu VM in Azure):

# 1. Install nginx and certbot:
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx

# 2. Configure nginx proxy:
sudo cp phase3-custom-domain/nginx-configs/wazuh-dashboard-proxy.conf \
     /etc/nginx/sites-available/wazuh
sudo ln -s /etc/nginx/sites-available/wazuh /etc/nginx/sites-enabled/

# 3. Setup SSL:
cd phase3-custom-domain/ssl-scripts
chmod +x setup-ssl.sh
sudo ./setup-ssl.sh yourdomain.com your-email@example.com

# 4. Configure Azure App Service domain in Azure Portal
```

### Phase 4: Deploy Vault PAM

```bash
# On dedicated Ubuntu VM (or existing Wazuh server):

# 1. Install Vault:
cd phase4-vault-pam/vault-config
chmod +x install-vault.sh
sudo ./install-vault.sh

# 2. Save the unseal keys and root token securely!

# 3. Configure OCP app to use Vault:
#    In Azure Portal > App Service > Configuration:
#    VAULT_ENABLED = true
#    VAULT_ADDR = https://vault.yourdomain.com:8200
#    VAULT_ROLE_ID = <from installation output>
#    VAULT_SECRET_ID = <from installation output>

# 4. Copy vault-client.php to OCP app:
#    phase4-vault-pam/app-integration/vault-client.php -> app/src/utils/
```

## Critical Configuration Checklist

Before running anything, update these values throughout the project:

| File | Setting | Description |
|------|---------|-------------|
| All attack scripts | `DEBIAN_IP`, `UBUNTU_IP`, `WINDOWS_IP` | Your VM IP addresses |
| `config/config.php` | `DB_HOST`, `DB_USER`, `DB_PASS` | Azure MySQL credentials |
| `config/config.php` | `VAULT_ADDR`, `VAULT_ROLE_ID` | After Vault installation |
| `azure-deploy.sh` | `RESOURCE_GROUP`, `LOCATION` | Your Azure preferences |
| `setup-ssl.sh` | `DOMAIN` | Your registered domain |
| `install-vault.sh` | `DOMAIN` | Your registered domain |
| `wazuh-dashboard-proxy.conf` | `server_name` | Your wazuh subdomain |
| `vault.hcl` (generated) | `api_addr`, `cluster_addr` | Vault domain |

## Important Notes

- **Default passwords must be changed immediately after deployment**
- The OCP app includes intentionally vulnerable endpoints (`/api/execute.php`, `/api/ping.php`) for security testing - do not expose these in production without proper controls
- Vault unseal keys are critical - store them securely offline
- Keep `db-credentials.txt` and `vault-init-backup.json` secure with `chmod 600`

## Support

For detailed instructions, refer to `docs/project-master-guide.md`.

---

*Generated for Cloud Security Internship Project*
