#!/bin/bash
# Core libraries installer
# Builds and installs Palabos (CFD) and geometry-central (mesh processing)

set -e

# Get script directory and source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"
source "${SCRIPT_DIR}/../lib/common.sh"

log_section "Core Libraries Installation"

# ============================================================================
# Palabos-hybrid (CFD Library)
# ============================================================================
install_palabos() {
    log_info "Installing Palabos-hybrid CFD library..."
    
    if is_installed "palabos-hybrid"; then
        log_info "Palabos-hybrid already installed"
        return 0
    fi
    
    cd /tmp
    rm -rf palabos-hybrid
    
    # Clone repository
    clone_repo "${PALABOS_REPO}" "palabos-hybrid" "Palabos-hybrid"
    cd palabos-hybrid
    
    # Disable examples to speed up build
    log_info "Configuring Palabos build..."
    sed -i -E 's|^[[:space:]]*add_subdirectory[[:space:]]*\([[:space:]]*examples/|# DISABLED: &|g' CMakeLists.txt
    
    # Configure with CMake
    # Use system g++ + system MPI for reliable Palabos build
    # NVIDIA compilers will be used later for actual CFD development
    mkdir -p build
    cd build
    
    # Install system MPI for building (if not already available)
    if ! command -v mpirun &> /dev/null; then
        log_info "Installing system MPI for build..."
        apt-get update && apt-get install -y libopenmpi-dev
    fi
    
    cmake .. \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
        -DCMAKE_CXX_COMPILER="${DEFAULT_CXX_COMPILER}" \
        -DCMAKE_CXX_STANDARD="${CMAKE_CXX_STANDARD}" \
        -DPALABOS_ENABLE_MPI=ON \
        -DPALABOS_ENABLE_CUDA=OFF \
        -DBUILD_HDF5=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -G Ninja
    
    # Build library
    log_info "Building Palabos (this will take 10-15 minutes)..."
    ninja -j${BUILD_JOBS} palabos
    
    # Install library
    log_info "Installing Palabos library..."
    if [ ! -f "libpalabos.a" ]; then
        # Find the library in build directory
        PALABOS_LIB=$(find . -name "libpalabos.a" -print -quit)
        if [ -z "$PALABOS_LIB" ]; then
            log_error "libpalabos.a not found after build"
        fi
        cp "$PALABOS_LIB" "${DEPS_LIB}/"
    else
        cp libpalabos.a "${DEPS_LIB}/"
    fi
    
    # Install headers
    log_info "Installing Palabos headers..."
    cd ..
    mkdir -p "${DEPS_INCLUDE}/palabos"
    cp -r src/* "${DEPS_INCLUDE}/palabos/"
    cp -r externalLibraries "${DEPS_INCLUDE}/palabos/"
    
    # Verify installation
    verify_file_exists "${DEPS_LIB}/libpalabos.a" "Palabos library"
    PALABOS_HEADERS=$(find "${DEPS_INCLUDE}/palabos" -name "*.h" -o -name "*.hh" | wc -l)
    log_success "Palabos installed: ${PALABOS_HEADERS} header files"
    
    # Clean up
    cd /tmp
    rm -rf palabos-hybrid
    
    mark_installed "palabos-hybrid"
}

# ============================================================================
# geometry-central (Mesh Processing Library)
# ============================================================================
install_geometry_central() {
    log_info "Installing geometry-central mesh processing library..."
    
    if is_installed "geometry-central"; then
        log_info "geometry-central already installed"
        return 0
    fi
    
    cd /tmp
    rm -rf geometry-central
    
    # Clone repository
    clone_repo "${GEOMETRY_CENTRAL_REPO}" "geometry-central" "geometry-central"
    cd geometry-central
    
    # Configure with CMake
    mkdir -p build
    cd build
    cmake .. \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
        -DCMAKE_CXX_COMPILER="${DEFAULT_CXX_COMPILER}" \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_INSTALL_PREFIX="${DEPS_ROOT}" \
        -G Ninja
    
    # Build and install
    log_info "Building geometry-central..."
    ninja -j${BUILD_JOBS} install
    
    # Verify installation
    verify_file_exists "${DEPS_LIB}/libgeometry-central.a" "geometry-central library"
    if [ -d "${DEPS_INCLUDE}/geometrycentral" ]; then
        GC_HEADERS=$(find "${DEPS_INCLUDE}/geometrycentral" -name "*.h" -o -name "*.ipp" | wc -l)
        log_success "geometry-central installed: ${GC_HEADERS} header files"
    else
        log_warning "geometry-central headers may not have installed correctly"
    fi
    
    # Clean up
    cd /tmp
    rm -rf geometry-central
    
    mark_installed "geometry-central"
}

# ============================================================================
# Main execution
# ============================================================================

# Install Palabos if enabled
if [ "${INSTALL_PALABOS}" == "true" ]; then
    install_palabos
else
    log_info "Palabos installation disabled in config"
fi

# Install geometry-central if enabled
if [ "${INSTALL_GEOMETRY_CENTRAL}" == "true" ]; then
    install_geometry_central
else
    log_info "geometry-central installation disabled in config"
fi

# Strip debug symbols from static libraries to save space
log_info "Optimizing library sizes..."
find "${DEPS_LIB}" -name "*.a" -exec strip -g {} \; 2>/dev/null || true

# Update environment file
log_info "Updating environment configuration..."
cat >> "${DEPS_ROOT}/env.sh" << 'EOF'

# Core libraries
export PALABOS_INCLUDE="${DEPS_INCLUDE}/palabos"
export GEOMETRY_CENTRAL_INCLUDE="${DEPS_INCLUDE}/geometrycentral"
EOF

log_success "Core libraries installation complete"
log_info "Installed libraries:"
log_info "  - Palabos CFD: ${DEPS_LIB}/libpalabos.a"
log_info "  - geometry-central: ${DEPS_LIB}/libgeometry-central.a"