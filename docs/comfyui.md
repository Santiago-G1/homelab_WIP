# ComfyUI on the P100 (CT 126)

Image generation on the AI host, sharing the single Tesla P100-PCIE-16GB with
llama.cpp, Immich ML and Jellyfin NVENC.

- Stack: `/opt/docker/comfyui` (`docker-compose/ai-services/comfyui/`), published
  on `192.168.10.26:8188` and `https://comfy.<zona>/` through Caddy.
- **On demand.** llama.cpp alone holds ~15.8 of the 16 GB, so ComfyUI is not kept
  resident: the GPU panel's **Image** mode unloads the LLM, stops Immich ML,
  moves Jellyfin to the iGPU and then starts the container. Selecting LLM, Media
  or Shared stops it again. Everything else (`docker start comfyui` by hand)
  would OOM on the first model load.

## Why a locally built image

Upstream ComfyUI/Wheels images cannot be used on this card:

- PyTorch **dropped Maxwell and Pascal (sm_50/sm_60) from its CUDA 12.8 and 12.9
  builds in 2.8**, and CUDA 13 removed them entirely. The last line that still
  ships sm_60 SASS is **2.7.x on cu126**.
- ComfyUI's `requirements.txt` lists `torch`/`torchvision` without versions, so a
  naive build silently lands on a wheel that cannot see the card (`torch.cuda.
  is_available() == False`, or "requires CUDA capability sm_70 or higher").

`docker-compose/ai-services/comfyui/Dockerfile` therefore builds on
`pytorch/pytorch:2.7.1-cuda12.6-cudnn9-runtime` and installs the requirements
with `constraints.txt` (`torch==2.7.1`, `torchvision==0.22.1`). Verified inside
the container:

```
torch 2.7.1+cu126 · Tesla P100-PCIE-16GB · arch list ['sm_50','sm_60',...,'sm_90']
```

Bumping the base image means losing the card unless the new torch line still
carries sm_60: check `torch.cuda.get_arch_list()` before pinning a newer one.

## GPU plumbing (unprivileged LXC)

The container gets `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm` and
`/dev/nvidia-uvm-tools` plus the CT's `libcuda.so.1` bind-mounted. There is no
`nvidia-container-toolkit`: `nvidia-container-cli` needs `CAP_MKNOD`, which an
unprivileged container does not have, so it fails with "operation not
permitted". cuBLAS/cuDNN/nvrtc come from the torch wheels inside the image, and
the Pascal SASS is precompiled, so no PTX JIT is needed either.

## Flags (and why)

| Flag | Reason |
| --- | --- |
| `--force-fp16` | fp16 is 2x fp32 on GP100. ComfyUI still returns fp32 for Pascal on Linux (`comfy/model_management.py` lists `p100` among the "fp32 is faster" cards); it is not, for SDXL. |
| `--use-pytorch-cross-attention` | SDPA is the only usable backend: flash-attention and xformers' memory-efficient kernels need sm_70+/sm_80+. |
| `--disable-smart-memory` | Offloads weights to RAM as soon as the card is needed by someone else, instead of keeping them cached in VRAM. |
| `--reserve-vram 0.75` | Leaves room for the CUDA context and for Immich ML/Jellyfin while a workflow runs. |
| `--preview-method none` | No TAESD model installed; previews would only add noise. |

Not used on purpose: fp8 (`--fp8_e4m3fn-*`) needs sm_89+ compute, bf16 is not
supported by Pascal, and `--fast` (fp16 accumulation via `torch.compile`) needs
Ampere-class tensor cores.

Measured on this card: see "Benchmarks" at the bottom.

## Models

All models live on the tank, in their own directory (outside
`llamacpp_models_dir`, so the llama.cpp router does not offer an SDXL GGUF as if
it were an LLM):

```
/mnt/data/image_models/                 -> mounted as /opt/ComfyUI/models
  unet/        WAI-NSFW-illustrious-SDXL-v110-Q8_0.gguf   (2.6 GB)
               WAI-NSFW-illustrious-SDXL-v110-Q5_K_M.gguf (1.8 GB)
               pony_diffusion_v6_xl_Q8_0.gguf             (2.6 GB)
  clip/        pony_clip_g.safetensors, pony_clip_l.safetensors (fp16)
               illustrious_clip_{g,l}_fp8_e4m3fn.safetensors
  vae/         pony_VAE_SDXL.safetensors, illustrious_v110_vae_fp8_e4m3fn.safetensors
  clip_vision/ CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors
  ipadapter/   ip-adapter-plus_sdxl_vit-h.safetensors
  checkpoints/ v1-5-pruned-emaonly.safetensors
  workflows/   the old ai-dock workflows (pony / illustrious + image reference)
```

