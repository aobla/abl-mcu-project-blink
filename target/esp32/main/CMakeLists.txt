# main component of the IDF project (D3):
#   - main.c            : app_main() trampoline (D7);
#   - portable src/     : the application, attached from the project root;
#   - platform sources  : HAL port, SoC bring-up and the runtime backend.
#
# IDF restricts idf_component_register(SRCS ...) to the component directory, so
# outside sources are attached with target_sources()/target_include_directories().

idf_component_register(
    SRCS "main.c"
    REQUIRES driver esp_timer esp_rom freertos
)

# IDF processes a component's CMakeLists.txt twice: first in script mode to
# collect requirements, where non-scriptable commands (add_custom_command,
# add_custom_target, target_sources) are rejected. Only the registration above
# belongs to that pass.
if(CMAKE_SCRIPT_MODE_FILE)
    return()
endif()

set(ABL_HAL_DIR "${ABL_PLATFORM_DIR}/hal")
set(ABL_SOC_DIR "${ABL_PLATFORM_DIR}/soc")
set(ABL_RT_DIR  "${ABL_PLATFORM_DIR}/runtime")
set(ABL_SCRIPTS "${ABL_PLATFORM_DIR}/scripts")
set(GEN_DIR     "${CMAKE_BINARY_DIR}/generated")

# ─── Code generation: same single entry point as the plain CMake build ───────
add_custom_command(
    OUTPUT  "${GEN_DIR}/hardware_config.h"
            "${GEN_DIR}/hardware_pins.h"
            "${GEN_DIR}/generated_gpio_init.c"
    COMMAND python3 "${ABL_SCRIPTS}/generate.py" "${BOARD_FILE}" "${APP_CONFIG}"
    DEPENDS "${BOARD_FILE}" "${APP_CONFIG}"
            "${ABL_SCRIPTS}/generate.py"
            "${ABL_SCRIPTS}/gen_config.py"
            "${ABL_SCRIPTS}/gen_pinmux.py"
            "${ABL_SCRIPTS}/abl_codegen.py"
            "${ABL_PLATFORM_DIR}/templates/hardware_config.h.jinja"
            "${ABL_PLATFORM_DIR}/templates/hardware_pins.h.jinja"
            "${ABL_PLATFORM_DIR}/templates/generated_gpio_init.c.jinja"
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
    COMMENT "Generating hardware_config.h + pinmux"
)

add_custom_target(abl_generated DEPENDS
    "${GEN_DIR}/hardware_config.h"
    "${GEN_DIR}/hardware_pins.h"
    "${GEN_DIR}/generated_gpio_init.c"
)

target_sources(${COMPONENT_LIB} PRIVATE
    "${ABL_PROJECT_DIR}/src/main.c"
    "${GEN_DIR}/generated_gpio_init.c"
    "${ABL_HAL_DIR}/src/esp32/gpio_esp32.c"
    "${ABL_HAL_DIR}/src/esp32/delay_esp32.c"
    "${ABL_HAL_DIR}/src/esp32/time_esp32.c"
    "${ABL_HAL_DIR}/src/esp32/critical_esp32.c"
    "${ABL_SOC_DIR}/esp32/esp32_target_init.c"
    "${ABL_RT_DIR}/src/${ABL_RUNTIME}/runtime_${ABL_RUNTIME}.c"
)

target_include_directories(${COMPONENT_LIB} PRIVATE
    "${ABL_PROJECT_DIR}/include"
    "${GEN_DIR}"
    "${ABL_HAL_DIR}/include"
    "${ABL_SOC_DIR}/include"
    "${ABL_SOC_DIR}/esp32"
    "${ABL_RT_DIR}/include"
)

add_dependencies(${COMPONENT_LIB} abl_generated)
