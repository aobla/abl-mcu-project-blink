#!/bin/bash

# Скрипт для упрощенной сборки проекта под различные платформы

set -e  # Выход при ошибке

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_BASE_DIR="${SCRIPT_DIR}/build"
TOOLCHAIN_BASE_DIR="$HOME/.local/share/abl-mcu-toolchains"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# ─── Dependency check ────────────────────────────────────────────────────────

# Resolve platform repository (ABL_DEPS_PATH → lib/ → sibling для разработки)
resolve_platform_dir() {
    if [[ -n "$ABL_DEPS_PATH" && -d "$ABL_DEPS_PATH/abl-mcu-platform" ]]; then
        echo "$ABL_DEPS_PATH/abl-mcu-platform"
    elif [[ -d "$SCRIPT_DIR/lib/abl-mcu-platform" ]]; then
        echo "$SCRIPT_DIR/lib/abl-mcu-platform"
    elif [[ -d "$SCRIPT_DIR/../abl-mcu-platform" ]]; then
        echo "$SCRIPT_DIR/../abl-mcu-platform"
    else
        echo ""
    fi
}

check_git_deps() {
    local core_path
    core_path=$(resolve_platform_dir)
    if [[ -n "$core_path" ]]; then
        log_ok "Platform dependency found: abl-mcu-platform at $core_path"
        return 0
    fi
    return 1
}

# Map platform name to toolchain binary and search paths
get_toolchain_info() {
    local platform="$1"
    case "$platform" in
        stm32f*|stm32h*)
            echo "arm-none-eabi-gcc"
            echo "arm-none-eabi"
            ;;
        avr)
            echo "avr-gcc"
            echo "avr"
            ;;
        esp32)
            echo "xtensa-esp32-elf-gcc"
            echo "esp-idf"
            ;;
        native)
            echo "cc"
            echo ""
            ;;
        *)
            echo ""
            echo ""
            ;;
    esac
}

check_toolchain() {
    local platform="$1"

    local info
    info=$(get_toolchain_info "$platform")
    local binary
    binary=$(echo "$info" | head -1)
    local tc_dir
    tc_dir=$(echo "$info" | tail -1)

    if [[ -z "$binary" ]]; then
        return 1
    fi

    # Priority 1: ABL_TOOLCHAIN_PATH env var
    if [[ -n "$ABL_TOOLCHAIN_PATH" ]]; then
        if [[ -x "$ABL_TOOLCHAIN_PATH/bin/$binary" ]]; then
            log_ok "Toolchain found via ABL_TOOLCHAIN_PATH: $binary ($ABL_TOOLCHAIN_PATH/bin/$binary)"
            return 0
        else
            log_error "ABL_TOOLCHAIN_PATH set but $binary not found at $ABL_TOOLCHAIN_PATH/bin/"
            return 1
        fi
    fi

    # Priority 2: System PATH
    if command -v "$binary" &>/dev/null; then
        local version
        version=$("$binary" --version 2>&1 | head -1)
        log_ok "Toolchain found in PATH: $binary — $version"
        return 0
    fi

    # Priority 3: Managed toolchain (~/.local/share/...)
    local managed_bin="$TOOLCHAIN_BASE_DIR/$tc_dir/current/bin/$binary"
    if [[ -x "$managed_bin" ]]; then
        log_ok "Toolchain found (managed): $binary ($managed_bin)"
        # Export to PATH for CMake to find
        export PATH="$TOOLCHAIN_BASE_DIR/$tc_dir/current/bin:$PATH"
        return 0
    fi

    # Also check esp-idf special case
    if [[ "$platform" == "esp32" ]]; then
        local esp_idf_dir="$TOOLCHAIN_BASE_DIR/esp-idf"
        if [[ -d "$esp_idf_dir" ]]; then
            # Find any version
            local found_version
            found_version=$(find "$esp_idf_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
            if [[ -n "$found_version" ]]; then
                local esp_gcc="$found_version/tools/xtensa-esp32-elf/bin/xtensa-esp32-elf-gcc"
                if [[ -x "$esp_gcc" ]]; then
                    log_ok "Toolchain found (ESP-IDF): $esp_gcc"
                    export IDF_PATH="$found_version"
                    export PATH="$found_version/tools/xtensa-esp32-elf/bin:$PATH"
                    return 0
                fi
            fi
        fi
    fi

    return 1
}

# ─── Прошивка / монитор: единая команда, платформенная реализация ────────────
# Что и как прошивать, описывает board-дефиниция (секции flash:/monitor:).
flash_firmware() {
    local tool
    tool=$(yaml_get "$BOARD_FILE" "flash.tool" 2>/dev/null) || true

    case "$tool" in
        openocd)
            local cfg="${PLATFORM_DIR}/boards/${PRODUCT_BOARD}.openocd.cfg"
            local elf="${BUILD_DIR}/release/${OUTPUT_NAME}.elf"
            if [[ ! -f "$cfg" ]]; then
                log_error "OpenOCD-конфиг не найден: $cfg"
                return 1
            fi
            if [[ ! -f "$elf" ]]; then
                log_error "ELF не найден: $elf"
                return 1
            fi
            if ! command -v openocd >/dev/null; then
                log_error "openocd не установлен"
                log_info "  sudo apt install openocd"
                return 1
            fi
            log_info "Прошивка (OpenOCD): $(basename "$elf")"
            openocd -f "$cfg" -c "program ${elf} verify reset exit"
            ;;

        avrdude)
            local programmer port baud part hex
            programmer=$(yaml_get "$BOARD_FILE" "flash.programmer" 2>/dev/null) || true
            port=$(yaml_get "$BOARD_FILE" "flash.port" 2>/dev/null) || true
            baud=$(yaml_get "$BOARD_FILE" "flash.baud" 2>/dev/null) || true
            part=$(yaml_get "$BOARD_FILE" "cpu" 2>/dev/null) || true
            hex="${BUILD_DIR}/release/${OUTPUT_NAME}.hex"
            if [[ ! -f "$hex" ]]; then
                log_error "HEX не найден: $hex"
                return 1
            fi
            if ! command -v avrdude >/dev/null; then
                log_error "avrdude не установлен"
                log_info "  sudo apt install avrdude"
                return 1
            fi
            log_info "Прошивка (avrdude): $(basename "$hex") → $port ($programmer, $part)"
            avrdude -c "$programmer" -p "$part" -P "$port" -b "$baud" -U "flash:w:${hex}:i"
            ;;

        *)
            log_error "Для платы '${PRODUCT_BOARD}' не задан flash.tool в board-дефиниции"
            return 1
            ;;
    esac
}

