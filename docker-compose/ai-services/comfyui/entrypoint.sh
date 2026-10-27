#!/bin/sh
# Link the baked nodes into the persisted custom_nodes volume; existing entries
# win, so a node the user updated is never replaced by the baked copy.
set -e

# libcuda is bind mounted, so the linker cache has to learn about it or Triton
# aborts the import of comfy_kitchen.
ldconfig 2>/dev/null || true

mkdir -p /opt/ComfyUI/custom_nodes
for src in /opt/builtin_nodes/*; do
    [ -e "$src" ] || continue
    dest="/opt/ComfyUI/custom_nodes/$(basename "$src")"
    [ -e "$dest" ] || cp -a "$src" "$dest"
done

# The flags live in COMFYUI_ARGS, rendered into the stack's .env.
if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086 # word splitting is the point: it is a flag list
    set -- python main.py --listen 0.0.0.0 --port 8188 ${COMFYUI_ARGS}
fi

exec "$@"
