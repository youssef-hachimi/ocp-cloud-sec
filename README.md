# OCP SOC Lab - Attack Simulation

Run **only** from the Kali node, **only** against your own lab VMs (10.0.3.10/.11/.12).
The script has a hardcoded guardrail (`ALLOWED_LAB_NETWORKS`) that refuses to run
against any IP outside `10.0.0.0/16`.

## What it does

| Phase | Tool | Action | What Suricata/Wazuh should show |
|---|---|---|---|
| 1. Recon | `nmap` | Service/version scan of port 22 on each VM | Suricata: port-scan / nmap signature alerts |
| 2. Brute force | `hydra` | Tries 5 users x 6 weak passwords over SSH | Wazuh: repeated `sshd` auth failure events, possible active-response/Fail2ban-style trigger if configured |
| 3. Unauthorized access | `sshpass` + `ssh` | Logs in with any cracked (or known weak) credential, runs `id; whoami; uname -a; w` | Wazuh: successful login event right after failures = classic brute-force-then-compromise pattern; Suricata may flag anomalous SSH session length/behavior |
| 4. DoS / flood | `hping3` | SYN flood against port 22, spoofed source IPs, for N seconds | Suricata: flood/DDoS signature, high connection-rate alert |

All 4 phases write to `logs/attack_sim_<timestamp>.log` (human-readable) and
`logs/attack_sim_report_<timestamp>.json` (structured, with UTC timestamps you
can line up against `eve.json` and the Wazuh dashboard timeline).

## Setup on Kali

```bash
sudo apt update
sudo apt install -y nmap hydra hping3 sshpass
```

## Usage

```bash
# Full run, all 3 default VMs, all 4 phases
sudo python3 ocp_attack_sim.py

# Only specific targets
sudo python3 ocp_attack_sim.py --targets 10.0.3.10 10.0.3.11

# Skip the SYN flood (e.g. first pass, just recon+bruteforce+access)
python3 ocp_attack_sim.py --skip-flood

# Shorter flood, more delay between phases for cleaner log reading
sudo python3 ocp_attack_sim.py --flood-duration 10 --delay 8
```

`sudo` is only strictly required for phase 4 (`hping3` needs raw sockets).
Phases 1-3 work fine unprivileged.

## Why these choices

- **Weak creds are tiny and obvious on purpose** (`root/toor`, `admin/admin123`, etc.) —
  this is a detection demo, not a real cracking tool. Set these up as actual
  low-privilege test accounts on your lab VMs beforehand if they don't already
  exist, or hydra will just report "no valid credentials" (which is itself a
  valid, loggable result — Wazuh will show pure auth-failure floods).
- **`-f` flag on hydra** stops at the first valid pair so the brute-force phase
  doesn't run indefinitely once it succeeds.
- **No custom exploit/payload code.** Everything is a wrapper call to
  industry-standard tools your professors/evaluators will recognize: nmap,
  hydra, hping3. This keeps the project legitimate and easy to explain in your
  report.
- **`--rand-source` on hping3** simulates spoofed-source flood traffic, which is
  the classic pattern Suricata DDoS rulesets are tuned to catch — good for
  showing a clean alert in your screenshots.

## Correlating results

On the Security Server VM (Wazuh + Suricata):

```bash
# Suricata - tail alerts live while the script runs
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="alert")'

# Or filtered to alerts only
sudo jq 'select(.event_type=="alert") | {timestamp, src_ip, dest_ip, alert: .alert.signature}' /var/log/suricata/eve.json
```

In the Wazuh dashboard:
- **Security Events** → filter by `agent.name` for the target VM and the time
  window from your run's JSON report.
- Look for `sshd` authentication failure rule IDs in a tight burst (brute force),
  followed by a successful login from the same source IP (unauthorized access).
- For the flood phase, check **Suricata module** alerts in Wazuh, or cross-reference
  directly in the Suricata `eve.json` since high-volume floods can also show up
  as a spike in Wazuh's own agent/manager connection stats if it overlaps the
  agent's reporting port — keep the flood targeted at 22 only, not 1514, to avoid
  knocking out the Wazuh agent channel itself mid-test.

## Suggested report structure (for your internship writeup)

1. Architecture diagram (you already have this).
2. Attack methodology table (the one above).
3. Suricata alert screenshots per phase, with timestamps.
4. Wazuh dashboard screenshots: auth failures → successful login correlation.
5. MITRE ATT&CK mapping (optional but examiners like it):
   - Recon → `T1046` Network Service Discovery
   - Brute force → `T1110.001` Password Guessing
   - Unauthorized access → `T1078` Valid Accounts
   - SYN flood → `T1498.001` Direct Network Flood
6. Recommendations (rate limiting, fail2ban/active-response, NSG tightening,
   MFA on SSH, Suricata rule tuning thresholds).
