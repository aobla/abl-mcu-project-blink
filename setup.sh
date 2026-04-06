#!/bin/bash

# Setup script for ABL MCU Project Blink
# Checks and installs prerequisites for the selected platform(s)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQ_FILE="${SCRIPT_DIR}/prerequisites.yaml"
TOOLCHAIN_BASE_DIR="$HOME/.local/share/abl-mcu-toolchains"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC} $1"; }
log_skip()    { echo -e "${YELLOW}[SKIP]${NC} $1"; }

# ─── Help ────────────────────────────────────────────────────────────────────
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and check prerequisites for ABL MCU projects.

OPTIONS:
    -p, --platform PLATFORM    Platform to setup (stm32, avr, esp32)
                               Can be specified multiple times
    -a, --all                  Setup all platforms
    --check-only               Only check, don't install
    --force                    Force reinstall even if found
    -h, --help                 Show this help message

EXAMPLES:
    $0 -p stm32                Setup STM32 toolchain
    $0 -p stm32 -p avr         Setup both STM32 and AVR
    $0 --check-only            Check all dependencies
    $0 -a                      Setup all platforms
EOF
}

# ─── Parse arguments ─────────────────────────────────────────────────────────
PLATFORMS=()
CHECK_ONLY=false
FORCE=false
ALL_PLATFORMS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--platform)
            PLATFORMS+=("$2")
            shift 2
            ;;
        -a|--all)
            ALL_PLATFORMS=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --force)
            FORCE=true
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

# ─── Detect OS ───────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_ID="macos"
    else
        OS_ID="unknown"
    fi
    echo "$OS_ID"
}

OS_ID=$(detect_os)
log_info "Detected OS: $OS_ID"

# ─── Detect architecture ─────────────────────────────────────────────────────
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) echo "$arch" ;;
    esac
}

ARCH=$(detect_arch)
log_info "Detected architecture: $ARCH"

# ─── YAML parser (lightweight, no external deps beyond python3) ──────────────
# Uses python3 to parse YAML since it's a prerequisite anyway

yaml_get() {
    local file="$1"
    local query="$2"
    python3 -c "
import yaml, sys, json
with open('$file') as f:
    data = yaml.safe_load(f)
# Navigate the query (dot-separated)
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
if isinstance(result, (dict, list)):
    print(json.dumps(result))
else:
    print(result)
"
}

yaml_get_list() {
    local file="$1"
    local query="$2"
    python3 -c "
import yaml, json
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
    print('[]')
else:
    print(json.dumps(result))
"
}

# ─── Version comparison ──────────────────────────────────────────────────────
version_gte() {
    # Returns 0 if $1 >= $2
    python3 -c "
from packaging import version
import sys
sys.exit(0 if version.parse('$1') >= version.parse('$2') else 1)
" 2>/dev/null || python3 -c "
# Fallback without packaging module
v1 = '$1'.split('.')
v2 = '$2'.split('.')
for a, b in zip(v1, v2):
    try:
        a, b = int(a), int(b)
    except ValueError:
        a, b = str(a), str(b)
    if a > b: exit(0)
    if a < b: exit(1)
exit(0 if len(v1) >= len(v2) else 1)
"
}

# ─── Check if binary exists and get version ──────────────────────────────────
check_binary_version() {
    local binary="$1"
    local version_flag="$2"
    local regex="$3"

    local binary_path
    binary_path=$(command -v "$binary" 2>/dev/null) || return 1

    local version_output
    version_output=$("$binary" $version_flag 2>&1) || return 1

    local version
    version=$(echo "$version_output" | grep -oP "$regex" | head -1) || return 1

    echo "$version"
    return 0
}

# ─── Check a single prerequisite ─────────────────────────────────────────────
check_prerequisite() {
    local name="$1"
    local binary="$2"
    local version_flag="$3"
    local regex="$4"
    local min_version="$5"

    local version
    version=$(check_binary_version "$binary" "$version_flag" "$regex") || return 1

    if [[ -n "$min_version" ]]; then
        if version_gte "$version" "$min_version"; then
            log_ok "$name $version (≥ $min_version)"
            return 0
        else
            log_warn "$name $version (need ≥ $min_version)"
            return 1
        fi
    else
        log_ok "$name $version"
        return 0
    fi
}

