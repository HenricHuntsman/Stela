# Fedora Mesa host-tool compatibility (experimental)

This is an opt-in, project-local workaround for the Mesa source pinned by Stela on Fedora 45. It is **not** part of the default build and does not enable macOS boot or GPU execution by itself.

## Verified local evidence (18 November 2026)

Against Stela `fd1a646f7` with Fedora 45, LLVM/Clang 23.1.5, SPIRV-LLVM-Translator 23.1.0.0, libdrm 2.4.134 and SPIRV-Tools 2026.2:

- Mesa configuration succeeded after correcting Clang's bundled OpenCL header lookup and Fedora's pkg-config data search path.
- `mesa_clc` and `vtn_bindgen2` each compiled and linked in a standalone `.tools/fedora-pkgconfig/clang-probe-*` directory.
- `mesa_clc` compiled the `dragonhub_test` OpenCL kernel to SPIR-V 1.0; `spirv-val --target-env spv1.0` exited 0.
- Git worktrees were clean after each temporary source edit.

The outcomes above are from an *isolated host-tool probe*, not a clean build through `cargo xtask gpu nvk` or a GPU runtime test. They have not yet been repeated on the updated upstream-based revision.

## Why the wrapper is needed

Fedora's `pkg-config` wrapper may invoke `rpm`, which is unavailable under Stela's restricted build PATH; the bundled `pkgconf` executable has a `/usr/local`-only default package search path and needs `PKG_CONFIG_LIBDIR=/usr/lib64/pkgconfig:/usr/share/pkgconfig`. Pinned Mesa constructs its Clang resource-header path from `llvm-config --libdir`, whereas Fedora puts OpenCL headers under `clang -print-resource-dir`.

The `scripts/fedora-gpu-host-tools.sh` wrapper:

1. Refuses to run if the Mesa submodule contains changes.
2. Locates the already-installed bundled `pkgconf`, and checks Clang's headers and the necessary .pc packages.
3. Creates a shim beneath the ignored `.tools` tree.
4. Applies `patches/fedora/mesa-clang-resource-dir.patch` temporarily, runs the specified command, then reverses the patch at exit.

No `sudo` or system-wide installation is performed. A hard kill or crash can prevent automatic cleanup; inspect `git -C third_party/mesa status --short` before retrying.

## Usage (after updating your local checkout to the feature branch)

    cd ~/Stela
    bash scripts/fedora-gpu-host-tools.sh cargo xtask gpu nvk --jobs 4

This may be a substantial GPU build. The wrapper has passed shell syntax validation, but its full Stela integration remains **unverified** until a Fedora run confirms it. Do not merge this draft just because unrelated CI jobs pass.

Inspect the result:

    git status --short --branch
    git -C third_party/mesa status --short
    find target/gpu/clc/build/src/compiler -type f \( -name mesa_clc -o -name vtn_bindgen2 \) -print

If the build fails, retain `target/gpu/clc/meson-log.txt` or `ninja-log.txt` and report the first error. Do not reset/clean submodules or remove existing binaries merely to retry.
