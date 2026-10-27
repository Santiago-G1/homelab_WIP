# ComfyUI for the Tesla P100 (sm_60) in CT 126.
#
# Local build because torch >= 2.8 dropped Pascal from its CUDA wheels: the last
# line with sm_60 is 2.7 on cu126, hence the pinned base and constraints.txt.
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

# Baked in for reproducibility; the entrypoint links them into the persisted
# custom_nodes volume, so manager installs survive an image rebuild.
RUN git clone https://github.com/city96/ComfyUI-GGUF.git /opt/builtin_nodes/ComfyUI-GGUF \
 && cd /opt/builtin_nodes/ComfyUI-GGUF \
 && git checkout "${GGUF_NODES_VERSION}" \
 && pip install -r requirements.txt

RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git /opt/builtin_nodes/ComfyUI_IPAdapter_plus \
 && cd /opt/builtin_nodes/ComfyUI_IPAdapter_plus \
 && git checkout "${IPADAPTER_NODES_VERSION}"

# Triton builds a CUDA helper with the system compiler on first import.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/comfyui-entrypoint.sh
RUN chmod +x /usr/local/bin/comfyui-entrypoint.sh

WORKDIR /opt/ComfyUI
EXPOSE 8188
ENTRYPOINT ["/usr/local/bin/comfyui-entrypoint.sh"]
