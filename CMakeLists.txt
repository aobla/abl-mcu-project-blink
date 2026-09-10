cmake_minimum_required(VERSION 3.20)

# ─── Project name (from CLI or default) ──────────────────────────────────────
if(DEFINED PROJECT_NAME)
    set(_PROJECT_NAME "${PROJECT_NAME}")
else()
    set(_PROJECT_NAME "abl-mcu-project")
endif()

# ─── Resolve platform-core path BEFORE project() ─────────────────────────────
if(DEFINED ENV{ABL_DEPS_PATH} AND EXISTS "$ENV{ABL_DEPS_PATH}/abl-mcu-platform/CMakeLists.txt")
    set(_PCORE_DIR "$ENV{ABL_DEPS_PATH}/abl-mcu-platform")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform/CMakeLists.txt")
    set(_PCORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform/CMakeLists.txt")
    set(_PCORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform")
else()
    set(_PCORE_DIR "")
endif()

# ─── Include toolchain BEFORE project() ──────────────────────────────────────
if(DEFINED PLATFORM)
    if(PLATFORM MATCHES "^stm32f1")
        set(STM32_MCU "cortex-m3")
        set(STM32_FPU "")
        set(STM32_FLOAT_ABI "soft")
    elseif(PLATFORM MATCHES "^stm32f4")
        set(STM32_MCU "cortex-m4")
        set(STM32_FPU "fpv4-sp-d16")
        set(STM32_FLOAT_ABI "hard")
    elseif(PLATFORM MATCHES "^stm32h7")
        set(STM32_MCU "cortex-m7")
        set(STM32_FPU "fpv5-sp-d16")
        set(STM32_FLOAT_ABI "hard")
    endif()

    if(PLATFORM MATCHES "^stm32")
        set(CMAKE_TOOLCHAIN_FILE "${_PCORE_DIR}/cmake/toolchains/stm32-gcc.cmake")
        set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
    elseif(PLATFORM STREQUAL "esp32")
        set(CMAKE_TOOLCHAIN_FILE "${_PCORE_DIR}/cmake/toolchains/esp32-clang.cmake")
        set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
    elseif(PLATFORM STREQUAL "avr")
        set(AVR_MCU "atmega328p")
        set(CMAKE_TOOLCHAIN_FILE "${_PCORE_DIR}/cmake/toolchains/avr-gcc.cmake")
        set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
    endif()
endif()

project(${_PROJECT_NAME} C CXX ASM)

# ─── Platform define — MUST be before add_subdirectory(platformcore) ──────────
string(TOUPPER "${PLATFORM}" PLATFORM_UPPER)
add_compile_definitions(PLATFORM_${PLATFORM_UPPER})

# STM32 HAL конфигурируется SoC (hal_conf живёт в soc/); define нужен по всему
# проекту, т.к. app.h подтягивает vendor-заголовки ради макросов пинов.
add_compile_definitions(USE_HAL_DRIVER)

# ─── Resolve platform-core ───────────────────────────────────────────────────
# Priority 1: ABL_DEPS_PATH
# Priority 2: project/lib/abl-mcu-platform/
# Priority 3: FetchContent from git (fallback for CI / fresh clone)

if(DEFINED ENV{ABL_DEPS_PATH} AND EXISTS "$ENV{ABL_DEPS_PATH}/abl-mcu-platform/CMakeLists.txt")
    set(platformcore_SOURCE_DIR "$ENV{ABL_DEPS_PATH}/abl-mcu-platform")
    add_subdirectory(${platformcore_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/platformcore-build)
    message(STATUS "Using platform-core from ABL_DEPS_PATH: ${platformcore_SOURCE_DIR}")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform/CMakeLists.txt")
    # Development: sibling directory
    set(platformcore_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform")
    add_subdirectory(${platformcore_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/platformcore-build)
    message(STATUS "Using sibling platform-core: ${platformcore_SOURCE_DIR}")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform/CMakeLists.txt")
    set(platformcore_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform")
    add_subdirectory(${platformcore_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/platformcore-build)
    message(STATUS "Using local platform-core: ${platformcore_SOURCE_DIR}")
else()
    # FetchContent fallback
    message(STATUS "Local platform-core not found — fetching from git")
    include(FetchContent)
    FetchContent_Declare(
        platformcore
        GIT_REPOSITORY https://github.com/aobla/abl-mcu-platform.git
        GIT_TAG main
    )
    FetchContent_MakeAvailable(platformcore)
endif()

# Проверка версии platform-core
if(DEFINED platformcore_VERSION)
    if(platformcore_VERSION VERSION_LESS "1.0.0")
        message(FATAL_ERROR "abl-mcu-project-blink requires platform-core >= v1.0.0, got ${platformcore_VERSION}")
    endif()
else()
    message(WARNING "platform-core version not detected, assuming v1.0.0")
endif()

# ─── Config file (platform hardware config, passed from build.sh) ────────────
if(DEFINED CONFIG_FILE AND EXISTS "${CONFIG_FILE}")
    set(PLATFORM_CONFIG "${CONFIG_FILE}")
else()
    message(FATAL_ERROR "CONFIG_FILE not set or not found. Pass via -DCONFIG_FILE=... or use build.sh")
endif()

# ─── Generated files — custom target so target_init can depend on them ────────
set(GEN_DIR ${CMAKE_BINARY_DIR}/generated)
file(MAKE_DIRECTORY ${GEN_DIR})

# Generate hardware_config.h
add_custom_command(
    OUTPUT ${GEN_DIR}/hardware_config.h
    COMMAND python3 ${platformcore_SOURCE_DIR}/scripts/gen_config_v1.0.py ${PLATFORM_CONFIG}
    DEPENDS ${PLATFORM_CONFIG}
            ${platformcore_SOURCE_DIR}/scripts/gen_config_v1.0.py
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Generating hardware_config.h"
)

# Generate pinmux (hardware_pins.h + generated_gpio_init.c)
add_custom_command(
    OUTPUT ${GEN_DIR}/hardware_pins.h ${GEN_DIR}/generated_gpio_init.c
    COMMAND python3 ${platformcore_SOURCE_DIR}/scripts/gen_pinmux_v1.0.py ${PLATFORM_CONFIG}
    DEPENDS ${PLATFORM_CONFIG}
            ${platformcore_SOURCE_DIR}/scripts/gen_pinmux_v1.0.py
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Generating pinmux"
)

# Custom target to trigger generation
add_custom_target(generated_files DEPENDS
    ${GEN_DIR}/hardware_config.h
    ${GEN_DIR}/hardware_pins.h
    ${GEN_DIR}/generated_gpio_init.c
)

# ─── Output name (from CLI or default) ───────────────────────────────────────
if(DEFINED OUTPUT_NAME AND NOT OUTPUT_NAME STREQUAL "")
    set(_OUTPUT_NAME "${OUTPUT_NAME}")
else()
    set(_OUTPUT_NAME "blink_led")
endif()

# 3. Создаём прошивку
add_firmware_target(
    NAME ${_OUTPUT_NAME}
    PLATFORM ${PLATFORM}
    CONFIG ${PLATFORM_CONFIG}
    SOURCES src/main.c
)

# Проектный include/ (app.h и т.п.) виден прошивке
target_include_directories(${_OUTPUT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)

# ─── Post-build: generate .bin and .hex ──────────────────────────────────────
set(OUTPUT_DIR ${CMAKE_BINARY_DIR}/release)
file(MAKE_DIRECTORY ${OUTPUT_DIR})

# .bin
add_custom_command(TARGET ${_OUTPUT_NAME} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${_OUTPUT_NAME}> ${OUTPUT_DIR}/${_OUTPUT_NAME}.bin
    COMMENT "Generating binary image..."
)

# .hex
add_custom_command(TARGET ${_OUTPUT_NAME} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${_OUTPUT_NAME}> ${OUTPUT_DIR}/${_OUTPUT_NAME}.hex
    COMMENT "Generating hex image..."
)

# .elf (copy with platform name)
add_custom_command(TARGET ${_OUTPUT_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${_OUTPUT_NAME}> ${OUTPUT_DIR}/${_OUTPUT_NAME}.elf
    COMMENT "Copying ELF file..."
)

# Print summary
add_custom_command(TARGET ${_OUTPUT_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E echo "─────────────────────────────────────────────────────────────────────"
    COMMAND ${CMAKE_COMMAND} -E echo "  Firmware images generated in: build/${PLATFORM}/release/"
    COMMAND ${CMAKE_COMMAND} -E echo "    ${_OUTPUT_NAME}.elf  — debug symbol file"
    COMMAND ${CMAKE_COMMAND} -E echo "    ${_OUTPUT_NAME}.bin  — raw binary for flashing"
    COMMAND ${CMAKE_COMMAND} -E echo "    ${_OUTPUT_NAME}.hex  — Intel HEX for programmers"
    COMMAND ${CMAKE_COMMAND} -E echo "─────────────────────────────────────────────────────────────────────"

)