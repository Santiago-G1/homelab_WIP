#!/bin/sh
# Apply a numbered llama.cpp patch set (the P100 one by default) to the checkout
# in $PWD, in filename order.
#
#   apply-patches.sh [PATCH_DIR]
#
# PATCH_DIR defaults to the first argument and must contain the *.patch files.
# Environment:
#   LLAMACPP_PATCH_OPTIONAL       space-separated basenames allowed to not apply
#   LLAMACPP_PATCH_IGNORE_MISSING non-empty: every patch is optional
#
# Each patch is applied with `git apply`, which is exact-context but tolerates
# line offsets. `patch -p1 -F0` is the fallback, still with zero fuzz: fuzzy
# application is the dangerous failure mode here, it succeeds while landing a
# hunk in the wrong place. There is deliberately no `git apply --3way` step —
# it leaves conflict markers behind instead of failing, and the reset before
# this runs means the base is always the requested tree.
#
# A patch that does not apply stops the run unless it is listed as optional
# (or everything is), so the failure names the ref mismatch instead of the
# build failing later on a half-patched tree.
set -eu

dir=${1:-}
[ -n "$dir" ] || { echo "usage: $0 PATCH_DIR" >&2; exit 2; }
[ -d "$dir" ] || { echo "no such patch directory: $dir" >&2; exit 2; }

optional=" ${LLAMACPP_PATCH_OPTIONAL:-} "
ignore_missing=${LLAMACPP_PATCH_IGNORE_MISSING:-}

is_optional() {
    [ -n "$ignore_missing" ] && return 0
    case "$optional" in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

applied=0
skipped=""
for p in "$dir"/*.patch; do
    name=$(basename "$p")
    if git apply --check -p1 "$p" >/dev/null 2>&1; then
        git apply -p1 "$p"
    elif patch -p1 -F0 --dry-run --force <"$p" >/dev/null 2>&1; then
        patch -p1 -F0 --force <"$p" >/dev/null
    elif is_optional "$name"; then
        echo "skip $name (does not apply to this llama.cpp ref)" >&2
        skipped="$skipped $name"
        continue
    else
        echo "cannot apply $name: it was not cut for this llama.cpp ref" >&2
        echo "the tree is left half-patched; nothing was built" >&2
        exit 1
    fi
    applied=$((applied + 1))
done

echo "applied $applied/$(ls "$dir"/*.patch | wc -l)"
[ -z "$skipped" ] || echo "skipped:$skipped"
