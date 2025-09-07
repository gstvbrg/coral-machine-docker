#!/bin/bash
# Build headers installer
# Installs development headers needed for compilation (Eigen3, OpenGL, X11, etc.)

set -e

# Get script directory and source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"
source "${SCRIPT_DIR}/../lib/common.sh"

log_section "Development Headers Installation"

# Check if already installed
if is_installed "build-headers"; then
    log_info "Build headers already installed"
    exit 0
fi

# Install development packages to extract headers
log_info "Installing development packages..."
install_apt_packages \
    libeigen3-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libx11-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxi-dev \
    libxext-dev \
    libtbb-dev

# Copy Eigen3 headers
if [ "${INSTALL_EIGEN3}" == "true" ]; then
    copy_headers "/usr/include/eigen3" "Eigen3"
fi

# Copy OpenGL headers
if [ "${INSTALL_GL_HEADERS}" == "true" ]; then
    copy_headers "/usr/include/GL" "OpenGL"
    copy_headers "/usr/include/KHR" "OpenGL KHR"
fi

# Copy X11 headers
log_info "Copying X11 headers..."
for x11_dir in X11 xcb; do
    copy_headers "/usr/include/${x11_dir}" "${x11_dir}"
done

# Copy TBB headers (optional for parallel algorithms)
copy_headers "/usr/include/tbb" "TBB"
copy_headers "/usr/include/oneapi" "oneAPI TBB"

# HDF5 headers removed - only needed for Palabos examples we don't compile
# Saves space and reduces complexity

# Copy essential shared libraries that might be needed at runtime
log_info "Copying essential runtime libraries..."
# TBB might be needed by ParaView for parallel rendering
copy_libraries "libtbb.so*" "TBB libraries"
# HDF5 removed - not needed without Palabos examples

# pkg-config directory removed - not used in our build system

# Update environment file with include paths
log_info "Updating environment configuration..."
cat >> "${DEPS_ROOT}/env.sh" << 'EOF'

# Include paths for compilation
export CPLUS_INCLUDE_PATH="${DEPS_INCLUDE}:${DEPS_INCLUDE}/eigen3:${CPLUS_INCLUDE_PATH:-}"
export C_INCLUDE_PATH="${DEPS_INCLUDE}:${C_INCLUDE_PATH:-}"
EOF

# Verify critical headers
log_info "Verifying header installation..."
if [ -d "${DEPS_INCLUDE}/eigen3" ]; then
    EIGEN_COUNT=$(find "${DEPS_INCLUDE}/eigen3" -name "*.h" | wc -l)
    log_success "Eigen3: ${EIGEN_COUNT} header files"
else
    log_warning "Eigen3 headers not found"
fi

if [ -d "${DEPS_INCLUDE}/GL" ]; then
    GL_COUNT=$(find "${DEPS_INCLUDE}/GL" -name "*.h" | wc -l)
    log_success "OpenGL: ${GL_COUNT} header files"
else
    log_warning "OpenGL headers not found"
fi

if [ -d "${DEPS_INCLUDE}/X11" ]; then
    X11_COUNT=$(find "${DEPS_INCLUDE}/X11" -name "*.h" | wc -l)
    log_success "X11: ${X11_COUNT} header files"
else
    log_warning "X11 headers not found"
fi

# Mark as installed
mark_installed "build-headers"

log_success "Development headers installation complete"
log_info "Headers available in: ${DEPS_INCLUDE}/"
log_info "Key components:"
log_info "  - Eigen3 (linear algebra)"
log_info "  - OpenGL/GLU (graphics)"
log_info "  - X11 (windowing)"
log_info "  - TBB (parallelization)"