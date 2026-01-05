#!/bin/sh
set -euo pipefail

# Copies the SwiftPM-produced llama.framework into the app bundle's Frameworks
# folder (iOS/visionOS/macOS), so dyld can resolve @rpath/llama.framework/llama.

src_package_frameworks="${BUILT_PRODUCTS_DIR:-}/PackageFrameworks/llama.framework"
src_built_products="${BUILT_PRODUCTS_DIR:-}/llama.framework"

src=""
if [ -d "${src_package_frameworks}" ]; then
  src="${src_package_frameworks}"
elif [ -d "${src_built_products}" ]; then
  src="${src_built_products}"
fi

dst_dir="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-Contents/Frameworks}"
dst="${dst_dir}/llama.framework"

if [ -z "${src}" ]; then
  echo "embed-llama: source not found (SwiftPM may not have produced it yet)"
  exit 0
fi

echo "embed-llama: copying ${src} -> ${dst}"
mkdir -p "${dst_dir}"

# Preserve structure/symlinks for proper code signing
rsync -a --delete "${src}/" "${dst}/"

if [ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]; then
  mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
  touch "${SCRIPT_OUTPUT_FILE_0}"
fi

exit 0
