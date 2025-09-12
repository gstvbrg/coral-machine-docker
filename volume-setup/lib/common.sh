#!/bin/bash
# Shared functions for all installer scripts
# Provides logging, error handling, and utility functions

# ============================================================================
# Logging Functions
# ============================================================================
log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

log_warning() {
    echo "⚠️  WARNING: $1"
}

log_section() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

# ============================================================================
# Installation State Management
# ============================================================================
is_installed() {
    local marker_file="$1"
    [[ -f "${MARKER_DIR}/${marker_file}" ]]
}

mark_installed() {
    local marker_file="$1"
    mkdir -p "${MARKER_DIR}"
    echo "$(date)" > "${MARKER_DIR}/${marker_file}"
    log_success "Marked ${marker_file} as installed"
}

# ============================================================================
# Directory Management
# ============================================================================
ensure_deps_structure() {
    log_info "Creating standard directory structure..."
    mkdir -p "$DEPS_BIN" "$DEPS_LIB" "$DEPS_INCLUDE" "$DEPS_SHARE" "$MARKER_DIR"
    mkdir -p "$CCACHE_DIR" "$BUILD_DIR" "$SOURCE_DIR" "$VTK_DIR"
}

clean_temp_files() {
    log_info "Cleaning temporary files..."
    cd /tmp
    rm -rf nvhpc* paraview* geometry-central polyscope palabos-hybrid build
}

# ============================================================================
# Download Functions
# ============================================================================
download_file() {
    local url="$1"
    local output="$2"
    local description="${3:-file}"
    
    log_info "Downloading ${description}..."
    
    # RunPod optimized download approach:
    # 1. Use aria2c if available (much faster for large files)
    # 2. Fall back to curl with resume support
    # 3. Fall back to wget as last resort
    
    if command -v aria2c &> /dev/null; then
        # aria2c is recommended by RunPod for fastest downloads
        # -x 16: Use 16 connections per download
        # -s 16: Split file into 16 segments
        # -k 1M: Min split size 1MB
        # --file-allocation=none: Faster on network volumes
        log_info "Using aria2c for optimized download (RunPod recommended)..."
        if ! aria2c -x 16 -s 16 -k 1M --file-allocation=none --console-log-level=warn -o "$output" "$url"; then
            log_error "Failed to download with aria2c from: $url"
            return 1
        fi
    elif command -v curl &> /dev/null; then
        # curl with resume support
        log_info "Using curl with resume support..."
        if ! curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "$output" "$url"; then
            log_error "Failed to download with curl from: $url"
            return 1
        fi
    else
        # wget as fallback with better options
        log_info "Using wget..."
        if ! wget --timeout=60 --tries=3 -c --show-progress -O "$output" "$url"; then
            log_error "Failed to download with wget from: $url"
            return 1
        fi
    fi
    
    # Verify file exists
    if [ ! -f "$output" ]; then
        log_error "Download failed - output file not found: $output"
        return 1
    fi
    
    return 0
}

download_and_extract() {
    local url="$1"
    local extract_dir="$2"
    local description="${3:-archive}"
    
    local temp_file="/tmp/$(basename "$url")"
    
    # Check if download succeeds
    if ! download_file "$url" "$temp_file" "$description"; then
        log_error "Failed to download ${description}"
        return 1
    fi
    
    log_info "Extracting ${description}..."
    case "$temp_file" in
        *.tar.gz|*.tgz)
            if ! tar -xzf "$temp_file" -C "$extract_dir"; then
                log_error "Failed to extract tar.gz: $temp_file"
                return 1
            fi
            ;;
        *.tar.bz2)
            if ! tar -xjf "$temp_file" -C "$extract_dir"; then
                log_error "Failed to extract tar.bz2: $temp_file"
                return 1
            fi
            ;;
        *.zip)
            if ! unzip -q "$temp_file" -d "$extract_dir"; then
                log_error "Failed to extract zip: $temp_file"
                return 1
            fi
            ;;
        *)
            log_error "Unknown archive format: $temp_file"
            return 1
            ;;
    esac
    
    rm -f "$temp_file"
    return 0
}