# ─── Install system packages ─────────────────────────────────────────────────
install_system_packages() {
    local packages="$1"  # space-separated or JSON array

    # Handle JSON array input
    if [[ "$packages" == "["* ]]; then
        packages=$(echo "$packages" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)))" 2>/dev/null)
    fi

    if [[ -z "$packages" || "$packages" == "null" ]]; then
        return 1
    fi

    log_step "Installing system packages: $packages"

    case "$OS_ID" in
        ubuntu|debian)
            if [[ "$CHECK_ONLY" == true ]]; then
                log_warn "Would run: sudo apt install -y $packages"
                return 0
            fi
            sudo apt update -qq
            sudo apt install -y $packages
            ;;
        arch)
            if [[ "$CHECK_ONLY" == true ]]; then
                log_warn "Would run: sudo pacman -S --noconfirm $packages"
                return 0
            fi
            sudo pacman -S --noconfirm --needed $packages
            ;;
        fedora)
            if [[ "$CHECK_ONLY" == true ]]; then
                log_warn "Would run: sudo dnf install -y $packages"
                return 0
            fi
            sudo dnf install -y $packages
            ;;
        macos)
            if [[ "$CHECK_ONLY" == true ]]; then
                log_warn "Would run: brew install $packages"
                return 0
            fi
            if ! command -v brew &>/dev/null; then
                log_error "Homebrew not found. Install it first: https://brew.sh"
                return 1
            fi
            brew install $packages
            ;;
        *)
            log_error "Unsupported OS: $OS_ID"
            return 1
            ;;
    esac
}

# ─── Install Python packages ─────────────────────────────────────────────────
install_python_packages() {
    local packages="$1"  # space-separated

    if [[ -z "$packages" ]]; then
        return 0
    fi

    log_step "Installing Python packages: $packages"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would run: pip3 install $packages"
        return 0
    fi

    pip3 install --user --quiet $packages
}

# ─── Download and install toolchain from URL ─────────────────────────────────
install_toolchain_from_url() {
    local name="$1"
    local install_dir="$2"
    local os_key="${OS_ID}_${ARCH}"

    # Get download URL for this OS/arch
    local download_info
    download_info=$(yaml_get "$PREREQ_FILE" "platforms.${name}.0.download.${os_key}") || {
        log_error "No download available for $os_key"
        return 1
    }

    local url
    url=$(echo "$download_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
    local archive_type
    archive_type=$(echo "$download_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['archive_type'])")

    local dest_dir
    dest_dir=$(echo "$install_dir" | sed "s|~|$HOME|g")

    log_step "Downloading $name for $os_key..."
    log_info "URL: $url"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would download and install to $dest_dir"
        return 0
    fi

    # Create temp directory
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" RETURN

    # Download
    local archive_name
    archive_name=$(basename "$url")
    curl -L --progress-bar "$url" -o "$tmp_dir/$archive_name"

    # Extract
    log_info "Extracting..."
    mkdir -p "$dest_dir"

    case "$archive_type" in
        tar.xz)
            tar -xJf "$tmp_dir/$archive_name" -C "$dest_dir" --strip-components=1
            ;;
        tar.gz)
            tar -xzf "$tmp_dir/$archive_name" -C "$dest_dir" --strip-components=1
            ;;
        zip)
            unzip -q "$tmp_dir/$archive_name" -d "$dest_dir"
            ;;
        *)
            log_error "Unsupported archive type: $archive_type"
            return 1
            ;;
    esac

    # Create symlink
    local version_dir
    version_dir=$(basename "$url" | grep -oP '[0-9]+\.[0-9]+[^/]*' | head -1)
    if [[ -d "$dest_dir" ]]; then
        ln -sf "$dest_dir" "$dest_dir/../current" 2>/dev/null || true
        log_ok "Installed to $dest_dir"
    fi
}

# ─── Install ESP-IDF ─────────────────────────────────────────────────────────
install_esp_idf() {
    local install_dir
    install_dir=$(yaml_get "$PREREQ_FILE" "platforms.esp32.0.install_dir" | sed "s|~|$HOME|g")
    local git_url
    git_url=$(yaml_get "$PREREQ_FILE" "platforms.esp32.0.git.url" | tr -d '"')
    local git_tag
    git_tag=$(yaml_get "$PREREQ_FILE" "platforms.esp32.0.git.tag" | tr -d '"')

    log_step "Setting up ESP-IDF..."

    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would clone $git_url ($git_tag) to $install_dir"
        return 0
    fi

    mkdir -p "$install_dir"

    if [[ ! -d "$install_dir/.git" ]]; then
        log_info "Cloning ESP-IDF ($git_tag)..."
        git clone --recursive --branch "$git_tag" --depth 1 "$git_url" "$install_dir"
    else
        log_info "ESP-IDF already cloned, updating..."
        cd "$install_dir"
        git fetch --depth 1 origin "$git_tag"
        git checkout "$git_tag"
        git submodule update --init --recursive
        cd -
    fi

    # Run install script
    log_info "Running ESP-IDF install.sh..."
    cd "$install_dir"
    ./install.sh
    cd -

    log_ok "ESP-IDF installed to $install_dir"
    log_info "Run 'source $install_dir/export.sh' before building"
}

