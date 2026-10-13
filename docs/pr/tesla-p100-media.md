# Use the Tesla P100 in Immich and Jellyfin

Branch: `feat/p100-media` (not pushed).

## Summary

The Tesla P100 now accelerates both media services:

- **Jellyfin** transcodes with NVENC/NVDEC.
- **Immich** transcodes with NVENC/NVDEC **and** runs its machine learning on the P100 through CUDA.
- The Intel iGPU stays passed through as a VAAPI fallback.

An LXC has no `nvidia-container-runtime`, so the approach is device passthrough
plus bind-mounted driver libraries — the same pattern the repo already uses for
ComfyUI.

## What changed

| File | Change |
| --- | --- |
| `terraform/proxmox/lxc_media.tf` | Pass `/dev/nvidia{0,ctl,-uvm,-uvm-tools}` to `immich` (gid 991) and `frontend` (gid 44), next to the existing iGPU node. |
| `ansible/inventories/hosts.ini` | New `[gpu]` group: `frontend`, `immich`. |
| `ansible/inventories/group_vars/gpu/main.yml` | Pins `nvidia_driver_version: 580.159.04`. |
| `ansible/playbooks/site.yml` | Runs `roles/nvidia` on `[gpu]` before the Compose stacks. |
| `ansible/playbooks/verify.yml` | Checks `nvidia-smi` on the GPU hosts. |
| `docker-compose/media-services/frontend/jellyfin/docker-compose.yml` | P100 devices + NVENC/NVDEC libraries for `jellyfin-ffmpeg`. |
| `ansible/roles/stacks/templates/immich-override.yml.j2` | P100 devices/libraries for `immich-server`; `immich-machine-learning` switched to the `-cuda` image with the P100 passed in. |
| `README.md` | Documents the P100, codec limits and the shared-VRAM caveat. |

## Why these decisions

- **Wire transcoding *and* ML.** Immich uses the GPU in two independent places
  (video transcoding and machine learning). Only doing both makes the P100
  actually useful to Immich.
- **Device passthrough instead of the NVIDIA runtime.** Installing
  `nvidia-container-toolkit` inside an unprivileged LXC is fragile. Passing the
  nodes and bind-mounting the libraries is simpler and matches the existing
  ComfyUI stack. It was verified end-to-end (see below).
- **Bind-mount the libraries from the LXC.** `roles/nvidia` already installs the
  exact userspace driver version, so mounting `libcuda`, `libnvidia-encode`,
  `libnvcuvid`, `libnvidia-ml` and `libnvidia-ptxjitcompiler` keeps the userspace
  library and the host kernel module in lockstep. The PTX JIT compiler is needed
  because ffmpeg's `scale_cuda` filter compiles its kernel at runtime (GP100 is
  `sm_60`).
- **Keep the iGPU.** The P100 encoder only does H.264, so the iGPU is a free
  fallback and removing it would be a one-way door. Immich and Jellyfin use a
  single backend at a time, so leaving the node mapped costs nothing.
- **A dedicated `[gpu]` group.** Only `immich` and `frontend` get the P100;
  `arrsuite` does not need the driver, so `roles/nvidia` is not applied to all of
  `[media]`.
- **One pinned driver version.** The userspace driver must match the PVE host
  exactly; the version is pinned once per group, like `llm` already does.
- **`-cuda` ML image.** Immich ships a CUDA build of `immich-machine-learning`;
  ML needs no app setting and uses the GPU when present. Video transcoding still
  needs a one-time UI selection (documented, not in config), the same convention
  already used for the iGPU.
- **GP100 is H.264-encode only.** This is a hardware limit, not a config choice:
  HEVC/VP9 decode is hardware, HEVC *output* falls back to software.

## Validation

- Host GPU: `Tesla P100-PCIE-16GB`, driver `580.159.04`.
- Empirical NVENC through the exact LXC → Docker wiring (devices + library
  bind-mounts) using the bundled `jellyfin-ffmpeg`:
  `frame=30 ... h264_nvenc ... speed=8.55x` (hardware, not software).
- `terraform fmt -check -recursive` and `terraform validate`: pass.
- `ansible-playbook --syntax-check` on `site.yml` and `verify.yml`: pass.
- `docker compose config` on the merged Jellyfin and Immich projects: pass.
- `ghcr.io/immich-app/immich-machine-learning:v3-cuda` exists for the deployed
  `IMMICH_VERSION`.

## Deployment

Applied on 2026-10-13 (not pushed):

- `terraform apply`: in-place update of CT 121 and CT 122 (no destroy). Both
  containers restarted to pick up the new device nodes.
- `ansible-playbook playbooks/site.yml --limit frontend,immich`: NVIDIA userspace
  driver installed, Jellyfin and Immich stacks recreated with the P100. A second
  run is idempotent (`changed=0`).
- `ansible-playbook playbooks/verify.yml --limit frontend,immich`: all green,
  including the GPU check.
- Verified inside the containers: `h264_nvenc` encode works in both `jellyfin`
  and `immich_server`, and the ML container opens the P100 through `libcuda`
  (`cuDeviceGetName`) with `CUDAExecutionProvider` available in onnxruntime.

During the first Jellyfin playback test, transcoding failed because the setting
was still `vaapi` (VAAPI device creation failed). Switching to `nvenc` exposed a
second issue: `scale_cuda` failed with `CUDA_ERROR_JIT_COMPILER_NOT_FOUND`, since
`libnvidia-ptxjitcompiler.so.1` was not mounted. Added it to Jellyfin and
`immich-server` (`8835862`); the full NVENC pipeline then transcoded the test
movie (NVDEC decode + `scale_cuda` + `h264_nvenc`).

## After deploying (one-time, in the UIs)

Left to do in the applications (the devices and libraries are already wired):

1. Jellyfin → Dashboard → Playback → Transcoding → Hardware acceleration = `NVIDIA NVENC`.
   *(done on the live host; stored in `jellyfin/config/encoding.xml`)*
2. Immich → Administration → Settings → Video transcoding → Hardware acceleration = `NVENC`.
   *(still pending)*

## Caveats

- GP100 has **no HEVC/AV1 encoder**; HEVC output is software.
- VRAM is shared with `llama-server`: a loaded 27B model takes ~15 of 16 GiB, so
  Immich ML may not fit while a model is resident. Transcoding is unaffected.
  Stop the model (or lower its context) before bulk ML jobs.
- Pascal (compute 6.0) support depends on the CUDA version Immich bundles; this
  is why the repo stays on CUDA 12.x. Verify with the `-cuda` image after deploy.
