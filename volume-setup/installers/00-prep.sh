#!/bin/bash
# Preparation script - sets up build environment and tools
# Must run first to establish directory structure and ccache

set -e

# Get script directory and source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"
source "${SCRIPT_DIR}/../lib/common.sh"

log_section "Build Environment Preparation"

# Check if already done
if is_installed "build-environment"; then
    log_info "Build environment already prepared"
    exit 0
fi

# Create directory structure
ensure_deps_structure

# Setup ccache for faster rebuilds
log_info "Configuring ccache (${CCACHE_SIZE} cache)..."
mkdir -p "${CCACHE_DIR}"
cat > "${CCACHE_DIR}/ccache.conf" << EOF
max_size = ${CCACHE_SIZE}
compression = true
compiler_check = content
hash_dir = false
EOF

# Set up ccache symlinks for common compilers
if command -v ccache &> /dev/null; then
    mkdir -p "${DEPS_BIN}"
    for compiler in gcc g++ cc c++ nvc++ nvcc; do
        if [ ! -L "${DEPS_BIN}/${compiler}" ]; then
            ln -sf $(which ccache) "${DEPS_BIN}/${compiler}" 2>/dev/null || true
        fi
    done
    log_success "ccache configured with compiler symlinks"
else
    log_warning "ccache not found - builds will be slower"
fi

# Clean any previous failed attempts
clean_temp_files

# Initialize build tools
log_info "Checking build tools..."
for tool in cmake ninja git wget; do
    if command -v $tool &> /dev/null; then
        log_success "$tool: $(which $tool)"
    else
        log_warning "$tool not found - some installers may fail"
    fi
done

# Create initial environment file (will be updated by other installers)
log_info "Creating initial environment file..."
cat > "${DEPS_ROOT}/env.sh" << 'EOF'
#!/bin/bash
# Coral Machine Development Environment
# This file is auto-generated and updated by installers

# Core paths
export DEPS_ROOT="/workspace/deps"
export DEPS_BIN="${DEPS_ROOT}/bin"
export DEPS_LIB="${DEPS_ROOT}/lib"
export DEPS_INCLUDE="${DEPS_ROOT}/include"

# Build configuration
export CMAKE_PREFIX_PATH="${DEPS_ROOT}"
export CCACHE_DIR="/workspace/.ccache"
export CCACHE_MAXSIZE="10G"

# Initial paths (will be extended by other installers)
export PATH="${DEPS_BIN}:$PATH"
export LD_LIBRARY_PATH="${DEPS_LIB}:$LD_LIBRARY_PATH"
export LIBRARY_PATH="${DEPS_LIB}:$LIBRARY_PATH"

echo "Coral Machine environment loaded"
EOF

chmod +x "${DEPS_ROOT}/env.sh"

# Mark as complete
mark_installed "build-environment"

log_success "Build environment prepared successfully"
log_info "Directory structure:"
log_info "  ${DEPS_BIN}/ - Executables"
log_info "  ${DEPS_LIB}/ - Libraries"
log_info "  ${DEPS_INCLUDE}/ - Headers"
log_info "  ${CCACHE_DIR}/ - Build cache"