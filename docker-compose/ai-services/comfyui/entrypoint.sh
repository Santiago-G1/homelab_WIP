#!/bin/sh
# Link the nodes baked into the image into the persisted custom_nodes volume
# (ComfyUI-Manager installs its own nodes there, and those must survive an image
# rebuild). Existing entries win, so a node the user updated is never replaced
# by the baked copy.
set -e

# libcuda is bind mounted (the LXC cannot run nvidia-container-cli), so the
# image's linker cache does not know about it. Triton's driver looks the library
# up through `ldconfig -p` and aborts the import of comfy_kitchen otherwise;
# TRITON_LIBCUDA_PATH in the compose file is the same fix, this covers the rest.
ldconfig 2>/dev/null || true

mkdir -p /opt/ComfyUI/custom_nodes
for src in /opt/builtin_nodes/*; do
    [ -e "$src" ] || continue
    dest="/opt/ComfyUI/custom_nodes/$(basename "$src")"
    [ -e "$dest" ] || cp -a "$src" "$dest"
done

# No CMD in the image: the flags live in COMFYUI_ARGS, rendered into the stack's
# .env from host_vars/llm/main.yml.
if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086 # word splitting is the point: it is a flag list
    set -- python main.py --listen 0.0.0.0 --port 8188 ${COMFYUI_ARGS}
fi

exec "$@"
