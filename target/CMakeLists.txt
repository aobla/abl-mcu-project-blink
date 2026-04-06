# target/CMakeLists.txt
# Реализация target_init() для конкретного проекта
# Каждый проект определяет свою инициализацию платформы

# Определяем файлы в зависимости от выбранной платформы
if(PLATFORM MATCHES "^stm32.*")
    set(TARGET_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/stm32/init/stm32_target_init.c
    )
    set(TARGET_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/stm32
    )
elseif(PLATFORM STREQUAL "esp32")
    set(TARGET_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/esp32/init/esp32_target_init.c
    )
    set(TARGET_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/esp32
    )
elseif(PLATFORM STREQUAL "avr")
    set(TARGET_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/avr/init/avr_target_init.c
    )
    set(TARGET_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/avr
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
)

# Include paths для сгенерированных файлов (hardware_config.h, hardware_pins.h)
target_include_directories(target_init PRIVATE
    ${CMAKE_BINARY_DIR}/generated
)
