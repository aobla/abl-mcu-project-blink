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

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

string(MAKE_C_IDENTIFIER "${ABL_PRODUCT_ID}" _abl_project)
if(_abl_project STREQUAL "")
    set(_abl_project "abl_app")
endif()

project(${_abl_project})
