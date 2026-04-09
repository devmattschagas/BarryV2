#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:?Usage: $0 <apk_path>}"

required_libs=(
  "libzeptoclaw.so"
  "libbarry_vad_native.so"
  "libonnxruntime.so"
  "libbarry_whisper_worker.so"
)
abis=("arm64-v8a" "armeabi-v7a")

for abi in "${abis[@]}"; do
  for lib in "${required_libs[@]}"; do
    apk_entry="lib/${abi}/${lib}"

    if ! unzip -l "$APK_PATH" | grep -q "$apk_entry"; then
      echo "Missing native library in APK: $apk_entry" >&2
      exit 1
    fi

    magic_hex=$(unzip -p "$APK_PATH" "$apk_entry" | head -c 4 | od -An -t x1 | tr -d ' \n')
    if [[ "$magic_hex" != "7f454c46" ]]; then
      echo "Invalid ELF header for $apk_entry (magic=$magic_hex)" >&2
      exit 1
    fi
  done
done

echo "Native libraries validated in $APK_PATH"
