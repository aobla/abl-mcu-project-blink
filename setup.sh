#!/bin/bash

# Setup script for ABL MCU Project Blink
# Checks and installs prerequisites for the selected platform(s)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQ_FILE="${SCRIPT_DIR}/prerequisites.yaml"
# Канонический источник версий vendor-SDK/тулчейнов — манифест платформы.
# Пока платформа не найдена, используется bootstrap-файл проекта (fallback).
MANIFEST_FILE="$PREREQ_FILE"
TOOLCHAIN_BASE_DIR="$HOME/.local/share/abl-mcu-toolchains"
SDK_BASE_DIR="$HOME/.local/share/abl-mcu-sdks"
DEPS_BASE_DIR="$HOME/.local/share/abl-mcu-deps"

# ─── Platform manifest resolution ────────────────────────────────────────────
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

manifest_file() {
    local dir
    dir=$(resolve_platform_dir)
    if [[ -n "$dir" && -f "$dir/manifest.yml" ]]; then
        echo "$dir/manifest.yml"
    else
        echo "$PREREQ_FILE"
    fi
}

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
    -p, --platform PLATFORM    Platform to setup (stm32f4, stm32f103, stm32h743, avr, esp32)
                               Can be specified multiple times
    -a, --all                  Setup all platforms
    -d, --deps                 Install git dependencies (core, drivers, etc.)
    --sdk SDK_NAME              Install a specific SDK
    --check-only               Only check, don't install
    --force                    Force reinstall even if found
    -h, --help                 Show this help message

EXAMPLES:
    $0 -d                      Install git dependencies (core, drivers)
    $0 -p stm32f4              Setup STM32F4 toolchain + SDK
    $0 -p stm32f4 -d           Setup toolchain + SDK + git dependencies
    $0 --check-only            Check all dependencies
    $0 -a -d                   Setup everything
EOF
}

# ─── Parse arguments ─────────────────────────────────────────────────────────
PLATFORMS=()
CHECK_ONLY=false
FORCE=false
ALL_PLATFORMS=false
INSTALL_DEPS=false
SPECIFIC_SDK=""

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
        -d|--deps)
            INSTALL_DEPS=true
            shift
            ;;
        --sdk)
            SPECIFIC_SDK="$2"
            shift 2
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

# ─── YAML parser (uses python3) ──────────────────────────────────────────────
yaml_get() {
    local file="$1"
    local query="$2"
    python3 -c "
import yaml, sys, json
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
    python3 -c "
from packaging import version
import sys
sys.exit(0 if version.parse('$1') >= version.parse('$2') else 1)
" 2>/dev/null || python3 -c "
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

# ─── Check binary version ────────────────────────────────────────────────────
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
    local packages="$1"

    # Handle JSON array input
    if [[ "$packages" == "["* ]]; then
        packages=$(echo "$packages" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)))" 2>/dev/null)
    fi

    if [[ -z "$packages" || "$packages" == "null" ]]; then
        return 1
    fi

    log_step "Installing system packages: $packages"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would install: $packages"
        return 0
    fi

    case "$OS_ID" in
        ubuntu|debian)
            sudo apt update -qq
            sudo apt install -y $packages
            ;;
        arch)
            sudo pacman -S --noconfirm --needed $packages
            ;;
        fedora)
            sudo dnf install -y $packages
            ;;
        macos)
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
    local packages="$1"

    if [[ -z "$packages" ]]; then
        return 0
    fi

    log_step "Installing Python packages: $packages"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would run: pip3 install --break-system-packages $packages"
        return 0
    fi

    pip3 install --user --quiet --break-system-packages $packages 2>/dev/null || \
    pip3 install --user --quiet $packages 2>/dev/null || \
    log_warn "pip3 install failed — try: sudo apt install python3-yaml python3-jinja2"
}

# ─── Clone git repository ────────────────────────────────────────────────────
clone_git_repo() {
    local name="$1"
    local url="$2"
    local tag="$3"
    local dest="$4"

    if [[ -d "$dest/.git" ]]; then
        log_info "$name already cloned at $dest, checking tag..."
        local current_tag
        current_tag=$(cd "$dest" && git describe --tags --abbrev=0 2>/dev/null) || true
        if [[ "$current_tag" == "$tag" ]]; then
            log_ok "$name already at $tag"
            return 0
        else
            log_warn "$name at $current_tag, expected $tag — updating..."
            if [[ "$CHECK_ONLY" == true ]]; then
                log_warn "Would update $name to $tag"
                return 0
            fi
            cd "$dest"
            git fetch --tags origin "$tag"
            git checkout "$tag"
            cd - > /dev/null
            return 0
        fi
    fi

    log_step "Cloning $name ($tag)..."
    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would clone $url ($tag) to $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    # If dest exists and has content (from other repos), clone to temp and merge
    if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        git clone --branch "$tag" --depth 1 "$url" "$tmp_dir"
        # Copy contents, preserving existing dirs
        (cd "$tmp_dir" && tar cf - .) | (cd "$dest" && tar xf -)
        rm -rf "$tmp_dir"
    else
        git clone --branch "$tag" --depth 1 "$url" "$dest"
    fi
    log_ok "$name cloned to $dest"
}

