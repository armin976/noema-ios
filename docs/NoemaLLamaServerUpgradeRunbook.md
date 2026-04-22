# NoemaLLamaServer Upgrade Runbook

This document explains how to upgrade `Noema/External/NoemaLLamaServer` to a new `llama.cpp` release while preserving Noema-specific behavior.

## Scope

- Update the vendored upstream source used by the SwiftPM package in `External/NoemaLLamaServer`.
- Keep Noema bridge APIs stable for the app.
- Keep both `arm64` and `x86_64` debug SwiftPM builds passing.
- Update app-facing build label in settings (`Noema/Noema/SettingsView.swift`) to the new `b####`.

## Prerequisites

- You are on a branch in the parent repo (`Noema`) and submodule (`External/NoemaLLamaServer`).
- Xcode command line tools installed.
- `swift`, `git`, and `xxd` available.
- Release source for target `llama.cpp` version (tarball or local checkout).

## Upgrade Steps

### 1) Replace vendored upstream source

In `External/NoemaLLamaServer/Sources/NoemaLLamaServer/upstream`, replace these subtrees from the target release:

- `common`
- `ggml`
- `include`
- `src`
- `tools`
- `vendor`

Do a full replacement of those folders.

### 2) Regenerate server asset headers required by SwiftPM

From `External/NoemaLLamaServer`:

```bash
xxd -i -n index_html_gz Sources/NoemaLLamaServer/upstream/tools/server/public/index.html.gz \
  > Sources/NoemaLLamaServer/upstream/tools/server/index.html.gz.hpp

xxd -i -n loading_html Sources/NoemaLLamaServer/upstream/tools/server/public/loading.html \
  > Sources/NoemaLLamaServer/upstream/tools/server/loading.html.hpp
```

### 3) Update version macros and excludes in `Package.swift`

Update both `cSettings` and `cxxSettings`:

- `GGML_VERSION` to target release version string (example: `"0.9.7"`).
- `GGML_COMMIT` to target build tag (example: `"b8192"`).

Review `exclude` entries:

- Add new `tools/*` folders that produce extra `main` binaries and break SwiftPM linking.
- Add new backend folders not needed by this package (example: `upstream/ggml/src/ggml-virtgpu`).
- Remove stale excludes for deleted files.

### 4) Re-apply Noema server bridge patches

Patch `upstream/tools/server/server.cpp`:

- Keep `shutdown_handler` externally visible (not `static`) for `bridge/server_bridge.mm`.
- Keep these bridge callbacks declared and used:
  - `noema_llama_server_report_load_progress(float)`
  - `noema_llama_server_report_http_ready(void)`
- Wire `params.load_progress_callback` around model load.
- Report `load_progress` at start (`0.0`) and completion (`1.0`).
- Report HTTP ready in router mode after server starts listening.

Patch `upstream/tools/server/server-context.cpp`:

- Declare `noema_llama_server_report_http_ready`.
- Add `has_reported_http_ready` state.
- Reset it when loading a model.
- Trigger callback once when all slots become idle after load.

### 5) Keep mtmd compatibility rename

Patch `upstream/tools/mtmd/mtmd-audio.cpp`:

- Rename local `DEBUG` constant to `MTMD_AUDIO_DEBUG` (or similar) to avoid collision with SwiftPM debug macro defines.

### 6) Guard cross-arch SIMD files for SwiftPM compile-all behavior

Add whole-file architecture guards:

- x86-only:
  - `upstream/ggml/src/ggml-cpu/arch/x86/repack.cpp`
  - `upstream/ggml/src/ggml-cpu/arch/x86/quants.c`
- arm-only:
  - `upstream/ggml/src/ggml-cpu/arch/arm/repack.cpp`
  - `upstream/ggml/src/ggml-cpu/arch/arm/quants.c`

Important: place the closing `#endif` at end-of-file.

### 7) Regenerate `bridge/ggml_metal_embed.cpp`

Recreate embedded metal source using upstream merge logic:

1. Insert `ggml-common.h` into `ggml-metal.metal` at `__embed_ggml-common.h__`.
2. Inline `ggml-metal-impl.h` where included.
3. Apply Noema workaround:
   - Replace `ushort tiitg[[thread_index_in_threadgroup]]` with `uint ...`.
4. Emit symbols:
   - `ggml_metallib_start`
   - `ggml_metallib_end`
   - `ggml_metallib_len`

Keep `ggml-metal-device.m` declaration in sync with emitted symbol type for `ggml_metallib_end`.

### 8) Build verification

Run from `External/NoemaLLamaServer`:

```bash
swift build -c debug
swift build -c debug --arch x86_64
```

Expected:

- Builds complete successfully for both arches.
- Warnings may appear, but no unresolved symbols and no duplicate `main` link failures.

Optional symbol sanity check:

```bash
nm -a .build/arm64-apple-macosx/debug/libNoemaLLamaServer.dylib | rg "shutdown_handler|ggml_metallib_(start|end|len)"
nm -a .build/x86_64-apple-macosx/debug/libNoemaLLamaServer.dylib | rg "shutdown_handler|ggml_metallib_(start|end|len)"
```

### 9) Update app-visible build label

In `Noema/Noema/SettingsView.swift`, set:

- `llamaCppBuild` to the new `b####` (example: `b8192`).

### 10) Commit flow

- Commit submodule changes inside `External/NoemaLLamaServer`.
- Then, from parent repo, stage updated submodule pointer.
- Keep unrelated local changes untouched.

## Quick Checklist

- [ ] Upstream folders replaced (`common`, `ggml`, `include`, `src`, `tools`, `vendor`)
- [ ] `index.html.gz.hpp` and `loading.html.hpp` regenerated
- [ ] `Package.swift` version defines and excludes updated
- [ ] Noema callbacks and `shutdown_handler` patch reapplied
- [ ] `mtmd-audio.cpp` `DEBUG` rename applied
- [ ] x86/arm arch guards applied to four CPU arch files
- [ ] `ggml_metal_embed.cpp` regenerated with `start/end/len` and thread-index workaround
- [ ] `swift build -c debug` passes
- [ ] `swift build -c debug --arch x86_64` passes
- [ ] Settings screen build label updated to new `b####`