# ─── Setup a single platform ─────────────────────────────────────────────────
setup_platform() {
    local platform="$1"
    log_step "═══════════════════════════════════════════════════"
    log_step "Setting up platform: $platform"
    log_step "═══════════════════════════════════════════════════"

    # Get toolchain list for this platform
    local toolchains_json
    toolchains_json=$(yaml_get_list "$PREREQ_FILE" "platforms.${platform}") || {
        log_error "No toolchain definition for platform: $platform"
        return 1
    }

    # Process each toolchain entry
    local count
    count=$(echo "$toolchains_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    for ((i=0; i<count; i++)); do
        local tc_name
        tc_name=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d['name'])")
        local tc_check_binary
        tc_check_binary=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('check',{}).get('binary',''))" 2>/dev/null) || true
        local tc_check_flag
        tc_check_flag=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('check',{}).get('version_flag','--version'))" 2>/dev/null) || true
        local tc_check_regex
        tc_check_regex=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('check',{}).get('version_regex',''))" 2>/dev/null) || true
        local tc_min_version
        tc_min_version=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('check',{}).get('min_version',''))" 2>/dev/null) || true
        local tc_install_dir
        tc_install_dir=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('install_dir',''))" 2>/dev/null) || true

        log_info "Checking: $tc_name"

        # Step 1: Check system PATH
        local found_in_path=false
        if [[ -n "$tc_check_binary" ]]; then
            local sys_version
            sys_version=$(check_binary_version "$tc_check_binary" "$tc_check_flag" "$tc_check_regex") || true
            if [[ -n "$sys_version" ]]; then
                if [[ -n "$tc_min_version" ]] && version_gte "$sys_version" "$tc_min_version"; then
                    log_ok "Found in PATH: $tc_name $sys_version"
                    found_in_path=true
                else
                    log_warn "System version $sys_version < $tc_min_version"
                fi
            fi
        fi

        if [[ "$found_in_path" == true && "$FORCE" != true ]]; then
            log_skip "Using system toolchain, skipping install"
            continue
        fi

        # Step 2: Check managed toolchain (~/.local/share/...)
        if [[ -n "$tc_install_dir" ]]; then
            local managed_dir
            managed_dir=$(echo "$tc_install_dir" | sed "s|~|$HOME|g")
            local current_link="$managed_dir/current"

            if [[ -L "$current_link" || -d "$current_link" ]]; then
                local managed_version
                managed_version=$(PATH="$managed_dir/current/bin:$PATH" check_binary_version "$tc_check_binary" "$tc_check_flag" "$tc_check_regex") || true
                if [[ -n "$managed_version" ]]; then
                    if [[ -n "$tc_min_version" ]] && version_gte "$managed_version" "$tc_min_version"; then
                        log_ok "Found managed: $tc_name $managed_version at $managed_dir"
                        if [[ "$FORCE" != true ]]; then
                            log_skip "Using managed toolchain"
                            continue
                        fi
                    fi
                fi
            fi
        fi

        # Step 3: Install
        if [[ "$CHECK_ONLY" == true ]]; then
            log_warn "$tc_name not found — would be installed"
            continue
        fi

        # ESP-IDF special case
        if [[ "$tc_name" == "esp-idf" ]]; then
            install_esp_idf
            continue
        fi

        # Try system packages first
        local pkg_key="${platform}.${i}.packages.${OS_ID}"
        local sys_packages
        sys_packages=$(yaml_get "$PREREQ_FILE" "platforms.${pkg_key}" 2>/dev/null) || true
        sys_packages=$(echo "$sys_packages" | tr -d '"')

        if [[ -n "$sys_packages" && "$sys_packages" != "null" ]]; then
            log_info "Trying system packages for $tc_name..."
            if install_system_packages "$sys_packages"; then
                # Verify installation
                local new_version
                new_version=$(check_binary_version "$tc_check_binary" "$tc_check_flag" "$tc_check_regex") || true
                if [[ -n "$new_version" ]]; then
                    if [[ -n "$tc_min_version" ]] && version_gte "$new_version" "$tc_min_version"; then
                        log_ok "Installed via system package: $tc_name $new_version"
                        continue
                    fi
                fi
                log_warn "System package installed but version check failed"
            fi
        fi

        # Fallback: download
        if [[ -n "$tc_install_dir" ]]; then
            log_info "Downloading $tc_name..."
            if install_toolchain_from_url "$tc_name" "$tc_install_dir"; then
                log_ok "Downloaded $tc_name"
            else
                log_error "Failed to install $tc_name"
            fi
        else
            log_error "No installation method available for $tc_name on $OS_ID"
        fi
    done
}