The GGUF unets are loaded with **ComfyUI-GGUF** (`UnetLoaderGGUFAdvanced`). The
stored workflows were written for an older node version: they were updated in
place (`patch_on_device: false`, required since 2026-01, and `dequant_dtype`
`float32` -> `float16`; the originals are next to them as `*.bak-20261025`).

The `clip`/`vae` files named `*fp8_e4m3fn*` are fp8 *storage*: ComfyUI casts them
on load, so they work on Pascal, but they save VRAM only, not time. The fp16
pony pair is the safer default.

Reference images go to `/mnt/data/comfyui_workspace/ComfyUI/input`, outputs to
`/mnt/data/comfyui_output`, workflows/settings to
`/mnt/data/comfyui_workspace/ComfyUI/user` (the old ai-dock workspace, reused).

## Custom nodes

`ComfyUI-GGUF` and `ComfyUI_IPAdapter_plus` are built into the image at pinned
commits (`comfyui_gguf_nodes_version`, `comfyui_ipadapter_nodes_version` in
`host_vars/llm/main.yml`) and copied into the persisted volume
`/opt/docker/comfyui/custom_nodes` on start. Anything else installed there
survives image rebuilds.

ComfyUI-Manager ships inside ComfyUI but is **disabled**: it can "update" torch
and leave the card unusable. To use it:

```sh
# in /opt/docker/comfyui/.env, then docker compose up -d
COMFYUI_ARGS="... --enable-manager"
```

## Operating it

```sh
# from the GPU panel: Image mode, or
curl -X POST -H "Authorization: Bearer <token>" http://192.168.10.26:8099/api/mode/image
pct exec 126 -- docker logs -f comfyui        # from the PVE node
pct exec 126 -- nvidia-smi                    # who holds the card
```

Verify: `ansible-playbook playbooks/verify.yml` checks that the container exists
and, when it is running, that `/system_stats` answers. The `comfy.` route is not
in the availability widget on purpose: a stopped-but-healthy on-demand service
would always look DOWN.

`https://comfy.<zona>/` has **no authentication** (ComfyUI has none of its own):
it stays LAN-only and must not be published in the Cloudflare tunnel.

## Known limits

- Opening `comfy.` while the container is stopped answers **502**: the route is
there, the service is not. Press Image mode first (or use the panel's ComfyUI
card, whose Start button does exactly that).
- Image mode and the LLM are mutually exclusive on a 16 GB card. While ComfyUI is
up, a request to LiteLLM/llama.cpp tries to load ~13.6 GB and fails with
`cudaMalloc failed: out of memory`; that is expected, and switching back to LLM
mode stops ComfyUI and frees the card again.
- The same applies to Immich ML: it is stopped in Image mode (it is CUDA) and
only comes back in Media/Shared mode.
- The container sees the **host's** RAM, not the CT's 12 GB limit
(`/system_stats` reports ~16 GB) because cgroup limits are not visible to
`psutil`. Watch `docker stats comfyui` when queueing many models: `comfy-aimdo`
pins ~6 GB.
- Pruning the Docker build cache (`docker builder prune -af`) means the next
`docker compose build` of this stack re-runs the pip install: budget ~15 min.

## Benchmarks

SDXL 1024x1024, 28 steps, euler_ancestral/karras, pony Q8_0 GGUF, fp16:

| Run | Time | Notes |
| --- | --- | --- |
| First prompt (cold) | 155 s | 87 s of model load from the ZFS pool + 68 s of sampling |
| Second prompt (warm) | 74 s | 68 s of sampling (2.45 s/it) |
| `dequant_dtype: float32` | 68 s of sampling | Identical: `--force-fp16` is what decides the compute dtype |
| IPAdapter + illustrious Q8_0 + fp8 CLIP/VAE | 189 s | Cold, including 3.3 GB of CLIP-vision/IPAdapter |

Where the time goes: the GPU sits at **100 % utilisation and ~125 W** (limit
165 W) during sampling, with only **4.0 GiB of 16 GiB** in use. It is
compute-bound, not VRAM-bound, so quantising harder or offloading does not help.
The attention is the hot spot: a single 16384-token (128x128 latent) call takes
**0.64 s** with PyTorch's memory-efficient SDPA kernel. Flash attention needs
sm_80+; the math backend would need ~40 GiB for that same call. There is no
xformers build for torch 2.7 on sm_60, which is why SDPA is the floor here.

Practical consequences on this lab:

- 1024x1024 is ~70 s per image; 768x768 and 512x512 scale quadratically
  (~40 s and ~20 s).
- The 2.7 GB Q8_0 unet is the right size: VRAM is not the constraint, so there is
  no reason to go below Q8_0 and lose quality.
- ComfyUI warns that torch < 2.8 has no DynamicVRAM support and falls back to the
  legacy ModelPatcher; VRAM estimates are pessimistic but the model does fit.
- `comfy-aimdo` pins ~6 GB of the 12 GB the container has. Long queues with many
  different models are the case to watch (`docker stats comfyui`), not single
  images.
