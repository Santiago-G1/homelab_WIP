# ComfyUI for the Tesla P100 (Pascal, sm_60) in CT 126.
#
# Why a local build instead of an upstream image: ComfyUI's requirements leave
# torch unpinned, and every CUDA 12.8/12.9 (and 13.x) wheel from torch 2.8 on
# dropped Maxwell/Pascal from its arch list. The P100 needs the 2.7 line on
# cu126, which still ships sm_60 SASS, so the base image is pinned here and the
# requirement install is constrained to it (constraints.txt).
FROM pytorch/pytorch:2.7.1-cuda12.6-cudnn9-runtime

ARG COMFYUI_VERSION
ARG GGUF_NODES_VERSION
ARG IPADAPTER_NODES_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# git/curl for the clones and the healthcheck, libGL for the OpenCV-backed nodes.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

COPY constraints.txt /tmp/constraints.txt

RUN git clone --depth 1 --branch "${COMFYUI_VERSION}" \
      https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
 && cd /opt/ComfyUI \
 && pip install -r requirements.txt -c /tmp/constraints.txt

# Nodes are built into the image (reproducible, no first-boot network) and then
# linked into the persisted custom_nodes volume by the entrypoint, so anything
# ComfyUI-Manager installs later survives an image rebuild.
RUN git clone https://github.com/city96/ComfyUI-GGUF.git /opt/builtin_nodes/ComfyUI-GGUF \
 && cd /opt/builtin_nodes/ComfyUI-GGUF \
 && git checkout "${GGUF_NODES_VERSION}" \
 && pip install -r requirements.txt

RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git /opt/builtin_nodes/ComfyUI_IPAdapter_plus \
 && cd /opt/builtin_nodes/ComfyUI_IPAdapter_plus \
 && git checkout "${IPADAPTER_NODES_VERSION}"

# Triton is imported at startup by comfy_kitchen (ComfyUI's kernel library) and
# builds a small CUDA driver helper with the system C compiler the first time it
# runs. The runtime base ships no compiler, so add one here, after the Python
# layers, to keep them cached.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/comfyui-entrypoint.sh
RUN chmod +x /usr/local/bin/comfyui-entrypoint.sh

WORKDIR /opt/ComfyUI
EXPOSE 8188
ENTRYPOINT ["/usr/local/bin/comfyui-entrypoint.sh"]
