#!/usr/bin/env python3
"""Carve sm_60 (Tesla P100) out of the fp16 fast path, for attention and mmvf only.

llama.cpp#25593: GP100 has fast fp16 hardware, so the CUDA backend ran
quality-sensitive math in fp16 — ~0.0023 median KLD against an fp32 truth base.
sm_61 was exempted from these gates long ago; this extends the same idiom to
sm_60.

Two of the three gates are patched (FAST_FP16_AVAILABLE, used by the
flash-attention kernels, and fast_fp16_available(), used by mmvf). Measured free
here: -0.2% pp512, -0.7% pp2048, +0.3% tg on a 9B Q4_K.

The third gate is deliberately left alone: fast_fp16_hardware_available()
selects the cuBLAS compute type, and on GP100 fp32 GEMM costs ~40% prefill
(9B pp2048 645 -> 387 t/s measured). Forcing MMQ instead collapses dense
prefill (pp512 202 t/s). Fixing the weight-path precision needs an
fp32-accumulate GEMM at fp16 speed, which Pascal does not have.

This runs after the patch set, which is why it is a script and not a patch: the
patch would have to be rebased onto every upstream change of the same file.
Idempotent; exits non-zero if the expected source is not there.
"""
import pathlib
import sys

P = pathlib.Path("/opt/llama.cpp/ggml/src/ggml-cuda/common.cuh")
s = P.read_text()

GATE1 = "#if defined(FP16_AVAILABLE) && __CUDA_ARCH__ != 610\n"
GATE1_FIXED = "#if defined(FP16_AVAILABLE) && __CUDA_ARCH__ != 610 && __CUDA_ARCH__ != GGML_CUDA_CC_PASCAL\n"
GATE2 = "(GGML_CUDA_CC_IS_NVIDIA(cc) && fp16_available(cc) && ggml_cuda_highest_compiled_arch(cc) != 610) ||"
GATE2_FIXED = (
    "(GGML_CUDA_CC_IS_NVIDIA(cc) && fp16_available(cc) &&\n"
    "         ggml_cuda_highest_compiled_arch(cc) != 610 && "
    "ggml_cuda_highest_compiled_arch(cc) != GGML_CUDA_CC_PASCAL) ||"
)

if GATE1_FIXED in s and GATE2_FIXED in s:
    print("already")
    sys.exit(0)

if GATE1 not in s or GATE2 not in s:
    print("common.cuh does not look like the expected upstream source", file=sys.stderr)
    sys.exit(1)

s = s.replace(GATE1, GATE1_FIXED).replace(GATE2, GATE2_FIXED)
P.write_text(s)
print("applied")
