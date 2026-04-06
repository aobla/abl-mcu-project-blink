cmake_minimum_required(VERSION 3.20)
project(abl-mcu-project-blink)

# 1. Platform Core
include(FetchContent)
FetchContent_Declare(
    platformcore
    GIT_REPOSITORY https://github.com/myorg/abl-mcu-platform-core.git
    GIT_TAG v1.0.0
)
FetchContent_MakeAvailable(platformcore)

# Проверка версии platform-core
if(DEFINED platformcore_VERSION)
    if(platformcore_VERSION VERSION_LESS "1.0.0")
        message(FATAL_ERROR "abl-mcu-project-blink requires platform-core >= v1.0.0, got ${platformcore_VERSION}")
    endif()
else()
    message(WARNING "platform-core version not detected, assuming v1.0.0")
endif()

# 2. Target init — реализация проекта (тактирование, GPIO, периферия)
add_subdirectory(target)

# 3. Создаём прошивку
include(${platformcore_SOURCE_DIR}/cmake/helpers/target_helpers.cmake)

# Определяем конфигурацию и пинмап в зависимости от выбранной платформы
if(PLATFORM MATCHES "^stm32.*")
    # Если указана конкретная модель STM32
    if(PLATFORM STREQUAL "stm32")
        # По умолчанию используем STM32F4
        set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_config.yml)
        set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_pinmux.yml)
    else()
        # Используем указанную модель STM32
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
    # По умолчанию используем STM32F4
    set(CONFIG_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_config.yml)
    set(PINMUX_FILE ${CMAKE_CURRENT_SOURCE_DIR}/config/stm32f4_board_pinmux.yml)
endif()

add_firmware_target(
    NAME blink_led
    PLATFORM ${PLATFORM}
    CONFIG ${CONFIG_FILE}
    PINMUX ${PINMUX_FILE}
    SOURCES src/main.c
)