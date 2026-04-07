cmake_minimum_required(VERSION 3.20)

# ─── Resolve platform-core path BEFORE project() ─────────────────────────────
if(DEFINED ENV{ABL_DEPS_PATH} AND EXISTS "$ENV{ABL_DEPS_PATH}/abl-mcu-platform-core/CMakeLists.txt")
    set(_PCORE_DIR "$ENV{ABL_DEPS_PATH}/abl-mcu-platform-core")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform-core/CMakeLists.txt")
    set(_PCORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform-core")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform-core/CMakeLists.txt")
    set(_PCORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform-core")
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

project(abl-mcu-project-blink)

# ─── Platform define — MUST be before add_subdirectory(platformcore) ──────────
string(TOUPPER "${PLATFORM}" PLATFORM_UPPER)
add_compile_definitions(PLATFORM_${PLATFORM_UPPER})

# ─── HAL config headers (project-specific) ───────────────────────────────────
# These live in project's config/ and must be available to HAL sources
if(PLATFORM MATCHES "^stm32f1")
    add_compile_definitions(USE_HAL_DRIVER)
    set(HAL_CONFIG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/config)
elseif(PLATFORM MATCHES "^stm32f4")
    add_compile_definitions(USE_HAL_DRIVER)
    set(HAL_CONFIG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/config)
elseif(PLATFORM MATCHES "^stm32h7")
    add_compile_definitions(USE_HAL_DRIVER)
    set(HAL_CONFIG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/config)
endif()

# ─── Resolve platform-core ───────────────────────────────────────────────────
# Priority 1: ABL_DEPS_PATH
# Priority 2: project/lib/abl-mcu-platform-core/
# Priority 3: FetchContent from git (fallback for CI / fresh clone)

if(DEFINED ENV{ABL_DEPS_PATH} AND EXISTS "$ENV{ABL_DEPS_PATH}/abl-mcu-platform-core/CMakeLists.txt")
    set(platformcore_SOURCE_DIR "$ENV{ABL_DEPS_PATH}/abl-mcu-platform-core")
    add_subdirectory(${platformcore_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/platformcore-build)
    message(STATUS "Using platform-core from ABL_DEPS_PATH: ${platformcore_SOURCE_DIR}")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform-core/CMakeLists.txt")
    # Development: sibling directory
    set(platformcore_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../abl-mcu-platform-core")
    add_subdirectory(${platformcore_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/platformcore-build)
    message(STATUS "Using sibling platform-core: ${platformcore_SOURCE_DIR}")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform-core/CMakeLists.txt")
    set(platformcore_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/abl-mcu-platform-core")
    add_subdirectory(${platformcore_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/platformcore-build)
    message(STATUS "Using local platform-core: ${platformcore_SOURCE_DIR}")
else()
    # FetchContent fallback
    message(STATUS "Local platform-core not found — fetching from git")
    include(FetchContent)
    FetchContent_Declare(
        platformcore
        GIT_REPOSITORY https://github.com/aobla/abl-mcu-platform-core.git
        GIT_TAG main
    )
    FetchContent_MakeAvailable(platformcore)
endif()

# Add project HAL config directory to HAL library includes
if(DEFINED HAL_CONFIG_DIR AND TARGET hal_stm32)
    target_include_directories(hal_stm32 PUBLIC ${HAL_CONFIG_DIR})
endif()
if(DEFINED HAL_CONFIG_DIR AND TARGET target_init)
    target_include_directories(target_init PUBLIC ${HAL_CONFIG_DIR})
endif()
if(DEFINED HAL_CONFIG_DIR AND TARGET blink_led)
    target_include_directories(blink_led PUBLIC ${HAL_CONFIG_DIR})
endif()

# Проверка версии platform-core
if(DEFINED platformcore_VERSION)
    if(platformcore_VERSION VERSION_LESS "1.0.0")
        message(FATAL_ERROR "abl-mcu-project-blink requires platform-core >= v1.0.0, got ${platformcore_VERSION}")
    endif()
else()
    message(WARNING "platform-core version not detected, assuming v1.0.0")
endif()

# ─── Generated files — custom target so target_init can depend on them ────────
set(GEN_DIR ${CMAKE_BINARY_DIR}/generated)
file(MAKE_DIRECTORY ${GEN_DIR})

# Determine config files
if(PLATFORM MATCHES "^stm32.*")
    if(PLATFORM STREQUAL "stm32")
        set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_config.yml)
        set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_pinmux.yml)
    else()
        set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/${PLATFORM}_board_config.yml)
        set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/${PLATFORM}_board_pinmux.yml)
    endif()
elseif(PLATFORM STREQUAL "esp32")
    set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/esp32_board_config.yml)
    set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/esp32_board_pinmux.yml)
elseif(PLATFORM STREQUAL "avr")
    set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/avr_board_config.yml)
    set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/avr_board_pinmux.yml)
else()
    set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_config.yml)
    set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_pinmux.yml)
endif()

# Generate hardware_config.h
add_custom_command(
    OUTPUT ${GEN_DIR}/hardware_config.h
    COMMAND python3 ${platformcore_SOURCE_DIR}/scripts/gen_config_v1.0.py ${CONFIG_FILE}
    DEPENDS ${CONFIG_FILE}
            ${platformcore_SOURCE_DIR}/scripts/gen_config_v1.0.py
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Generating hardware_config.h"
)

# Generate pinmux (hardware_pins.h + generated_gpio_init.c)
add_custom_command(
    OUTPUT ${GEN_DIR}/hardware_pins.h ${GEN_DIR}/generated_gpio_init.c
    COMMAND python3 ${platformcore_SOURCE_DIR}/scripts/gen_pinmux_v1.0.py ${PINMUX_FILE}
    DEPENDS ${PINMUX_FILE}
            ${platformcore_SOURCE_DIR}/scripts/gen_pinmux_v1.0.py
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Generating pinmux"
)

# Generate linker script
if(EXISTS ${platformcore_SOURCE_DIR}/templates/linker_script.ld.jinja)
    add_custom_command(
        OUTPUT ${GEN_DIR}/linker_script.ld
        COMMAND python3 ${platformcore_SOURCE_DIR}/scripts/gen_linker_v1.0.py ${CONFIG_FILE}
        DEPENDS ${CONFIG_FILE}
                ${platformcore_SOURCE_DIR}/scripts/gen_linker_v1.0.py
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Generating linker script"
    )
endif()

# Custom target to trigger generation
add_custom_target(generated_files DEPENDS
    ${GEN_DIR}/hardware_config.h
    ${GEN_DIR}/hardware_pins.h
    ${GEN_DIR}/generated_gpio_init.c
    ${GEN_DIR}/linker_script.ld
)

# 2. Target init — реализация проекта (тактирование, GPIO, периферия)
add_subdirectory(target)
add_dependencies(target_init generated_files)

# 3. Создаём прошивку
add_firmware_target(
    NAME blink_led
    PLATFORM ${PLATFORM}
    CONFIG ${CONFIG_FILE}
    PINMUX ${PINMUX_FILE}
    SOURCES src/main.c
)