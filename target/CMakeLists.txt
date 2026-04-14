# target/CMakeLists.txt
# Реализация abl_target_init() для конкретного проекта
# Каждый проект определяет свою инициализацию платформы

# Определяем файлы в зависимости от выбранной платформы
if(PLATFORM MATCHES "^stm32.*")
    set(TARGET_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/stm32/stm32_target_init.c
    )
    set(TARGET_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/stm32/extra
    )
elseif(PLATFORM STREQUAL "esp32")
    set(TARGET_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/esp32/esp32_target_init.c
    )
    set(TARGET_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/esp32/extra
    )
elseif(PLATFORM STREQUAL "avr")
    set(TARGET_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/avr/avr_target_init.c
    )
    set(TARGET_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/avr/extra
    )
else()
    message(FATAL_ERROR "Unsupported platform: ${PLATFORM}")
endif()

add_library(target_init STATIC ${TARGET_SOURCES})

target_include_directories(target_init PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${TARGET_INCLUDES}
    ${platformcore_SOURCE_DIR}/target/common
    ${platformcore_SOURCE_DIR}/hal/include
    ${CMAKE_BINARY_DIR}/generated
    ${CMAKE_CURRENT_SOURCE_DIR}/../../include
)

# SDK include paths (from toolchain)
if(DEFINED STM32_INCLUDE_DIRS)
    target_include_directories(target_init PUBLIC ${STM32_INCLUDE_DIRS})
endif()

# Project HAL config (stm32f1xx_hal_conf.h, etc.)
if(DEFINED HAL_CONFIG_DIR)
    target_include_directories(target_init PUBLIC ${HAL_CONFIG_DIR})
endif()

# Platform define
target_compile_definitions(target_init PRIVATE
    PLATFORM_${PLATFORM_UPPER}
)

# Include paths для сгенерированных файлов (hardware_config.h, hardware_pins.h)
target_include_directories(target_init PRIVATE
    ${CMAKE_BINARY_DIR}/generated
)