# ─── Install SDK from git (single or multi-repo) ─────────────────────────────
install_sdk_from_git() {
    local sdk_name="$1"
    local install_dir
    install_dir=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.install_dir" 2>/dev/null | tr -d '"' | sed "s|~|$HOME|g") || {
        log_error "No install_dir for SDK: $sdk_name"
        return 1
    }

    mkdir -p "$install_dir"

    # Check if it's a list of git repos or a single one
    local is_list
    is_list=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.git" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('true' if isinstance(data, list) else 'false')
" 2>/dev/null)

    if [[ "$is_list" == "true" ]]; then
        # Multi-repo SDK
        local count
        count=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.git" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

        for ((i=0; i<count; i++)); do
            local repo_url
            repo_url=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.git" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i]['url'])")
            local repo_tag
            repo_tag=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.git" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i]['tag'])")
            local repo_subdir
            repo_subdir=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.git" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('subdir',''))" 2>/dev/null) || true

            local dest="$install_dir"
            if [[ -n "$repo_subdir" ]]; then
                dest="$install_dir/$repo_subdir"
            fi

            local repo_name
            repo_name=$(basename "$repo_url" .git)

            clone_git_repo "$repo_name" "$repo_url" "$repo_tag" "$dest"
        done
    else
        # Single repo
        local git_url
        git_url=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.git.url" 2>/dev/null | tr -d '"') || {
            log_error "No git URL for SDK: $sdk_name"
            return 1
        }
        local git_tag
        git_tag=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.git.tag" 2>/dev/null | tr -d '"') || {
            log_error "No git tag for SDK: $sdk_name"
            return 1
        }

        clone_git_repo "$sdk_name" "$git_url" "$git_tag" "$install_dir"
    fi
}

# ─── Install SDK from archive ────────────────────────────────────────────────
install_sdk_from_archive() {
    local sdk_name="$1"
    local os_key="${OS_ID}_${ARCH}"

    local archive_info
    archive_info=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.download.${os_key}" 2>/dev/null) || {
        log_error "No download available for $sdk_name on $os_key"
        return 1
    }

    local url
    url=$(echo "$archive_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
    local archive_type
    archive_type=$(echo "$archive_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['archive_type'])")

    local install_dir
    install_dir=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.install_dir" | tr -d '"' | sed "s|~|$HOME|g")

    log_step "Downloading $sdk_name..."
    log_info "URL: $url"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_warn "Would download and install $sdk_name to $install_dir"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" RETURN

    curl -L --progress-bar "$url" -o "$tmp_dir/archive"

    mkdir -p "$install_dir"
    case "$archive_type" in
        tar.xz)  tar -xJf "$tmp_dir/archive" -C "$install_dir" --strip-components=1 ;;
        tar.gz)  tar -xzf "$tmp_dir/archive" -C "$install_dir" --strip-components=1 ;;
        zip)     unzip -q "$tmp_dir/archive" -d "$install_dir" ;;
        *)       log_error "Unsupported archive type: $archive_type"; return 1 ;;
    esac

    log_ok "$sdk_name installed to $install_dir"
}