monitor_target() {
    local port baud
    port=$(yaml_get "$BOARD_FILE" "monitor.port" 2>/dev/null) || true
    baud=$(yaml_get "$BOARD_FILE" "monitor.baud" 2>/dev/null) || true
    baud="${baud:-115200}"

    if [[ -z "$port" ]]; then
        log_warn "Плата не задаёт monitor.port — монитор не запущен"
        return 0
    fi

    if command -v picocom >/dev/null; then
        log_info "Монитор (picocom): $port @ $baud — выход: Ctrl+A Ctrl+Q"
        picocom -b "$baud" "$port"
    else
        log_warn "picocom не установлен — запустите вручную:"
        log_info "  picocom -b $baud $port      # sudo apt install picocom"
    fi
}

# Функция справки
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build firmware from *_config.yml. If no config specified, uses the first
*_config.yml found in the project directory.

OPTIONS:
    -C, --config CONFIG_FILE   Config file (default: first *_config.yml)
    -p, --platform PLATFORM    Target platform (overrides config)
    -t, --type BUILD_TYPE      Build type (overrides config)
    -c, --clean                Clean build directory for this platform
    -f, --flash                Flash the firmware after a successful build
    -m, --monitor              Open the serial monitor (picocom / idf.py monitor)
    -h, --help                 Show this help message

EXAMPLES:
    $0                              # Build from config, defaults
    $0 -c                           # Clean and rebuild
    $0 -p stm32f4 -t Debug          # Override platform and type
    $0 -C myproject_config.yml      # Use specific config
EOF
}

# ─── YAML parser ─────────────────────────────────────────────────────────────
yaml_get() {
    local file="$1"
    local query="$2"
    python3 -c "
import yaml, sys
with open('$file') as f:
    data = yaml.safe_load(f)
keys = '$query'.split('.')
result = data
for k in keys:
    if isinstance(result, dict):
        result = result.get(k)
    else:
        result = None
        break
if result is None:
    sys.exit(1)
print(result)
"
}

