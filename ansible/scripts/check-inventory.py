#!/usr/bin/env python3
"""Fail fast on inventory mistakes that Ansible would otherwise resolve silently.

Two things are checked, both without contacting a host:

  catalogue   models.yml must name exactly one agent model, one model per
              profile, and every agent's `model_profile` must resolve.
  identity    terraform/proxmox and hosts.ini must agree on who is at which IP,
              and no vm_id or IP may be used twice.

Exit code 1 with one line per problem, 0 when clean. Only PyYAML is needed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / "ansible/inventories/host_vars/llm/models.yml"
AGENTS = ROOT / "ansible/inventories/host_vars/llm/main.yml"
HOSTS = ROOT / "ansible/inventories/hosts.ini"
TF_DIR = ROOT / "terraform/proxmox"

# Reached directly: the control node and the hypervisor itself.
NOT_IN_TERRAFORM = {"devops", "pve"}

problems: list[str] = []


def fail(msg: str) -> None:
    problems.append(msg)


def load_yaml(path: Path) -> dict:
    import yaml

    with path.open() as fh:
        return yaml.safe_load(fh) or {}


def check_catalogue() -> None:
    data = load_yaml(CATALOGUE)
    models = data.get("llm_models_catalogue") or []
    if not models:
        fail("catalogue: llm_models_catalogue is empty")
        return

    names = [m.get("name") for m in models]
    for name in sorted({n for n in names if names.count(n) > 1}):
        fail(f"catalogue: model {name} is listed twice (unique(attribute='name') hides it)")

    agents = [m["name"] for m in models if "agent" in m]
    if len(agents) != 1:
        fail(f"catalogue: expected exactly one `agent: true` model, found {len(agents)}: "
             + (", ".join(agents) or "none"))

    profiles: dict[str, str] = {}
    for m in models:
        if "profile" in m:
            p = m["profile"]
            if p in profiles:
                fail(f"catalogue: profile {p} claimed by {profiles[p]} and {m['name']}")
            profiles[p] = m["name"]

    main = load_yaml(AGENTS) if AGENTS.exists() else {}
    for agent, cfg in (main.get("hermes_agents") or {}).items():
        wanted = (cfg or {}).get("model_profile", "default")
        if wanted != "default" and wanted not in profiles:
            fail(f"catalogue: agent {agent} wants model_profile {wanted}, "
                 f"which no model claims (have: {', '.join(sorted(profiles)) or 'none'})")


def tf_entries() -> list[dict]:
    entries = []
    for tf in sorted(TF_DIR.glob("*.tf")):
        text = tf.read_text()
        for block in re.finditer(
            r'hostname\s*=\s*"([^"]+)".*?vm_id\s*=\s*(\d+).*?ip_address\s*=\s*"([\d.]+)"',
            text,
            re.S,
        ):
            hostname, vm_id, ip = block.groups()
            entries.append({"file": tf.name, "hostname": hostname, "vm_id": vm_id, "ip": ip})
    return entries


def inventory_hosts() -> dict[str, str]:
    hosts = {}
    for line in HOSTS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "[")):
            continue
        m = re.match(r"(\S+)\s+(.*)", line)
        if not m:
            continue
        name, rest = m.groups()
        ip = re.search(r"ansible_host=([\d.]+)", rest)
        if ip:
            hosts[name] = ip.group(1)
    return hosts


def check_identity() -> None:
    entries = tf_entries()
    if not entries:
        fail("identity: no container found in terraform/proxmox (hostname/vm_id/ip_address)")
        return
    hosts = inventory_hosts()

    for key in ("vm_id", "ip"):
        seen: dict[str, str] = {}
        for e in entries:
            val = e[key]
            if val in seen:
                fail(f"identity: {key} {val} used by {seen[val]} and {e['hostname']}")
            seen[val] = e["hostname"]

    by_ip = {ip: name for name, ip in hosts.items()}
    for e in entries:
        norm = e["hostname"].lower().replace("-", "_")
        if norm in hosts:
            if hosts[norm] != e["ip"]:
                fail(f"identity: {e['hostname']} is {e['ip']} in terraform but "
                     f"{hosts[norm]} in the inventory")
        elif e["ip"] not in by_ip:
            fail(f"identity: {e['hostname']} ({e['ip']}) has no host in hosts.ini")
        else:
            print(f"  note: {e['hostname']} matches {by_ip[e['ip']]} by IP, not by name")

    tf_ips = {e["ip"] for e in entries}
    for name, ip in sorted(hosts.items()):
        if name in NOT_IN_TERRAFORM:
            continue
        if ip not in tf_ips:
            fail(f"identity: inventory host {name} ({ip}) is not a terraform container")


def main() -> int:
    check_catalogue()
    check_identity()
    if problems:
        for p in problems:
            print(f"FAIL {p}", file=sys.stderr)
        return 1
    print("OK catalogue and identities agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