# ─── Check if SDK is installed ───────────────────────────────────────────────
check_sdk_installed() {
    local sdk_name="$1"
    local cmake_var
    cmake_var=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.cmake_var" 2>/dev/null | tr -d '"') || true

    # Check env-based cmake var
    if [[ -n "$cmake_var" ]]; then
        local env_val="${!cmake_var}"
        if [[ -n "$env_val" && -d "$env_val" ]]; then
            log_ok "$sdk_name found via $cmake_var=$env_val"
            return 0
        fi
    fi

    # Check standard paths
    local install_dir
    install_dir=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.install_dir" 2>/dev/null | tr -d '"' | sed "s|~|$HOME|g") || true

    if [[ -n "$install_dir" && -d "$install_dir" ]]; then
        # Check for marker files or include dirs
        local include_dirs
        include_dirs=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.include_dirs" 2>/dev/null) || true
        if [[ -n "$include_dirs" && "$include_dirs" != "[]" ]]; then
            local first_dir
            first_dir=$(echo "$include_dirs" | python3 -c "import sys,json; print(json.load(sys.stdin)[0])")
            if [[ -d "$install_dir/$first_dir" ]]; then
                log_ok "$sdk_name found at $install_dir"
                return 0
            fi
        else
            # For multi-repo: check if at least one expected subdir exists
            if [[ -d "$install_dir/Inc" || -d "$install_dir/CMSIS" || -d "$install_dir/Drivers" ]]; then
                log_ok "$sdk_name found at $install_dir"
                return 0
            fi
        fi
    fi

    # Check ABL_DEPS_PATH
    if [[ -n "$ABL_DEPS_PATH" && -d "$ABL_DEPS_PATH/$sdk_name" ]]; then
        log_ok "$sdk_name found at $ABL_DEPS_PATH/$sdk_name"
        return 0
    fi

    # Check project lib/
    local lib_dir="$SCRIPT_DIR/lib/$sdk_name"
    if [[ -d "$lib_dir" ]]; then
        log_ok "$sdk_name found at $lib_dir"
        return 0
    fi

    return 1
}

# ─── Resolve SDK install path ────────────────────────────────────────────────
resolve_sdk_path() {
    local sdk_name="$1"

    # Priority 1: ABL_DEPS_PATH
    if [[ -n "$ABL_DEPS_PATH" && -d "$ABL_DEPS_PATH/$sdk_name" ]]; then
        echo "$ABL_DEPS_PATH/$sdk_name"
        return 0
    fi

    # Priority 2: project/lib/
    local lib_dir="$SCRIPT_DIR/lib/$sdk_name"
    if [[ -d "$lib_dir" ]]; then
        echo "$lib_dir"
        return 0
    fi

    # Priority 3: ~/.local/share/abl-mcu-sdks/
    local install_dir
    install_dir=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.install_dir" 2>/dev/null | tr -d '"' | sed "s|~|$HOME|g") || true
    if [[ -n "$install_dir" && -d "$install_dir" ]]; then
        echo "$install_dir"
        return 0
    fi

    return 1
}

