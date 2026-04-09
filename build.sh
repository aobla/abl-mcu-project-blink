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

check_git_deps() {
    # Check if platform-core is available
    local core_path=""

    if [[ -n "$ABL_DEPS_PATH" && -d "$ABL_DEPS_PATH/abl-mcu-platform-core" ]]; then
        core_path="$ABL_DEPS_PATH/abl-mcu-platform-core"
    elif [[ -d "$SCRIPT_DIR/lib/abl-mcu-platform-core" ]]; then
        core_path="$SCRIPT_DIR/lib/abl-mcu-platform-core"
    fi

    if [[ -n "$core_path" ]]; then
        log_ok "Git dependency found: abl-mcu-platform-core at $core_path"
        return 0
    else
        return 1
    fi
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

# Функция справки
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -p, --platform PLATFORM    Target platform (stm32f4, stm32f103, stm32h743, esp32, avr)
    -t, --type BUILD_TYPE      Build type (Debug, Release, RelWithDebInfo, MinSizeRel)
    -c, --clean              Clean build directory before building
    -h, --help               Show this help message

EXAMPLES:
    $0 -p stm32f4                    # Build for STM32F4 in Release mode
    $0 -p esp32 -t Debug             # Build for ESP32 in Debug mode
    $0 -p avr -c                     # Clean build and compile for AVR
EOF
}

# Инициализация переменных
PLATFORM=""
BUILD_TYPE="Release"
CLEAN=false

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
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
SUPPORTED_PLATFORMS=("stm32f4" "stm32f103" "stm32h743" "esp32" "avr")
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

# Platform-specific build directory
BUILD_DIR="${BUILD_BASE_DIR}/${PLATFORM}"

# Проверка git-зависимостей (core, drivers, etc.)
if ! check_git_deps; then
    log_warn "Git dependencies not found in lib/"
    log_info "Fetching via CMake FetchContent — consider running first:"
    log_info "  ./setup.sh -d"
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
    -G "Ninja"

# Сборка проекта
log_info "Building project..."
ninja

log_info "Build completed successfully!"
log_info "Output files are located in: $BUILD_DIR"