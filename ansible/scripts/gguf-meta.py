#!/usr/bin/env python3
"""Print what a .gguf declares about itself, for models.yml / models.local.yml.

llama.cpp knows a model's window, architecture and whether it carries a
multi-token-prediction head, but none of that reaches Ansible: the file has to
say it. This reads the GGUF header (a few KB, even for a 20 GiB file) and
prints either JSON or the YAML entry that models.local.yml expects.

    gguf-meta.py Model-IQ4_XS.gguf
    gguf-meta.py --yaml Model-IQ4_XS.gguf
    gguf-meta.py --yaml --ctx 131072 Model-IQ4_XS.gguf

No third-party modules: the format is little-endian, magic "GGUF".
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys

MAGIC = b"GGUF"

# GGUF metadata value types -> struct format (None = variable length).
SCALARS = {
    0: "<B",   # uint8
    1: "<b",   # int8
    2: "<H",   # uint16
    3: "<h",   # int16
    4: "<I",   # uint32
    5: "<i",   # int32
    6: "<f",   # float32
    7: "<?",   # bool
    8: None,   # string
    9: None,   # array
    10: "<Q",  # uint64
    11: "<q",  # int64
    12: "<d",  # float64
}


class Reader:
    def __init__(self, fh):
        self.fh = fh

    def take(self, n):
        data = self.fh.read(n)
        if len(data) != n:
            raise ValueError("truncated GGUF header")
        return data

    def scalar(self, fmt):
        size = struct.calcsize(fmt)
        return struct.unpack(fmt, self.take(size))[0]

    def string(self):
        return self.take(self.scalar("<Q")).decode("utf-8", "replace")

    def value(self, vtype, depth=0):
        if vtype == 8:
            return self.string()
        if vtype == 9:
            if depth > 1:          # nested arrays are not a thing, but be safe
                raise ValueError("nested array")
            item_type = self.scalar("<I")
            count = self.scalar("<Q")
            return [self.value(item_type, depth + 1) for _ in range(count)]
        fmt = SCALARS.get(vtype)
        if fmt is None:
            raise ValueError(f"unknown value type {vtype}")
        return self.scalar(fmt)


def read_gguf(path):
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        r = Reader(fh)
        if r.take(4) != MAGIC:
            raise ValueError(f"{path} is not a GGUF file")
        version = r.scalar("<I")
        if version < 2:
            raise ValueError(f"GGUF v{version}: only the v2+ layout is read")
        tensor_count = r.scalar("<Q")
        kv_count = r.scalar("<Q")

        meta = {}
        for _ in range(kv_count):
            key = r.string()
            meta[key] = r.value(r.scalar("<I"))

        tensors = []
        for _ in range(tensor_count):
            name = r.string()
            n_dims = r.scalar("<I")
            r.take(8 * n_dims)          # shape
            r.scalar("<I")              # ggml type
            r.scalar("<Q")              # offset
            tensors.append(name)

    arch = meta.get("general.architecture", "")
    ctx = None
    for key in (f"{arch}.context_length", f"{arch}.n_ctx_train", "context_length"):
        value = meta.get(key)
        if isinstance(value, int) and value > 0:
            ctx = value
            break

    return {
        "path": path,
        "file": os.path.basename(path),
        "name": os.path.basename(path)[: -len(".gguf")] if path.endswith(".gguf") else os.path.basename(path),
        "size_bytes": size,
        "size_gib": round(size / 1024**3, 2),
        "gguf_version": version,
        "architecture": arch,
        "context_length": ctx,
        "block_count": meta.get(f"{arch}.block_count"),
        "embedding_length": meta.get(f"{arch}.embedding_length"),
        "expert_count": meta.get(f"{arch}.expert_count"),
        "chat_template": isinstance(meta.get("tokenizer.chat_template"), str),
        "reasoning": any(
            k in meta for k in ("tokenizer.chat_template.jinja", "general.reasoning")
        ),
        "vision": any(k.startswith("clip.") for k in meta) or "mmproj" in path.lower(),
        "mtp_head": any("mtp" in t or "nextn" in t for t in tensors),
        "tensor_count": len(tensors),
        "metadata_keys": len(meta),
    }


def yaml_entry(info, ctx):
    lines = [
        # A quoted scalar: a model name may carry ':', ' #' or a leading '-'.
        f"  - name: {json.dumps(info['name'])}",
        "    args:",
        f"      ctx-size: {ctx}",
        "      n-gpu-layers: 99",
        '      flash-attn: "on"',
    ]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("model")
    ap.add_argument("--yaml", action="store_true", help="print the models.local.yml entry")
    ap.add_argument("--ctx", type=int, default=None,
                    help="window to write (default: the model's own, capped at 65536)")
    ap.add_argument("--ctx-cap", type=int, default=65536,
                    help="cap for the default window (a 262144 window does not fit two P100s)")
    args = ap.parse_args()

    try:
        info = read_gguf(args.model)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.yaml:
        own = info["context_length"] or args.ctx_cap
        print(yaml_entry(info, args.ctx or min(own, args.ctx_cap)))
        return 0

    print(json.dumps(info, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
