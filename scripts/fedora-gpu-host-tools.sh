#!/usr/bin/env bash
# Opt-in Fedora Mesa host-tool build wrapper; changes only local build state.
set -euo pipefail

if (( $# == 0 )); then
    printf 'Usage: %s cargo xtask gpu nvk --jobs 4\n' "$0" >&2
    exit 2
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
mesa="$root/third_party/mesa"
patch="$root/patches/fedora/mesa-clang-resource-dir.patch"

if [[ ! -d "$mesa/.git" && ! -f "$mesa/.git" ]]; then
    echo 'Mesa submodule is not initialized; refusing to modify it.' >&2
    exit 1
fi
if [[ -n "$(git -C "$mesa" status --porcelain)" ]]; then
    echo 'Mesa submodule has local changes; refusing to overwrite them.' >&2
    exit 1
fi
if [[ ! -f "$patch" ]]; then
    echo "Missing compatibility patch: $patch" >&2
    exit 1
fi

pkgconf="$(find "$root/.tools/gpu/generators/lib" -type f -path '*/pkgconf/.bin/pkgconf' -print -quit 2>/dev/null || true)"
if [[ -z "$pkgconf" || ! -x "$pkgconf" ]]; then
    echo 'Bundled pkgconf not found. First install the Stela GPU generator tools.' >&2
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    echo 'Clang is required.' >&2
    exit 1
fi
clang_resource="$(clang -print-resource-dir)"
if [[ ! -f "$clang_resource/include/opencl-c-base.h" || ! -f "$clang_resource/include/opencl-c.h" ]]; then
    echo 'Clang OpenCL headers were not found in its resource directory.' >&2
    exit 1
fi

shim_dir="$root/.tools/fedora-gpu-host-tools/bin"
mkdir -p -- "$shim_dir"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$pkgconf" > "$shim_dir/pkg-config"
chmod 755 -- "$shim_dir/pkg-config"

export PATH="$shim_dir:$PATH"
export PKG_CONFIG_LIBDIR='/usr/lib64/pkgconfig:/usr/share/pkgconfig'
"$shim_dir/pkg-config" --exists libdrm LLVMSPIRVLib

git -C "$mesa" apply --check "$patch"
applied=0
cleanup() {
    status=$?
    trap - EXIT
    if (( applied )); then
        if ! git -C "$mesa" apply --reverse --check "$patch"; then
            echo 'ERROR: Mesa patch could not be reversed; inspect git status before proceeding.' >&2
            exit 1
        fi
        git -C "$mesa" apply --reverse "$patch"
        echo 'Mesa source restored.'
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

git -C "$mesa" apply "$patch"
applied=1
cd -- "$root"
"$@"
