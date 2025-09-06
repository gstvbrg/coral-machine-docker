#!/bin/bash
# Visualization tools installer
# Installs ParaView server (headless) and Polyscope headers

set -e

# Get script directory and source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"
source "${SCRIPT_DIR}/../lib/common.sh"

log_section "Visualization Tools Installation"

# ============================================================================
# ParaView Server (Headless)
# ============================================================================
install_paraview() {
    log_info "Installing ParaView ${PARAVIEW_VERSION} server..."
    
    if is_installed "paraview-${PARAVIEW_VERSION}"; then
        log_info "ParaView ${PARAVIEW_VERSION} already installed"
        return 0
    fi
    
    cd /tmp
    
    # Determine architecture
    ARCH="$(dpkg --print-architecture)"
    if [ "$ARCH" = "amd64" ]; then
        PARAVIEW_URL="https://www.paraview.org/files/v6.0/ParaView-${PARAVIEW_VERSION}-MPI-Linux-Python3.12-x86_64.tar.gz"
    else
        PARAVIEW_URL="https://www.paraview.org/files/v6.0/ParaView-${PARAVIEW_VERSION}-MPI-Linux-Python3.9-${ARCH}.tar.gz"
    fi
    
    # Download ParaView
    PV_ARCHIVE="paraview-${PARAVIEW_VERSION}.tar.gz"
    download_file "${PARAVIEW_URL}" "${PV_ARCHIVE}" "ParaView ${PARAVIEW_VERSION}"
    
    # Extract
    log_info "Extracting ParaView..."
    tar -xzf "${PV_ARCHIVE}"
    rm -f "${PV_ARCHIVE}"
    
    # Find extracted directory
    PV_DIR=$(ls -d ParaView-* | head -n1)
    
    # Copy to standard locations
    log_info "Installing ParaView to standard locations..."
    [ -d "${PV_DIR}/bin" ] && cp -r ${PV_DIR}/bin/* "${DEPS_BIN}/" 2>/dev/null || true
    [ -d "${PV_DIR}/lib" ] && cp -r ${PV_DIR}/lib/* "${DEPS_LIB}/" 2>/dev/null || true
    [ -d "${PV_DIR}/include" ] && cp -r ${PV_DIR}/include/* "${DEPS_INCLUDE}/" 2>/dev/null || true
    [ -d "${PV_DIR}/share" ] && cp -r ${PV_DIR}/share/* "${DEPS_SHARE}/" 2>/dev/null || true
    
    # Remove GUI applications (keep only server components)
    log_info "Optimizing for headless operation..."
    rm -f "${DEPS_BIN}"/paraview* 2>/dev/null || true
    rm -rf "${DEPS_SHARE}"/icons 2>/dev/null || true
    rm -rf "${DEPS_SHARE}"/applications 2>/dev/null || true
    
    # Create pvserver wrapper for headless operation
    log_info "Creating headless pvserver wrapper..."
    cat > "${DEPS_BIN}/pvserver-headless" << 'EOF'
#!/bin/bash
# ParaView server wrapper for headless operation

if [ -z "$DISPLAY" ]; then
    # No display - use software rendering
    export PV_BACKEND=${PV_BACKEND:-xvfb}
    if [ "$PV_BACKEND" = "xvfb" ]; then
        # Use Xvfb for software rendering
        xvfb-run -a -s "-screen 0 1024x768x24" "${DEPS_BIN}/pvserver" "$@"
    else
        # Try EGL/OSMesa offscreen rendering
        "${DEPS_BIN}/pvserver" --force-offscreen-rendering "$@"
    fi
else
    # Display available - use it
    "${DEPS_BIN}/pvserver" "$@"
fi
EOF
    chmod +x "${DEPS_BIN}/pvserver-headless"
    
    # Check EGL support
    log_info "Checking ParaView rendering backend support..."
    if ldd "${DEPS_BIN}/pvserver" 2>/dev/null | grep -q libEGL; then
        log_success "ParaView supports EGL rendering"
    else
        log_warning "ParaView using software rendering (install xvfb for headless)"
    fi
    
    # Verify installation
    if [ -f "${DEPS_BIN}/pvserver" ]; then
        log_success "pvserver installed at ${DEPS_BIN}/pvserver"
    else
        log_error "pvserver not found after installation"
    fi
    
    # Clean up
    rm -rf "${PV_DIR}"
    
    mark_installed "paraview-${PARAVIEW_VERSION}"
}

# ============================================================================
# Polyscope (Visualization Headers)
# ============================================================================
install_polyscope() {
    log_info "Installing Polyscope visualization headers..."
    
    if is_installed "polyscope-headers"; then
        log_info "Polyscope headers already installed"
        return 0
    fi
    
    cd /tmp
    rm -rf polyscope
    
    # Clone repository
    clone_repo "${POLYSCOPE_REPO}" "polyscope" "Polyscope"
    cd polyscope
    
    # Copy headers (header-only library)
    log_info "Installing Polyscope headers..."
    cp -r include/polyscope "${DEPS_INCLUDE}/"
    
    # Also copy imgui headers if present (Polyscope dependency)
    IMGUI_DIR=$(find deps -type d -name imgui 2>/dev/null | head -n1)
    if [ -n "$IMGUI_DIR" ] && [ -d "$IMGUI_DIR" ]; then
        log_info "Installing ImGui headers (Polyscope dependency)..."
        mkdir -p "${DEPS_INCLUDE}/imgui"
        find "$IMGUI_DIR" -name "*.h" -exec cp {} "${DEPS_INCLUDE}/imgui/" \; 2>/dev/null || true
    fi
    
    # Copy implot headers if present
    IMPLOT_DIR=$(find deps -type d -name implot 2>/dev/null | head -n1)
    if [ -n "$IMPLOT_DIR" ] && [ -d "$IMPLOT_DIR" ]; then
        log_info "Installing ImPlot headers..."
        mkdir -p "${DEPS_INCLUDE}/implot"
        find "$IMPLOT_DIR" -name "*.h" -exec cp {} "${DEPS_INCLUDE}/implot/" \; 2>/dev/null || true
    fi
    
    # Verify installation
    if [ -d "${DEPS_INCLUDE}/polyscope" ]; then
        POLY_HEADERS=$(find "${DEPS_INCLUDE}/polyscope" -name "*.h" | wc -l)
        log_success "Polyscope installed: ${POLY_HEADERS} header files"
    else
        log_warning "Polyscope headers may not have installed correctly"
    fi
    
    # Clean up
    cd /tmp
    rm -rf polyscope
    
    mark_installed "polyscope-headers"
}

# ============================================================================
# Main execution
# ============================================================================

# Install ParaView if enabled
if [ "${INSTALL_PARAVIEW}" == "true" ]; then
    install_paraview
else
    log_info "ParaView installation disabled in config"
fi

# Install Polyscope if enabled
if [ "${INSTALL_POLYSCOPE}" == "true" ]; then
    install_polyscope
else
    log_info "Polyscope installation disabled in config"
fi

# Update environment file
log_info "Updating environment configuration..."
cat >> "${DEPS_ROOT}/env.sh" << 'EOF'

# Visualization tools
export POLYSCOPE_INCLUDE="${DEPS_INCLUDE}/polyscope"
export IMGUI_INCLUDE="${DEPS_INCLUDE}/imgui"

# ParaView configuration
export PV_BACKEND="${PV_BACKEND:-xvfb}"
EOF

log_success "Visualization tools installation complete"
log_info "Installed components:"
log_info "  - ParaView server: ${DEPS_BIN}/pvserver"
log_info "  - ParaView wrapper: ${DEPS_BIN}/pvserver-headless"
log_info "  - Polyscope headers: ${DEPS_INCLUDE}/polyscope/"
log_info "  - ImGui headers: ${DEPS_INCLUDE}/imgui/"