# ============================================================================
# Git Functions
# ============================================================================
clone_repo() {
    local repo_url="$1"
    local target_dir="$2"
    local description="${3:-repository}"
    
    log_info "Cloning ${description}..."
    if ! git clone --depth 1 --recursive "$repo_url" "$target_dir"; then
        log_error "Failed to clone repository: $repo_url"
    fi
}

# ============================================================================
# Build Functions
# ============================================================================
run_cmake() {
    local source_dir="$1"
    local build_dir="$2"
    shift 2
    local cmake_args="$@"
    
    log_info "Configuring with CMake..."
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    if ! cmake "$source_dir" \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
        -DCMAKE_INSTALL_PREFIX="${DEPS_ROOT}" \
        $cmake_args; then
        log_error "CMake configuration failed"
    fi
}

run_build() {
    local build_dir="$1"
    local target="${2:-all}"
    
    log_info "Building ${target}..."
    cd "$build_dir"
    
    if command -v ninja &> /dev/null; then
        ninja -j${BUILD_JOBS} ${target}
    elif command -v make &> /dev/null; then
        make -j${BUILD_JOBS} ${target}
    else
        log_error "No build system found (ninja or make)"
    fi
}

# ============================================================================
# Permission Functions
# ============================================================================
fix_permissions() {
    local path="${1:-$WORKSPACE_ROOT}"
    log_info "Setting permissions for dev user on ${path}..."
    
    # Check if we need sudo (not running as root)
    local SUDO=""
    if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
        SUDO="sudo"
    fi
    
    $SUDO chown -R ${DEV_USER_UID}:${DEV_USER_GID} "$path"
    $SUDO chmod -R u+rw,g+r,o+r "$path"
}

# ============================================================================
# Validation Functions
# ============================================================================
check_volume_mounted() {
    # Check if /workspace exists (the volume mount point)
    if [ ! -d "/workspace" ]; then
        log_error "Volume not mounted at /workspace"
    fi
    # Create deps directory if it doesn't exist
    if [ ! -d "$DEPS_ROOT" ]; then
        mkdir -p "$DEPS_ROOT"
        log_info "Created $DEPS_ROOT directory"
    fi
}

verify_file_exists() {
    local file_path="$1"
    local description="${2:-file}"
    
    if [ ! -f "$file_path" ]; then
        log_error "${description} not found at: $file_path"
    fi
}

verify_dir_exists() {
    local dir_path="$1"
    local description="${2:-directory}"
    
    if [ ! -d "$dir_path" ]; then
        log_error "${description} not found at: $dir_path"
    fi
}

# ============================================================================
# Package Management
# ============================================================================
install_apt_packages() {
    local packages="$@"
    log_info "Installing system packages..."
    
    # Check if we need sudo (not running as root)
    local SUDO=""
    if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
        SUDO="sudo"
        log_info "Using sudo for package installation"
    fi
    
    # Update package list
    if ! $SUDO apt-get update; then
        log_error "Failed to update package list"
    fi
    
    # Install packages
    if ! $SUDO apt-get install -y --no-install-recommends $packages; then
        log_error "Failed to install packages: $packages"
    fi
}

# ============================================================================
# Header/Library Copy Functions
# ============================================================================
copy_headers() {
    local src_dir="$1"
    local dest_name="$2"
    
    if [ -d "$src_dir" ]; then
        log_info "Copying ${dest_name} headers..."
        cp -r "$src_dir" "${DEPS_INCLUDE}/"
        log_success "${dest_name} headers installed"
    else
        log_warning "${dest_name} headers not found at ${src_dir}"
    fi
}

copy_libraries() {
    local pattern="$1"
    local description="${2:-libraries}"
    
    log_info "Copying ${description}..."
    find /usr/lib -name "$pattern" -exec cp {} "${DEPS_LIB}/" \; 2>/dev/null || true
}