# Building llama.cpp for the Tesla P100

`roles/llamacpp` builds llama.cpp from source on the AI container. Most runs
skip the build (`playbooks/llm-models.yml`); the details behind the flags live
here.

## Version

`llamacpp_version` in `roles/llamacpp/defaults/main.yml` is the only version
knob. It takes any llama.cpp tag, branch or commit and defaults to `v0.7.0`.

The P100 patch set is **not vendored in this repo**. It is maintained upstream,
rebased for each llama.cpp ref and **tagged with that ref's name**, and
`llamacpp_p100_patches_version` defaults to `{{ llamacpp_version }}`. So the
upgrade path is a single line here rather than a hand rebase of 19 patch files:

```yaml
llamacpp_version: v0.7.0     # -> the patch set's v0.7.0 tag is fetched too
```

The role records the resolved patch-set commit in
`/opt/llama.cpp/.ansible-build-flags`, so moving a tag upstream is visible and
triggers a rebuild instead of silently changing the tree.

## Bumping llama.cpp

1. Look at the tags the patch set publishes:
   `git ls-remote --tags https://github.com/sbendhiba/llama-cpp-pascal-patches`
   (`git tag -l` in a clone gives the same list, and `main` is always the newest).
2. Set `llamacpp_version` to the ref you want. Nothing else.
3. Run `site.yml`. Before cloning anything the role checks that the patch set has
   a tag or branch with that exact name, and fails with a message naming the
   patch repo if it does not — instead of a half-patched tree and a build error
   twenty minutes later.
4. If a patch does not apply, the run stops on it. The set is generated at exact
   context; a patch that "applies" with fuzz is the dangerous case, so there is
   none. Your options, in order:
   - the ref has no tag yet: build the newest ref that does, or
     `llamacpp_p100_patches: false` for stock;
   - the patch repo's `docs/patches.md` documents which patches it **deleted**
     because upstream absorbed them on each rebase — never carry one forward
     after reading that, since it can apply at zero fuzz and still be dead code;
   - you can live without one patch:
     `llamacpp_p100_patches_optional: [12-mmvq-f16-sm60.patch]`. Dependencies
     matter — several patches touch the same lines and later ones build on
     earlier ones — and the patch repo's `RELEASING.md` explains how to find the
     real dependency set instead of guessing;
   - porting experimentally onto an untagged ref:
     `llamacpp_p100_patches_ignore_missing: true` skips whatever no longer
     applies and says so after the run. Treat it as a measurement aid, not a
     deployable tree.
5. Pin `llamacpp_p100_patches_version` to a commit instead of a tag when you want
   a byte-reproducible build: the upstream repo force-moves a tag when it
   re-cuts it, and the `v0.6.0` tag was stale twice.

## Which patch set

