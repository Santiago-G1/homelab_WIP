#!/bin/sh
# Apply the vendored P100 patch set to the llama.cpp checkout in $PWD.
#
# The role resets the tree to the pinned commit before this runs, so the base is
# always the same and the loop only has to apply. The patches were generated
# against llama.cpp v0.5.0; on the pinned commit most apply with plain
# `git apply`, a few only through a three-way merge (their v0.5.0 blobs are
# absent, so git falls back to the literal patch). Hence --3way everywhere.
#
# NOTE: do not pre-check with `git apply --3way --check`; with --3way that both
# applies the patch and reports "check", so the real apply then conflicts.
#
# Last line reports how many patches were applied.
set -eu
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
n=0
for p in "$dir"/*.patch; do
    if ! git apply --3way "$p" >/dev/null 2>&1; then
        echo "cannot apply $p (does it match the pinned llamacpp_version?)" >&2
        exit 1
    fi
    n=$((n + 1))
done
echo "applied $n"