# ─── Find app config file ────────────────────────────────────────────────────
find_config() {
    local configs=()
    local f
    for f in "${SCRIPT_DIR}/config/"*.yml; do
        [[ -f "$f" ]] && configs+=("$f")
    done

    if [[ ${#configs[@]} -eq 0 ]]; then
        log_error "No app config (*.yml) found in $SCRIPT_DIR/config/"
        log_info "Create one: config/app.yml"
        exit 1
    elif [[ ${#configs[@]} -eq 1 ]]; then
        echo "${configs[0]}"
    else
        log_warn "Multiple app configs found:"
        for c in "${configs[@]}"; do
            log_warn "  $(basename "$c")"
        done
        log_info "Specify one with: $0 -C <config>"
        exit 1
    fi
}

# ─── Initialize variables ────────────────────────────────────────────────────
CONFIG_FILE=""
PLATFORM=""
BUILD_TYPE=""
CLEAN=false
FLASH=false
MONITOR=false

# Save original args
ORIGINAL_ARGS=("$@")

# ─── Parse arguments (first pass — find config file) ─────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        -C|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -p|--platform|-t|--type)
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--clean|-f|--flash|-m|--monitor)
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Reset and parse again with config known
set -- "${ORIGINAL_ARGS[@]}"

# Find config if not specified
if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE=$(find_config)
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Абсолютный путь (build.sh далее меняет рабочий каталог)
if [[ "$CONFIG_FILE" != /* ]]; then
    CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
fi

log_info "Using app config: $(basename "$CONFIG_FILE")"

# ─── Board-дефиниция живёт в платформе (D9) ──────────────────────────────────
PRODUCT_BOARD=$(yaml_get "$CONFIG_FILE" "product.board" 2>/dev/null) || true
if [[ -z "$PRODUCT_BOARD" ]]; then
    log_error "product.board не задан в $(basename "$CONFIG_FILE")"
    exit 1
fi

PLATFORM_DIR=$(resolve_platform_dir)
if [[ -z "$PLATFORM_DIR" ]]; then
    log_error "abl-mcu-platform не найден (ABL_DEPS_PATH / lib/ / соседний каталог)"
    log_info "Установите зависимости: ./setup.sh -d"
    exit 1
fi

BOARD_FILE="${PLATFORM_DIR}/boards/${PRODUCT_BOARD}.yml"
if [[ ! -f "$BOARD_FILE" ]]; then
    log_error "Board-дефиниция не найдена: $BOARD_FILE"
    log_info "Доступные платы:"
    for b in "${PLATFORM_DIR}/boards/"*.yml; do
        [[ -f "$b" ]] && log_info "  $(basename "$b" .yml)"
    done
    exit 1
fi
log_info "Board: ${PRODUCT_BOARD}"

# Read defaults from board + app config
CONFIG_PLATFORM=$(yaml_get "$BOARD_FILE" "platform" 2>/dev/null) || true
MCU_PART=$(yaml_get "$BOARD_FILE" "mcu.part" 2>/dev/null) || true
BOARD_CPU=$(yaml_get "$BOARD_FILE" "cpu" 2>/dev/null) || true
BOARD_FREQ=$(yaml_get "$BOARD_FILE" "oscillator.freq_hz" 2>/dev/null) || true
CONFIG_BUILD_TYPE=$(yaml_get "$CONFIG_FILE" "build.type" 2>/dev/null) || true
CONFIG_RUNTIME=$(yaml_get "$CONFIG_FILE" "product.runtime" 2>/dev/null) || true
PRODUCT_ID=$(yaml_get "$CONFIG_FILE" "product.id" 2>/dev/null) || true
CONFIG_OUTPUT_NAME=$(yaml_get "$CONFIG_FILE" "build.output" 2>/dev/null) || true

# Apply config defaults (CLI overrides later)
PLATFORM="${PLATFORM:-$CONFIG_PLATFORM}"
BUILD_TYPE="${BUILD_TYPE:-$CONFIG_BUILD_TYPE}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
PROJECT_NAME="${PRODUCT_ID:-abl-project}"
OUTPUT_NAME="${CONFIG_OUTPUT_NAME:-$PROJECT_NAME}"
RUNTIME="${CONFIG_RUNTIME:-bare}"

# ─── Parse arguments (second pass — apply overrides) ─────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        -C|--config)
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -f|--flash)
            FLASH=true
            shift
            ;;
        -m|--monitor)
            MONITOR=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Проверка обязательных параметров
if [[ -z "$PLATFORM" ]]; then
    log_error "Platform is required. Use -p or --platform to specify target platform."
    show_help
    exit 1
fi

# Проверка поддерживаемых платформ
SUPPORTED_PLATFORMS=("stm32f4" "stm32f103" "stm32h743" "esp32" "avr" "native")
if [[ ! " ${SUPPORTED_PLATFORMS[@]} " =~ " ${PLATFORM} " ]]; then
    log_error "Unsupported platform: $PLATFORM"
    log_info "Supported platforms: ${SUPPORTED_PLATFORMS[*]}"
    exit 1
fi

# Проверка типа сборки
SUPPORTED_BUILD_TYPES=("Debug" "Release" "RelWithDebInfo" "MinSizeRel")
if [[ ! " ${SUPPORTED_BUILD_TYPES[@]} " =~ " ${BUILD_TYPE} " ]]; then
    log_error "Unsupported build type: $BUILD_TYPE"
    log_info "Supported build types: ${SUPPORTED_BUILD_TYPES[*]}"
    exit 1
fi

log_info "Building project for platform: $PLATFORM"
log_info "Build type: $BUILD_TYPE"
log_info "Runtime: $RUNTIME"

# Platform-specific build directory
BUILD_DIR="${BUILD_BASE_DIR}/${PLATFORM}"

# Проверка git-зависимостей (core, drivers, etc.)
if ! check_git_deps; then
    log_warn "Git dependencies not found in lib/"
    log_info "Fetching via CMake FetchContent — consider running first:"
    log_info "  ./setup.sh -d"
fi

# ─── ESP32: сборка через обёртку ESP-IDF (D3) ────────────────────────────────
if [[ "$PLATFORM" == "esp32" ]]; then
    IDF_PATH="${IDF_PATH:-$HOME/.local/share/abl-mcu-sdks/esp-idf}"
    if [[ ! -f "$IDF_PATH/export.sh" ]]; then
        log_error "ESP-IDF не найден: $IDF_PATH"
        log_info "Установите: ./setup.sh -p esp32"
        exit 1
    fi
    log_info "ESP-IDF: $IDF_PATH"

    if [[ $CLEAN == true && -d "$BUILD_DIR" ]]; then
        log_info "Cleaning build directory for platform: $PLATFORM..."
        rm -rf "$BUILD_DIR"
    fi

    # export.sh даёт toolchain (xtensa-esp-elf) и python-env IDF
    # shellcheck disable=SC1090
    source "$IDF_PATH/export.sh" >/dev/null

    IDF_ACTION="build"
    [[ "$FLASH" == true ]] && IDF_ACTION="flash"

    IDF_PORT=$(yaml_get "$BOARD_FILE" "flash.port" 2>/dev/null) || true
    IDF_PORT_ARG=""
    [[ -n "$IDF_PORT" ]] && IDF_PORT_ARG="-p $IDF_PORT"

    log_info "Building via idf.py (IDF project: target/esp32, action: $IDF_ACTION)"
    idf.py -C "${SCRIPT_DIR}/target/esp32" -B "${BUILD_DIR}" \
        -DABL_PLATFORM_DIR="${PLATFORM_DIR}" \
        -DABL_PROJECT_DIR="${SCRIPT_DIR}" \
        -DABL_PRODUCT_ID="${PRODUCT_ID}" \
        -DAPP_CONFIG="${CONFIG_FILE}" \
        -DBOARD_FILE="${BOARD_FILE}" \
        -DABL_RUNTIME="${RUNTIME}" \
        ${IDF_PORT_ARG} \
        ${IDF_ACTION}

    if [[ "$MONITOR" == true ]]; then
        log_info "Монитор IDF (выход: Ctrl+])"
        idf.py -C "${SCRIPT_DIR}/target/esp32" -B "${BUILD_DIR}" ${IDF_PORT_ARG} monitor
    fi

    log_info "Build completed successfully!"
    log_info "Images are located in: $BUILD_DIR"
    exit 0
fi

# Проверка тулчейна
if ! check_toolchain "$PLATFORM"; then
    log_error "Toolchain not found for platform: $PLATFORM"
    log_info ""
    log_info "Run setup to install the toolchain:"
    log_info "  ./setup.sh -p $PLATFORM"
    log_info ""
    log_info "Or set ABL_TOOLCHAIN_PATH to your toolchain directory."
    exit 1
fi
log_info "Toolchain check passed"

# Создание директории сборки
if [[ $CLEAN == true ]]; then
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "Cleaning build directory for platform: $PLATFORM..."
        rm -rf "$BUILD_DIR"
    else
        log_info "Build directory for $PLATFORM does not exist, skipping clean."
    fi
fi

mkdir -p "$BUILD_DIR"

# Переход в директорию сборки
cd "$BUILD_DIR"

# Запуск cmake
log_info "Configuring project with CMake..."
cmake "${SCRIPT_DIR}" \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DPLATFORM=$PLATFORM \
    -DPROJECT_NAME=$PROJECT_NAME \
    -DOUTPUT_NAME=$OUTPUT_NAME \
    -DAPP_CONFIG="${CONFIG_FILE}" \
    -DBOARD_FILE="${BOARD_FILE}" \
    -DMCU_PART="${MCU_PART}" \
    -DAVR_MCU="${BOARD_CPU}" \
    -DF_CPU_HZ="${BOARD_FREQ}" \
    -DABL_RUNTIME="${RUNTIME}" \
    -G "Ninja"

# Сборка проекта
log_info "Building project..."
ninja

log_info "Build completed successfully!"
log_info "Output files are located in: $BUILD_DIR"

# ─── Прошивка / монитор (единые команды, см. -f/-m) ──────────────────────────
if [[ "$FLASH" == true ]]; then
    flash_firmware
fi
if [[ "$MONITOR" == true ]]; then
    monitor_target
fi