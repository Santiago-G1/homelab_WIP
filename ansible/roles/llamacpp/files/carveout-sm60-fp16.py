#!/usr/bin/env python3
"""Carve sm_60 (Tesla P100) out of llama.cpp's fp16 fast path, attention + mmvf.

llama.cpp#25593: GP100 has fast fp16 hardware, so the CUDA backend ran
quality-sensitive math in fp16 — ~0.0023 median KLD against an fp32 truth base.
sm_61 was exempted from these gates long ago; this extends the same idiom to
sm_60.

Two of the three gates are patched: FAST_FP16_AVAILABLE (device macro, used by
the flash-attention kernels) and fast_fp16_available() (mmvf). Measured free
here: -0.2% pp512, -0.7% pp2048, +0.3% tg on a 9B Q4_K.

The third gate is deliberately left alone: fast_fp16_hardware_available()
selects the cuBLAS compute type, and on GP100 fp32 GEMM costs ~40% prefill
(9B pp2048 645 -> 387 t/s measured). Forcing MMQ instead collapses dense
prefill (pp512 202 t/s). Fixing the weight-path precision needs an
fp32-accumulate GEMM at fp16 speed, which Pascal does not have.

This is a script and not a patch on purpose: it edits two expressions that
upstream reformats freely, so a patch would need a rebase on every llama.cpp
bump for what is two substitutions. The match is the gate expression itself,
not its surrounding lines, and it is idempotent.

Usage: carveout-sm60-fp16.py [--strict] [LLAMA_CPP_DIR]
  --strict  fail when a gate is missing instead of warning (a missing gate is a
            precision regression, not a build failure, so the default is a
            warning: upstream may have moved or fixed it)
"""
import argparse
import pathlib
import re
import sys

# (label, pattern matching the upstream gate, replacement, marker of the patched form)
GATES = (
    (
        "FAST_FP16_AVAILABLE (flash attention)",
        # Only the #if itself. The #endif comment on the next line carries the
        # same expression, and the third gate spells it as `cc != 610`, so the
        # anchors and the full directive keep this to exactly one edit.
        re.compile(r"^#if defined\(FP16_AVAILABLE\) && __CUDA_ARCH__ != 610[ \t]*$", re.MULTILINE),
        "#if defined(FP16_AVAILABLE) && __CUDA_ARCH__ != 610 && __CUDA_ARCH__ != GGML_CUDA_CC_PASCAL",
        "__CUDA_ARCH__ != GGML_CUDA_CC_PASCAL",
    ),
    (
        "fast_fp16_available (mmvf)",
        re.compile(r"ggml_cuda_highest_compiled_arch\(cc\) != 610"),
        "ggml_cuda_highest_compiled_arch(cc) != 610 && "
        "ggml_cuda_highest_compiled_arch(cc) != GGML_CUDA_CC_PASCAL",
        "ggml_cuda_highest_compiled_arch(cc) != GGML_CUDA_CC_PASCAL",
    ),
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("source", nargs="?", default=".")
    args = ap.parse_args()

    path = pathlib.Path(args.source) / "ggml/src/ggml-cuda/common.cuh"
    try:
        src = path.read_text()
    except OSError as exc:
        print(f"cannot read {path}: {exc}", file=sys.stderr)
        return 1

    out = src
    missing = []
    for label, pattern, fixed, marker in GATES:
        if marker in out:
            print(f"{label}: already carved out")
            continue
        new, count = pattern.subn(fixed, out)
        if count != 1:
            missing.append(f"{label}: expected 1 match, found {count}")
            continue
        out = new
        print(f"{label}: carved sm_60 out")

    if missing:
        for line in missing:
            print(f"warning: {line}", file=sys.stderr)
        print(
            "warning: sm_60 may still take the fp16 fast path (llama.cpp#25593);"
            " re-check ggml/src/ggml-cuda/common.cuh",
            file=sys.stderr,
        )
        if args.strict:
            return 1

    if out != src:
        path.write_text(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
