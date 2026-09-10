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

    if [[ -n "$ABL_DEPS_PATH" && -d "$ABL_DEPS_PATH/abl-mcu-platform" ]]; then
        core_path="$ABL_DEPS_PATH/abl-mcu-platform"
    elif [[ -d "$SCRIPT_DIR/lib/abl-mcu-platform" ]]; then
        core_path="$SCRIPT_DIR/lib/abl-mcu-platform"
    fi

    if [[ -n "$core_path" ]]; then
        log_ok "Git dependency found: abl-mcu-platform at $core_path"
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

Build firmware from *_config.yml. If no config specified, uses the first
*_config.yml found in the project directory.

OPTIONS:
    -C, --config CONFIG_FILE   Config file (default: first *_config.yml)
    -p, --platform PLATFORM    Target platform (overrides config)
    -t, --type BUILD_TYPE      Build type (overrides config)
    -c, --clean                Clean build directory for this platform
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

# ─── Find config file ────────────────────────────────────────────────────────
find_config() {
    local configs=("${SCRIPT_DIR}/config/"*_config.yml)
    if [[ ${#configs[@]} -eq 0 ]]; then
        log_error "No *_config.yml found in $SCRIPT_DIR/config/"
        log_info "Create a config file: config/myproject_config.yml"
        exit 1
    elif [[ ${#configs[@]} -eq 1 ]]; then
        echo "${configs[0]}"
    else
        log_warn "Multiple config files found:"
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

# Save original args
ORIGINAL_ARGS=("$@")

# ─── Parse arguments (first pass — find config file) ─────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        -C|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -p|--platform|-t|--type|-c|--clean|-h|--help)
            shift; [[ "$1" != -* ]] && shift
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

log_info "Using config: $(basename "$CONFIG_FILE")"

# Resolve platform config path (relative to project root)
PLATFORM_CONFIG_REL=$(yaml_get "$CONFIG_FILE" "hardware.platform" 2>/dev/null) || true
if [[ -n "$PLATFORM_CONFIG_REL" && "$PLATFORM_CONFIG_REL" != /* ]]; then
    PLATFORM_CONFIG="${SCRIPT_DIR}/${PLATFORM_CONFIG_REL}"
else
    PLATFORM_CONFIG="$PLATFORM_CONFIG_REL"
fi

if [[ ! -f "$PLATFORM_CONFIG" ]]; then
    log_error "Platform config not found: $PLATFORM_CONFIG"
    log_info "Check hardware.platform in $(basename "$CONFIG_FILE")"
    exit 1
fi

# Read defaults from platform config
CONFIG_PLATFORM=$(yaml_get "$PLATFORM_CONFIG" "platform" 2>/dev/null) || true
CONFIG_BUILD_TYPE=$(yaml_get "$CONFIG_FILE" "build.type" 2>/dev/null) || true
CONFIG_PROJECT_NAME=$(yaml_get "$CONFIG_FILE" "project.name" 2>/dev/null) || true
CONFIG_OUTPUT_NAME=$(yaml_get "$CONFIG_FILE" "build.output" 2>/dev/null) || true

# Apply config defaults (CLI overrides later)
PLATFORM="${PLATFORM:-$CONFIG_PLATFORM}"
BUILD_TYPE="${BUILD_TYPE:-$CONFIG_BUILD_TYPE}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
PROJECT_NAME="${CONFIG_PROJECT_NAME:-abl-project}"
OUTPUT_NAME="${CONFIG_OUTPUT_NAME:-$PROJECT_NAME}"

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

# Read target files from config (prepend SCRIPT_DIR for absolute paths)
STARTUP_FILE=$(yaml_get "$CONFIG_FILE" "target.startup" 2>/dev/null) || true
LINKER_SCRIPT=$(yaml_get "$CONFIG_FILE" "target.linker" 2>/dev/null) || true
SYSTEM_FILE=$(yaml_get "$CONFIG_FILE" "target.system" 2>/dev/null) || true

# Make paths absolute
[[ -n "$STARTUP_FILE" && "$STARTUP_FILE" != /* ]] && STARTUP_FILE="${SCRIPT_DIR}/${STARTUP_FILE}"
[[ -n "$LINKER_SCRIPT" && "$LINKER_SCRIPT" != /* ]] && LINKER_SCRIPT="${SCRIPT_DIR}/${LINKER_SCRIPT}"
[[ -n "$SYSTEM_FILE" && "$SYSTEM_FILE" != /* ]] && SYSTEM_FILE="${SCRIPT_DIR}/${SYSTEM_FILE}"

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
    -DPROJECT_NAME=$PROJECT_NAME \
    -DOUTPUT_NAME=$OUTPUT_NAME \
    -DCONFIG_FILE="${PLATFORM_CONFIG}" \
    -DSTARTUP_FILE="${STARTUP_FILE}" \
    -DLINKER_SCRIPT="${LINKER_SCRIPT}" \
    -DSYSTEM_FILE="${SYSTEM_FILE}" \
    -G "Ninja"

# Сборка проекта
log_info "Building project..."
ninja

log_info "Build completed successfully!"
log_info "Output files are located in: $BUILD_DIR"