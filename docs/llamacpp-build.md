# Building llama.cpp for the Tesla P100

`roles/llamacpp` builds llama.cpp from source on the AI container. Most runs
skip the build (`playbooks/llm-models.yml`); the details behind the flags live
here.

## Version

`llamacpp_version` is `master` in `host_vars/llm/main.yml`, so a `site.yml` run
re-fetches the branch and rebuilds whenever upstream moved. Pin a `bXXXX` tag
for reproducible builds.

## CUDA 12 on Debian trixie

- CUDA 12.x is the newest line that can target Pascal: 13.x dropped compute
  capability 6.x. The container runs trixie but the **Debian 12** CUDA repo is
  used (`cuda_repo_distro`), because debian13 only ships the 13.x toolkit.
- apt on trixie verifies signatures with Sequoia, whose policy stopped accepting
  SHA1 on 2026-02-01 while NVIDIA still signs the repo key with SHA1. The role
  writes `/etc/crypto-policies/back-ends/apt-sequoia.config` to allow it;
  without that, apt rejects the whole repository.
- CUDA 12.x declares `sinpi`/`cospi` in `crt/math_functions.h` without an
  exception specification, while glibc 2.41 declares the same C23 functions
  `noexcept(true)`. `g++`/`clang++` accept the redeclaration but nvcc's cudafe++
  rejects every translation unit that includes `<math.h>`. The role patches the
  header with `replace` (the closing `;` in the pattern keeps it idempotent;
  a package upgrade that restores it is re-patched).

## Build flags

- `llamacpp_cuda_arch: 60-real` — the P100 is `sm_60`.
- `llamacpp_cuda_force_mmq: "OFF"` — `sm_60` has no dp4a; the runtime heuristic
  already picks MMQ for MoE (faster without dp4a) and cuBLAS for dense models.
  Forcing it slows the dense ones down.
- `GGML_AVX2`/FMA/BMI2/AVX512 off, `-march=ivybridge` — the CPU is the rig's.
- `llamacpp_build_jobs: 4` — nvcc is memory hungry and the container has 12 GB.
- `GGML_CUDA_FA=ON`, `GGML_CUDA_GRAPHS=ON`.

A crash during linking can leave a truncated `llama-server` that looks newer
than its objects; the role deletes a zero-size binary so make rebuilds it
(otherwise systemd fails with "Exec format error").

## Router mode

`llama-server` runs with `--models-dir`, `--models-preset` and `--models-max 1`,
so it loads one `.gguf` on demand. `models.ini.j2` renders `llamacpp_global_args`
plus each model's `args` from `llm_models` in
`ansible/inventories/host_vars/llm/models.yml`. See `llm-models.md`.

## The P100 (sm_60) patch set

`roles/llamacpp/files/patches-p100/` vendors the part of
[shinbunbun/llama-cpp-p100-patches](https://github.com/shinbunbun/llama-cpp-p100-patches)
that applies to the pinned commit, plus the fp16 carve-out from
[llama.cpp#25593](https://github.com/ggml-org/llama.cpp/issues/25593). It is
applied by `files/apply-p100-patches.sh` right after the checkout, in filename
order, idempotently; `.ansible-build-flags` includes their checksums, so editing
or adding a patch rebuilds without touching anything else.

Why it matters on this card: GP100 is the only Pascal chip **without DP4A**
(so llama.cpp emulates the int8 dot product and falls back to cuBLAS for dense
matmuls) while it does have full-rate HFMA2. The patches attack exactly that
asymmetry. Measured here (llama-bench, best of 3 interleaved rounds,
`-ngl 99 -fa on`, ub 512, same flags both arms):

| model | test | stock b11696 | patched | |
|---|---|---:|---:|---|
| Qwen3.5 9B Q4_K | pp512 | 620 | 622 | — |
| | pp2048 | 615 | 615 | — |
| | tg128 | 33.2 | **43.4** | +31 % |
| 35B-A3B IQ3_S | pp512 | 496 | 501 | +1 % |
| | pp2048 | 497 | 458 | −8 % (known trade-off of the set) |
| | tg128 | 46.0 | **60.0** | +30 % |

End to end through `llama-server` with the MTP model (draft-mtp n=3, KV q8_0,
8k ctx): 15.9 → **22.2 t/s** (+39 %).

`99-p100-fp32-attn-mmvf.patch` extends the existing sm_61 carve-out to sm_60 in
the first two `FAST_FP16` gates (`common.cuh`): `FAST_FP16_AVAILABLE` (device
macro, used by the flash-attention kernels) and `fast_fp16_available()`
(mmvf). Same root cause as [llama.cpp#25593](https://github.com/ggml-org/llama.cpp/issues/25593):
GP100 has fast fp16 hardware, so llama.cpp did quality-sensitive math in fp16,
which is ~0.0023 median KLD against an fp32 truth base.

Measured here on a 9B Q4_K (`-ngl 99 -fa on`, ub 512, same flags both arms):
pp512 649.6 -> 648.4, pp2048 644.6 -> 640.3, tg128 44.74 -> 44.86. Free.

**The third gate is deliberately NOT patched.**
`fast_fp16_hardware_available()` selects the cuBLAS compute type, and on GP100
fp32 GEMM costs ~40 % prefill: 9B pp2048 644.6 -> 386.8 t/s. Forcing MMQ to
avoid cuBLAS instead collapses dense prefill (9B pp512 202 t/s). So the weight
path on this card stays fp16 in exchange for prefill speed; fixing its precision
needs an fp32-accumulate GEMM at fp16 rate, which Pascal does not have.

### ubatch

`llamacpp_model_overrides` carries the per-model `batch-size`/`ubatch-size` from
`models.yml`. On this card the ubatch is worth more than most flags: 9B pp2048
614 → 781 t/s at 2048; the 12-13 GiB models must stay at 1024 (at 2048 VRAM
pressure makes prefill erratic) and gain 486 → 669 (35B-A3B) and 134 → 153 (27B).
Decode does not move with the ubatch.

### Benchmarking gotcha

If the weights live on spinning storage, preload the `.gguf`
(`dd if=model of=/dev/null`) before a `llama-bench` run, or the 12-14 GiB models
are read from disk mid-test and prefill scatters by ±150 t/s.
