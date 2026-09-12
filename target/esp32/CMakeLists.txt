# ESP-IDF project wrapper (D3).
#
# The IDF build system wants its own project root, so this directory is the IDF
# project while the rest of the repository stays a plain CMake project. The
# portable application (src/) and the platform repo are attached from main/.
#
# Build:  ./build.sh -C config/blink_esp32.yml     (delegates to idf.py)
# Manual: idf.py -C target/esp32 -DABL_PLATFORM_DIR=... -DAPP_CONFIG=... build

cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED ABL_PLATFORM_DIR OR NOT EXISTS "${ABL_PLATFORM_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "ABL_PLATFORM_DIR is not set or invalid (path to abl-mcu-platform)")
endif()
if(NOT DEFINED APP_CONFIG OR NOT EXISTS "${APP_CONFIG}")
    message(FATAL_ERROR "APP_CONFIG is not set or invalid (app config)")
endif()
if(NOT DEFINED BOARD_FILE OR NOT EXISTS "${BOARD_FILE}")
    message(FATAL_ERROR "BOARD_FILE is not set or invalid (board definition)")
endif()
if(NOT DEFINED ABL_RUNTIME OR ABL_RUNTIME STREQUAL "")
    set(ABL_RUNTIME "freertos")
endif()

# ─── Target chip (IDF_TARGET) ────────────────────────────────────────────────
# The chip is a property of the board (ESP32 vs ESP32-C3 vs ESP32-S3 are different
# architectures with different toolchains), so it comes from the board config as
# -DIDF_TARGET. Setting it before including project.cmake makes idf.py select the
# right toolchain and soc component.
if(NOT DEFINED IDF_TARGET OR IDF_TARGET STREQUAL "")
    message(FATAL_ERROR "IDF_TARGET is not set (idf_target in the board config). "
                        "Pass it as -DIDF_TARGET=esp32c3, or use ./build.sh")
endif()
set(IDF_TARGET "${IDF_TARGET}" CACHE STRING "ESP-IDF target chip" FORCE)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

string(MAKE_C_IDENTIFIER "${ABL_PRODUCT_ID}" _abl_project)
if(_abl_project STREQUAL "")
    set(_abl_project "abl_app")
endif()

project(${_abl_project})
