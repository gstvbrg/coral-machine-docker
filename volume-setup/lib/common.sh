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
    if ! wget -q --show-progress -O "$output" "$url"; then
        log_error "Failed to download from: $url"
    fi
}

download_and_extract() {
    local url="$1"
    local extract_dir="$2"
    local description="${3:-archive}"
    
    local temp_file="/tmp/$(basename "$url")"
    download_file "$url" "$temp_file" "$description"
    
    log_info "Extracting ${description}..."
    case "$temp_file" in
        *.tar.gz|*.tgz)
            tar -xzf "$temp_file" -C "$extract_dir"
            ;;
        *.tar.bz2)
            tar -xjf "$temp_file" -C "$extract_dir"
            ;;
        *.zip)
            unzip -q "$temp_file" -d "$extract_dir"
            ;;
        *)
            log_error "Unknown archive format: $temp_file"
            ;;
    esac
    
    rm -f "$temp_file"
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
    chown -R ${DEV_USER_UID}:${DEV_USER_GID} "$path"
    chmod -R u+rw,g+r,o+r "$path"
}

# ============================================================================
# Validation Functions
# ============================================================================
check_volume_mounted() {
    if [ ! -d "$DEPS_ROOT" ]; then
        log_error "Volume not mounted at $DEPS_ROOT"
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
    apt-get update > /dev/null 2>&1
    if ! apt-get install -y --no-install-recommends $packages > /dev/null 2>&1; then
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