# ─── Install SDK ─────────────────────────────────────────────────────────────
install_sdk() {
    local sdk_name="$1"

    log_info "Setting up SDK: $sdk_name"

    # Check if git is a list (multi-repo) or scalar
    local is_list
    is_list=$(yaml_get_list "$MANIFEST_FILE" "sdks.${sdk_name}.git" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('true' if isinstance(data, list) else 'false')
" 2>/dev/null) || true

    # For multi-repo SDKs, skip the installed check — let the loop handle each repo
    if [[ "$is_list" == "true" ]]; then
        install_sdk_from_git "$sdk_name"
        return $?
    fi

    # Single repo: check if already installed
    if [[ "$FORCE" != true ]] && check_sdk_installed "$sdk_name"; then
        log_skip "SDK already installed"
        return 0
    fi

    # Single git repo
    local git_url
    git_url=$(yaml_get "$MANIFEST_FILE" "sdks.${sdk_name}.git.url" 2>/dev/null | tr -d '"') || true
    if [[ -n "$git_url" && "$git_url" != "null" ]]; then
        install_sdk_from_git "$sdk_name"
        return $?
    fi

    # Try archive download
    install_sdk_from_archive "$sdk_name"
    return $?
}

# ─── Setup common dependencies ───────────────────────────────────────────────
setup_common() {
    log_step "═══════════════════════════════════════════════════"
    log_step "Checking common dependencies"
    log_step "═══════════════════════════════════════════════════"

    local common_count
    common_count=$(yaml_get_list "$PREREQ_FILE" "common" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

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
            local pkg
            pkg=$(echo "$item" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('packages',{}).get('$OS_ID',''))" 2>/dev/null) || true
            pkg=$(echo "$pkg" | tr -d '"' | sed 's/^\[//;s/\]$//;s/,/ /g;s/  */ /g')

            if [[ -n "$pkg" && "$pkg" != "null" ]]; then
                if [[ "$CHECK_ONLY" == true ]]; then
                    log_warn "Would install: $pkg"
                else
                    install_system_packages "$pkg"
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

# ─── Setup git dependencies ──────────────────────────────────────────────────
setup_dependencies() {
    log_step "═══════════════════════════════════════════════════"
    log_step "Installing git dependencies"
    log_step "═══════════════════════════════════════════════════"

    # Get all dependency names
    local dep_names
    dep_names=$(yaml_get_list "$PREREQ_FILE" "dependencies" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for name in data.keys():
    print(name)
" 2>/dev/null) || true

    for dep_name in $dep_names; do
        local required
        required=$(yaml_get "$PREREQ_FILE" "dependencies.${dep_name}.required" 2>/dev/null) || true

        local git_url
        git_url=$(yaml_get "$PREREQ_FILE" "dependencies.${dep_name}.git.url" 2>/dev/null | tr -d '"') || true
        if [[ -z "$git_url" ]]; then
            log_warn "$dep_name has no git URL, skipping"
            continue
        fi

        local git_tag
        git_tag=$(yaml_get "$PREREQ_FILE" "dependencies.${dep_name}.git.tag" 2>/dev/null | tr -d '"') || {
            log_error "$dep_name has no git tag"
            if [[ "$required" == "true" ]]; then
                return 1
            fi
            continue
        }

        local dest
        dest=$(yaml_get "$PREREQ_FILE" "dependencies.${dep_name}.dest" 2>/dev/null | tr -d '"') || {
            log_error "$dep_name has no destination"
            if [[ "$required" == "true" ]]; then
                return 1
            fi
            continue
        }

        # Resolve full path
        local full_dest
        if [[ -n "$ABL_DEPS_PATH" ]]; then
            full_dest="$ABL_DEPS_PATH/$dep_name"
        else
            full_dest="$SCRIPT_DIR/$dest"
        fi

        clone_git_repo "$dep_name" "$git_url" "$git_tag" "$full_dest"
    done
}

# ─── Setup a single platform ─────────────────────────────────────────────────
setup_platform() {
    local platform="$1"
    log_step "═══════════════════════════════════════════════════"
    log_step "Setting up platform: $platform"
    log_step "═══════════════════════════════════════════════════"

    local toolchains_json
    toolchains_json=$(yaml_get_list "$MANIFEST_FILE" "platforms.${platform}") || {
        log_error "No toolchain definition for platform: $platform"
        return 1
    }

    local count
    count=$(echo "$toolchains_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    for ((i=0; i<count; i++)); do
        local tc_name
        tc_name=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d['name'])")

        log_info "Checking: $tc_name"

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

        # ESP-IDF special case
        if [[ "$tc_name" == "esp-idf" ]]; then
            local esp_install_dir
            esp_install_dir=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('install_dir',''))" 2>/dev/null | tr -d '"' | sed "s|~|$HOME|g") || true
            if [[ -n "$esp_install_dir" && -d "$esp_install_dir/.git" ]]; then
                log_ok "ESP-IDF already cloned at $esp_install_dir"
            else
                local esp_git_url
                esp_git_url=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('git',{}).get('url',''))" 2>/dev/null | tr -d '"') || true
                local esp_git_tag
                esp_git_tag=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('git',{}).get('tag',''))" 2>/dev/null | tr -d '"') || true
                if [[ -n "$esp_git_url" && -n "$esp_git_tag" ]]; then
                    clone_git_repo "ESP-IDF" "$esp_git_url" "$esp_git_tag" "$esp_install_dir"
                fi
            fi
            continue
        fi

        # Check system PATH
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

        # Check managed toolchain
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

        # Install if needed
        if [[ "$CHECK_ONLY" == true ]]; then
            log_warn "$tc_name not found — would be installed"
            continue
        fi

        # Try system packages first
        local sys_packages
        sys_packages=$(echo "$toolchains_json" | python3 -c "import sys,json; d=json.load(sys.stdin)[$i]; print(d.get('packages',{}).get('$OS_ID',''))" 2>/dev/null) || true
        sys_packages=$(echo "$sys_packages" | tr -d '"')

        if [[ -n "$sys_packages" && "$sys_packages" != "null" ]]; then
            log_info "Trying system packages for $tc_name..."
            if install_system_packages "$sys_packages"; then
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
            local os_key="${OS_ID}_${ARCH}"
            local download_info
            download_info=$(echo "$toolchains_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)[$i].get('download', {})
for k, v in d.items():
    if k == '$os_key':
        print(json.dumps(v))
        break
" 2>/dev/null) || true

            if [[ -n "$download_info" && "$download_info" != "null" ]]; then
                local url
                url=$(echo "$download_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
                local archive_type
                archive_type=$(echo "$download_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['archive_type'])")

                local dest_dir
                dest_dir=$(echo "$tc_install_dir" | sed "s|~|$HOME|g")

                local tmp_dir
                tmp_dir=$(mktemp -d)
                curl -L --progress-bar "$url" -o "$tmp_dir/archive"
                mkdir -p "$dest_dir"
                case "$archive_type" in
                    tar.xz)  tar -xJf "$tmp_dir/archive" -C "$dest_dir" --strip-components=1 ;;
                    tar.gz)  tar -xzf "$tmp_dir/archive" -C "$dest_dir" --strip-components=1 ;;
                    zip)     unzip -q "$tmp_dir/archive" -d "$dest_dir" ;;
                esac
                rm -rf "$tmp_dir"
                log_ok "Installed $tc_name to $dest_dir"
            else
                log_error "No download available for $tc_name on $os_key"
            fi
        else
            log_error "No installation method available for $tc_name on $OS_ID"
        fi
    done
}

