#!/bin/sh
# Apply a numbered llama.cpp patch set (the P100 one by default) to the checkout
# in $PWD, in filename order.
#
#   apply-patches.sh [PATCH_DIR]
#
# Environment:
#   LLAMACPP_PATCH_OPTIONAL       space-separated basenames allowed to not apply
#   LLAMACPP_PATCH_IGNORE_MISSING non-empty: every patch is optional
#
# No fuzzy application and no `git apply --3way`: both succeed while landing a
# hunk in the wrong place, and a patch that does not apply has to stop the run
# (unless it is listed as optional) so the failure names the ref mismatch.
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