# ─── Setup common dependencies ───────────────────────────────────────────────
setup_common() {
    log_step "═══════════════════════════════════════════════════"
    log_step "Checking common dependencies"
    log_step "═══════════════════════════════════════════════════"

    local common_count
    common_count=$(yaml_get_list "$PREREQ_FILE" "common" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    local missing_packages=()

    for ((i=0; i<common_count; i++)); do
        local item
        item=$(yaml_get_list "$PREREQ_FILE" "common" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)[$i]))")

        local name
        name=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['name'])")

        # Skip pip_packages — handled separately
        if [[ "$name" == "pip_packages" ]]; then
            continue
        fi

        local binary
        binary=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('check',{}).get('binary',''))" 2>/dev/null) || true
        local flag
        flag=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('check',{}).get('version_flag','--version'))" 2>/dev/null) || true
        local regex
        regex=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('check',{}).get('version_regex',''))" 2>/dev/null) || true
        local min_ver
        min_ver=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('check',{}).get('min_version',''))" 2>/dev/null) || true

        if [[ -z "$binary" ]]; then
            continue
        fi

        if ! check_prerequisite "$name" "$binary" "$flag" "$regex" "$min_ver"; then
            # Try to install — get packages from the already-parsed item
            local pkg
            pkg=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('packages',{}).get('$OS_ID',''))" 2>/dev/null) || true
            pkg=$(echo "$pkg" | tr -d '"' | sed 's/^\[//;s/\]$//;s/,/ /g;s/  */ /g')

            if [[ -n "$pkg" && "$pkg" != "null" ]]; then
                if [[ "$CHECK_ONLY" == true ]]; then
                    log_warn "Would install: $pkg"
                else
                    install_system_packages "$pkg"
                    # Re-check
                    if ! check_prerequisite "$name" "$binary" "$flag" "$regex" "$min_ver"; then
                        log_error "Failed to install $name"
                    fi
                fi
            else
                log_error "$name not found and no package available for $OS_ID"
            fi
        fi
    done

    # Install Python packages
    log_step "Checking Python packages..."
    local pip_packages
    pip_packages=$(yaml_get_list "$PREREQ_FILE" "common" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data:
    if item.get('name') == 'pip_packages':
        print(' '.join(item.get('python', [])))
        break
" 2>/dev/null) || true

    if [[ -n "$pip_packages" ]]; then
        install_python_packages "$pip_packages"
        log_ok "Python packages installed"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    if [[ ! -f "$PREREQ_FILE" ]]; then
        log_error "Prerequisites file not found: $PREREQ_FILE"
        exit 1
    fi

    # Check python3 and PyYAML availability (needed for YAML parsing)
    if ! command -v python3 &>/dev/null; then
        log_error "Python3 is required but not installed"
        log_info "Install it first: sudo apt install python3 (Ubuntu/Debian)"
        exit 1
    fi

    if ! python3 -c "import yaml" 2>/dev/null; then
        log_warn "PyYAML not installed, installing..."
        pip3 install --user --quiet pyyaml
    fi

    # Setup common dependencies
    setup_common

    # Determine platforms to setup
    if [[ "$ALL_PLATFORMS" == true ]]; then
        PLATFORMS=($(yaml_get_list "$PREREQ_FILE" "platforms" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).keys()))"))
        log_info "Setting up all platforms: ${PLATFORMS[*]}"
    fi

    if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
        log_warn "No platform specified. Use -p PLATFORM or -a for all."
        show_help
        exit 0
    fi

    # Setup each platform
    for platform in "${PLATFORMS[@]}"; do
        setup_platform "$platform"
    done

    log_step ""
    log_ok "Setup complete!"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_info "This was a dry-run. Remove --check-only to actually install."
    fi
}

main
