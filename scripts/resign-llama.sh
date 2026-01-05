#!/bin/sh
set -euo pipefail

if [ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ]; then
  echo "Skipping llama.framework re-sign because CODE_SIGNING_ALLOWED != YES"
  exit 0
fi

identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
if [ -z "$identity" ] || [ "$identity" = "<CODE_SIGN_IDENTITY>" ]; then
  identity="-"
fi

resign() {
  framework_path="$1"

  if [ -z "$framework_path" ]; then
    return 0
  fi

  if [ ! -d "$framework_path" ]; then
    # Nothing to do if the framework directory hasn't been produced yet.
    return 0
  fi

  if [ ! -r "$framework_path" ]; then
    echo "Skipping $(basename "$framework_path") because it is not readable inside the build sandbox"
    return 0
  fi

  if [ ! -w "$framework_path" ]; then
    if ! chmod -R u+w "$framework_path" 2>/dev/null; then
      echo "Skipping $(basename "$framework_path") because the build sandbox denied write access"
      return 0
    fi
  fi

  echo "Re-signing $(basename "$framework_path") at $framework_path"
  if ! /usr/bin/codesign --force --sign "$identity" --timestamp=none "$framework_path"; then
    status=$?
    echo "Warning: codesign returned status $status for $framework_path; leaving the existing signature"
    return $status
  fi
}

resign "${BUILT_PRODUCTS_DIR:-}/llama.framework"

if [ -n "${BUILT_PRODUCTS_DIR:-}" ]; then
  resign "${BUILT_PRODUCTS_DIR}/PackageFrameworks/llama.framework"
fi

if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
  resign "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/llama.framework"
fi

if [ -n "${CODESIGNING_FOLDER_PATH:-}" ]; then
  resign "${CODESIGNING_FOLDER_PATH}/Frameworks/llama.framework"
fi

if [ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]; then
  mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
  touch "${SCRIPT_OUTPUT_FILE_0}"
fi

exit 0
