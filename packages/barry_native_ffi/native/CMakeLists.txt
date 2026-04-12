cmake_minimum_required(VERSION 3.10)
project(barry_native_ffi)

add_library(zeptoclaw SHARED zeptoclaw_native.c)
set_target_properties(zeptoclaw PROPERTIES OUTPUT_NAME "zeptoclaw")

add_library(barry_vad_native SHARED vad_native.c)
set_target_properties(barry_vad_native PROPERTIES OUTPUT_NAME "barry_vad_native")

add_library(barry_whisper_worker SHARED whisper_worker.c)
set_target_properties(barry_whisper_worker PROPERTIES OUTPUT_NAME "barry_whisper_worker")
