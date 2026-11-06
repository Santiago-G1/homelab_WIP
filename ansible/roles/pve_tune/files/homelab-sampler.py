#!/usr/bin/env python3
"""One CSV line every N seconds: the state just before the host dies.

The box has reset four times in five days without writing a shutdown sequence,
so the journal says nothing about why. This keeps a short ring of samples on
disk (flushed and fsynced) so the last row is the state at the reset: RAM and
pressure, ARC, CPU and disk temperature, and what each GPU was drawing.

    homelab-sampler.py <log> [interval_seconds] [max_bytes]

Rotates once to <log>.1 when it grows past max_bytes: two files of that size,
which at 10 s is about a week of history.
"""

from __future__ import annotations

import glob
import os
import shutil
import subprocess
import sys
import time

FIELDS = [
    "ts", "up_s", "load1", "cpu_busy", "cpu_iowait",
    "psi_cpu", "psi_mem", "psi_io",
    "mem_total", "mem_avail", "mem_free", "swap_free",
    "arc_size", "arc_max",
    "cpu_c",
    "gpu_temp", "gpu_w", "gpu_util", "gpu_mem",
    "top",
]


def read(path, default=""):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return default


def kb_to_mib(value):
    try:
        return int(value.split()[0]) // 1024
    except (ValueError, IndexError):
        return -1


def meminfo():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        key, _, rest = line.partition(":")
        info[key] = rest.strip()
    return info


def psi():
    out = {}
    for kind in ("cpu", "memory", "io"):
        for line in read(f"/proc/pressure/{kind}").splitlines():
            if line.startswith("some"):
                out[kind] = line.split("avg60=")[1].split()[0]
                break
    return out


def arcstats():
    stats = {}
    for line in read("/proc/spl/kstat/zfs/arcstats").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] in ("size", "c_max"):
            stats[parts[0]] = int(parts[2])
    return stats


def cpu_times():
    parts = read("/proc/stat").splitlines()[0].split()[1:]
    values = [int(v) for v in parts]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return sum(values), idle, (values[4] if len(values) > 4 else 0)


def cpu_temp():
    best = None
    for hwmon in glob.glob("/sys/class/hwmon/hwmon*"):
        name = read(f"{hwmon}/name").lower()
        if name not in ("coretemp", "k10temp", "zenpower", "acpitz", "cpu_thermal"):
            continue
        for path in glob.glob(f"{hwmon}/temp*_input"):
            try:
                value = int(read(path)) / 1000.0
            except ValueError:
                continue
            best = value if best is None else max(best, value)
    return best


def gpus():
    try:
        out = subprocess.run(
            ["nvidia-smi",
             "--query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    rows = []
    for line in out.strip().splitlines():
        cells = [c.strip() for c in line.split(",")]
        if len(cells) == 4:
            rows.append(cells)
    return rows


def top_procs(limit=3):
    procs = []
    for stat_path in glob.glob("/proc/[0-9]*/statm"):
        pid = stat_path.split("/")[2]
        try:
            rss = int(read(stat_path).split()[1]) * os.sysconf("SC_PAGE_SIZE") // 2**20
            name = read(f"/proc/{pid}/comm", "?")
        except (OSError, ValueError, IndexError):
            continue
        procs.append((rss, name))
    procs.sort(reverse=True)
    return ";".join(f"{name}:{rss}" for rss, name in procs[:limit])


def rotate(log, max_bytes):
    try:
        if os.path.getsize(log) > max_bytes:
            shutil.move(log, log + ".1")
    except OSError:
        pass


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    log = sys.argv[1]
    interval = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    max_bytes = int(sys.argv[3]) if len(sys.argv) > 3 else 8 * 1024 * 1024

    started = time.monotonic()
    prev_total, prev_idle, prev_iowait = cpu_times()

    with open(log, "a", buffering=1) as out:
        if out.tell() == 0:
            out.write(",".join(FIELDS) + "\n")
        while True:
            time.sleep(interval)
            rotate(log, max_bytes)

            total, idle, iowait = cpu_times()
            d_total = max(total - prev_total, 1)
            busy = round(100.0 * (d_total - (idle - prev_idle)) / d_total, 1)
            io = round(100.0 * (iowait - prev_iowait) / d_total, 1)
            prev_total, prev_idle, prev_iowait = total, idle, iowait

            mem = meminfo()
            pressure = psi()
            arc = arcstats()
            gpu_rows = gpus()
            temp = cpu_temp()

            row = [
                time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                int(time.monotonic() - started),
                read("/proc/loadavg").split()[0],
                busy, io,
                pressure.get("cpu", ""), pressure.get("memory", ""), pressure.get("io", ""),
                kb_to_mib(mem.get("MemTotal", "")),
                kb_to_mib(mem.get("MemAvailable", "")),
                kb_to_mib(mem.get("MemFree", "")),
                kb_to_mib(mem.get("SwapFree", "")),
                arc.get("size", -1) // 2**20,
                arc.get("c_max", -1) // 2**20,
                "" if temp is None else round(temp, 1),
                ";".join(f"{r[0]}C/{r[1]}W" for r in gpu_rows),
                ";".join(r[1] for r in gpu_rows),
                ";".join(r[2] for r in gpu_rows),
                ";".join(r[3] for r in gpu_rows),
                top_procs(),
            ]
            out.write(",".join(str(v) for v in row) + "\n")
            out.flush()
            os.fsync(out.fileno())


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
