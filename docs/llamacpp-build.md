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