| repo | shape | why / why not |
|---|---|---|
| [sbendhiba/llama-cpp-pascal-patches](https://github.com/sbendhiba/llama-cpp-pascal-patches) | 41 patches at `v0.7.0`, **one tag per llama.cpp ref** | default here: the tags are the upgrade path, and `docs/patches.md` records what each rebase dropped and which hunks needed re-anchoring |
| [shinbunbun/llama-cpp-p100-patches](https://github.com/shinbunbun/llama-cpp-p100-patches) | 45 patches, the original set | the measurements and the reasoning live here (and `docs/benchmarking.md`, worth reading on its own), but its set tracks one ref at a time with no per-ref tags |
| [qr0n/p100-llama-cpp](https://github.com/qr0n/p100-llama-cpp) | a whole llama.cpp fork at `b10660`, 18 patches | strongest on multi-GPU `-sm tensor` (N-card AllReduce, cuBLAS-GEMM attention); a fork, so it does not compose with an upstream ref |
| [ikawrakow/ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp) | a separate llama.cpp derivative | documents Pascal/Volta support (`docs/pascal-volta.md`) and upstreamed the P100 fp16 flash-attention fix in its own tree; a backend migration, not a patch set |

Only the patch set was ever P100-specific here; the CUDA 12/glibc work below is
independent of which of these you pick.

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
- `llamacpp_build_jobs: 2` — nvcc is memory hungry and the host has reset under
  4 parallel LTO jobs. `host_vars/llm` keeps it explicit for the AI host.
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

Why it matters on this card: GP100 is the only Pascal chip **without DP4A**
(so llama.cpp emulates the int8 dot product and falls back to cuBLAS for dense
matmuls) while it does have full-rate HFMA2. The patches attack exactly that
asymmetry; only ~10 of the 41 are Pascal-gated, the rest are kernel fusions and
scheduler work that help any card.

The set used to be vendored here as a 19-patch subset of
[shinbunbun/llama-cpp-p100-patches](https://github.com/shinbunbun/llama-cpp-p100-patches),
trimmed by hand to a single upstream commit. That subset was stale: it was
missing 10, 13, 15, 17, 18, 22, 24–28 and 31 of its own set, and the newer
49–51 (N-card AllReduce, CUDA graphs on Pascal, the cuBLAS prefill algorithm) —
i.e. more than half of the work, and the reason the tree could not move. It is
gone; `apply-patches.sh` now consumes whatever the pinned tag contains, in
filename order.

The measurements below were taken with that 19-patch subset at `b11696` and are
kept as the record of what the sm_60-specific patches are worth on this card,
**not** as the current set's numbers. For the current figures, see the patch
repo's README (`What to expect`) and `docs/patches.md`.

| model | test | stock b11696 | 19-patch subset | |
|---|---|---:|---:|---|
| Qwen3.5 9B Q4_K | pp512 | 620 | 622 | — |
| | pp2048 | 615 | 615 | — |
| | tg128 | 33.2 | **43.4** | +31 % |
| 35B-A3B IQ3_S | pp512 | 496 | 501 | +1 % |
| | pp2048 | 497 | 458 | −8 % (known trade-off of the set) |
| | tg128 | 46.0 | **60.0** | +30 % |

End to end through `llama-server` with the MTP model (draft-mtp n=3, KV q8_0,
8k ctx): 15.9 → **22.2 t/s** (+39 %).

### Measured on this host: 19 patches (master) -> 41 patches (v0.7.0)

The upgrade itself, A/B on the same card: `-ngl 99 -fa on -t 4 -p 512,2048
-n 128 -r 3`, each model preloaded and given a discarded warmup run, 2
interleaved rounds with the arm order reversed, median of 6 reps, 44-47 °C. The
old arm is the previous binary (master `2a667032d`, build 11698, + the 19
patches) kept at `/opt/p100bench/bin-masterp` and run with its own libraries.

| model | test | old 19p | new 41p | |
|---|---|---:|---:|---|
| Qwen3.5 9B Q4_K | pp512 | 586.2 | **652.5** | **+11.3 %** |
| | pp2048 | 577.2 | **645.1** | **+11.8 %** |
| | tg128 | 40.86 | 40.64 | −0.5 % |
| Qwen3.6 35B-A3B IQ3_S | pp512 | 456.3 | 456.8 | +0.1 % |
| | pp2048 | 436.3 | 437.2 | +0.2 % |
| | tg128 | 55.27 | 54.72 | −1.0 % |

Decode is parity because both arms already carried the decode patches (01, 02,
12): the 22 extra patches buy dense prefill, not decode. The point of the change
is that the tree moves again without a hand rebase — this is what moving costs.
Both arms land ~6 % below the October table above for the same old binary
(best-of-3 then, median and a warm cache now), so compare the A/B deltas here,
not across tables.

### The fp16 carve-out (still local, deliberately)

`files/carveout-sm60-fp16.py` extends the existing sm_61 carve-out to sm_60 in
the first two `FAST_FP16` gates (`ggml/src/ggml-cuda/common.cuh`):
`FAST_FP16_AVAILABLE` (device macro, used by the flash-attention kernels) and
`fast_fp16_available()` (mmvf). Same root cause as
[llama.cpp#25593](https://github.com/ggml-org/llama.cpp/issues/25593): GP100 has
fast fp16 hardware, so llama.cpp did quality-sensitive math in fp16, which is
~0.0023 median KLD against an fp32 truth base.

Measured here on a 9B Q4_K (`-ngl 99 -fa on`, ub 512, same flags both arms):
pp512 649.6 -> 648.4, pp2048 644.6 -> 640.3, tg128 44.74 -> 44.86. Free.

It stays a script rather than a patch because it is two string substitutions in
an expression upstream reformats freely: the script matches the gate expression
itself, is idempotent, and **warns instead of failing** when a gate is missing
(`llamacpp_p100_carveout_strict: true` to make it fail), since a gate upstream
moved is a precision regression, not a build failure.

**The third gate is deliberately NOT patched.**
`fast_fp16_hardware_available()` selects the cuBLAS compute type, and on GP100
fp32 GEMM costs ~40 % prefill: 9B pp2048 644.6 -> 386.8 t/s. Forcing MMQ to
avoid cuBLAS instead collapses dense prefill (9B pp512 202 t/s). So the weight
path on this card stays fp16 in exchange for prefill speed; fixing its precision
needs an fp32-accumulate GEMM at fp16 rate, which Pascal does not have. Patch 51
in the current set takes a different cut at the same problem (it makes cuBLAS
pick a block-accumulating fp16 algorithm on Pascal: closer to fp32 **and** faster
at 512–1024 rows), so re-measure before assuming this gate is still the right
trade.

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
