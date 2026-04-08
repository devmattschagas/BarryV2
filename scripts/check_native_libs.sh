#!/usr/bin/env bash
set -euo pipefail
APK_PATH="$1"
unzip -l "$APK_PATH" | rg 'lib/(arm64-v8a|armeabi-v7a)/(libzeptoclaw.so|libbarry_vad_native.so|libonnxruntime.so|libbarry_whisper_worker.so)'