# ─── Setup SDK for platform ──────────────────────────────────────────────────
setup_platform_sdk() {
    local platform="$1"
    local sub_platform="$2"

    log_info "Checking SDK for platform: $sub_platform"

    # Get SDK name from sdk_map
    local sdk_name=""

    # Try platform-specific map first (e.g. stm32_sdk_map for stm32)
    if [[ "$base_platform" == "stm32" ]]; then
        sdk_name=$(yaml_get "$MANIFEST_FILE" "platforms.stm32_sdk_map.${sub_platform}" 2>/dev/null | tr -d '"') || true
    fi

    if [[ -z "$sdk_name" || "$sdk_name" == "null" ]]; then
        log_warn "No SDK mapping for $sub_platform"
        return 0
    fi

    log_info "Required SDK: $sdk_name"

    # Check if installed
    if [[ "$FORCE" != true ]] && check_sdk_installed "$sdk_name"; then
        log_skip "SDK already installed"
        return 0
    fi

    install_sdk "$sdk_name"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    if [[ ! -f "$PREREQ_FILE" ]]; then
        log_error "Prerequisites file not found: $PREREQ_FILE"
        exit 1
    fi

    # Check python3 and PyYAML
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

    # Setup git dependencies if requested
    if [[ "$INSTALL_DEPS" == true ]]; then
        setup_dependencies
    fi

    # Платформа на месте → читаем её манифест (canonical SDK/toolchain pins)
    MANIFEST_FILE=$(manifest_file)
    log_info "Manifest: $MANIFEST_FILE"

    # Setup specific SDK if requested
    if [[ -n "$SPECIFIC_SDK" ]]; then
        install_sdk "$SPECIFIC_SDK"
    fi

    # Determine platforms to setup
    if [[ "$ALL_PLATFORMS" == true ]]; then
        PLATFORMS=($(yaml_get_list "$PREREQ_FILE" "platforms" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).keys()))"))
        log_info "Setting up all platforms: ${PLATFORMS[*]}"
    fi

    if [[ ${#PLATFORMS[@]} -eq 0 && -z "$SPECIFIC_SDK" && "$INSTALL_DEPS" != true ]]; then
        log_warn "No platform specified. Use -p PLATFORM, -d for dependencies, or -a for all."
        show_help
        exit 0
    fi

    # Setup each platform
    for platform in "${PLATFORMS[@]}"; do
        # Determine sub-platform for SDK mapping
        # For stm32f4 → platform=stm32, sub_platform=stm32f4
        local base_platform=""
        local sub_platform=""

        if [[ "$platform" == stm32* ]]; then
            base_platform="stm32"
            sub_platform="$platform"
        elif [[ "$platform" == "esp32" ]]; then
            base_platform="esp32"
            sub_platform="esp32"
        elif [[ "$platform" == "avr" ]]; then
            base_platform="avr"
            sub_platform="avr"
        else
            base_platform="$platform"
            sub_platform="$platform"
        fi

        setup_platform "$base_platform"
        setup_platform_sdk "$base_platform" "$sub_platform"
    done

    log_step ""
    log_ok "Setup complete!"

    if [[ "$CHECK_ONLY" == true ]]; then
        log_info "This was a dry-run. Remove --check-only to actually install."
    fi

    # Print summary
    if [[ "$INSTALL_DEPS" == true ]]; then
        log_info ""
        log_info "Dependencies installed to:"
        if [[ -n "$ABL_DEPS_PATH" ]]; then
            log_info "  $ABL_DEPS_PATH/"
        else
            log_info "  $SCRIPT_DIR/lib/"
        fi
    fi
}

main
