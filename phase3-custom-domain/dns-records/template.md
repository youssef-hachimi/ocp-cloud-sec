# DNS Configuration Template - Cloud Security Project

## Domain Information
Replace `yourdomain.com` with your actual registered domain name.

---

## Required DNS Records

### 1. OCP Web Application (Azure App Service)

**Option A: A Record (if using IP)**
| Type | Host | Value | TTL |
|------|------|-------|-----|
| A | `app` | `<Azure App Service IP>` | 3600 |

**Option B: CNAME (recommended)**
| Type | Host | Value | TTL |
|------|------|-------|-----|
| CNAME | `app` | `<your-app>.azurewebsites.net` | 3600 |

> To find your App Service IP:
> ```bash
> az webapp show --name <APP_NAME> --resource-group <RG> --query outboundIpAddresses -o tsv
> ```

---

### 2. Wazuh Dashboard (Azure VM with nginx)

| Type | Host | Value | TTL |
|------|------|-------|-----|
| A | `wazuh` | `<Wazuh VM Public IP>` | 3600 |

> To find your VM's public IP:
> ```bash
> az vm list-ip-addresses --resource-group <RG> --name <VM_NAME> --query [].virtualMachine.network.publicIpAddresses[0].ipAddress -o tsv
> ```

---

### 3. HashiCorp Vault (Azure VM)

| Type | Host | Value | TTL |
|------|------|-------|-----|
| A | `vault` | `<Vault VM Public IP>` | 3600 |

---

### 4. Wildcard for Future Use (Optional)

| Type | Host | Value | TTL |
|------|------|-------|-----|
| CNAME | `*` | `yourdomain.com` | 3600 |

---

### 5. SPF, DKIM, DMARC (Optional - for email)

If you plan to send emails from the OCP app:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| TXT | `@` | `v=spf1 include:_spf.google.com ~all` | 3600 |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com` | 3600 |

---

## Azure Verification Records

When adding custom domains in Azure, you'll need these TXT records for validation:

### App Service Domain Verification
| Type | Host | Value | Purpose |
|------|------|-------|---------|
| TXT | `asuid.app` | `<verification-token-from-azure>` | Azure ownership proof |

---

## Complete Example (replace with your values)

```
Domain: cloudsec-project.com

A     app     20.119.0.42        (Azure App Service)
A     wazuh   20.51.123.45       (Wazuh VM in Azure)
A     vault   20.51.123.46       (Vault VM in Azure)
CNAME www     app.cloudsec-project.com
```

---

## Testing DNS Propagation

After configuring DNS records, test propagation:

```bash
# Test each subdomain
dig +short app.yourdomain.com
dig +short wazuh.yourdomain.com
dig +short vault.yourdomain.com

# Or using nslookup
nslookup app.yourdomain.com
nslookup wazuh.yourdomain.com

# Global propagation check (using multiple DNS servers)
dig @8.8.8.8 app.yourdomain.com
dig @1.1.1.1 app.yourdomain.com
dig @9.9.9.9 app.yourdomain.com
```

DNS propagation typically takes 5 minutes to 48 hours depending on TTL and provider.

---

## SSL Certificate Status

| Subdomain | Certificate Type | Provider | Status |
|-----------|-----------------|----------|--------|
| app.yourdomain.com | Managed | Azure (Free) | Pending |
| wazuh.yourdomain.com | Let's Encrypt | certbot | Pending |
| vault.yourdomain.com | Self-Signed + Let's Encrypt | certbot | Pending |
