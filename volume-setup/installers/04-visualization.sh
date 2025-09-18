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
    
    # Install xvfb for headless software rendering
    log_info "Installing xvfb for headless rendering support..."
    install_apt_packages xvfb
    
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
    
    # Extract (with progress if pv is available)
    log_info "Extracting ParaView..."
    if command -v pv &> /dev/null; then
        PV_SIZE=$(stat -c%s "${PV_ARCHIVE}" 2>/dev/null || echo "")
        if [ -n "$PV_SIZE" ]; then
            pv -s "$PV_SIZE" "${PV_ARCHIVE}" | tar -xz -f -
        else
            pv "${PV_ARCHIVE}" | tar -xz -f -
        fi
    else
        tar -xzf "${PV_ARCHIVE}"
    fi
    rm -f "${PV_ARCHIVE}"
    
    # Find extracted directory
    PV_DIR=$(ls -d ParaView-* | head -n1)
    
    # Copy to standard locations
    log_info "Installing ParaView to standard locations..."
    [ -d "${PV_DIR}/bin" ] && cp -r ${PV_DIR}/bin/* "${DEPS_BIN}/" 2>/dev/null || true
    [ -d "${PV_DIR}/lib" ] && cp -r ${PV_DIR}/lib/* "${DEPS_LIB}/" 2>/dev/null || true
    [ -d "${PV_DIR}/include" ] && mkdir -p "${DEPS_INCLUDE}/paraview" && cp -r ${PV_DIR}/include/* "${DEPS_INCLUDE}/paraview/" 2>/dev/null || true
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
# ParaView server wrapper with smart MPI defaults and GPU preference
#
# Usage:
#   pvserver-headless                    # Auto-detect MPI procs based on cores
#   PV_MPI_PROCS=1 pvserver-headless    # Force single process (no MPI)
#   PV_MPI_PROCS=8 pvserver-headless    # Force 8 MPI processes
#   PV_MPI_PROCS=max pvserver-headless  # Use all available cores
#   PV_BACKEND=egl pvserver-headless    # Force EGL backend
#   PV_BACKEND=xvfb pvserver-headless   # Force Xvfb backend

DEPS_BIN="$(dirname "$0")"

# Smart MPI process count detection
if [ -z "$PV_MPI_PROCS" ]; then
    # Auto-detect optimal MPI process count
    AVAILABLE_CORES=$(nproc)

    if [ "$AVAILABLE_CORES" -ge 8 ]; then
        # Plenty of cores - use half for ParaView (leave half for other work)
        PV_MPI_PROCS=$((AVAILABLE_CORES / 2))
    elif [ "$AVAILABLE_CORES" -ge 4 ]; then
        # Moderate cores - use most but leave one for system
        PV_MPI_PROCS=$((AVAILABLE_CORES - 1))
    else
        # Few cores - just use 1 (no MPI)
        PV_MPI_PROCS=1
    fi

    echo "[pvserver] Auto-detected $AVAILABLE_CORES cores, using $PV_MPI_PROCS MPI processes" >&2
elif [ "$PV_MPI_PROCS" = "max" ]; then
    # User wants maximum parallelism
    PV_MPI_PROCS=$(nproc)
    echo "[pvserver] Using maximum parallelism: $PV_MPI_PROCS MPI processes" >&2
fi

# Build the pvserver command with common flags
PVSERVER_CMD="${DEPS_BIN}/pvserver --disable-xdisplay-test"

# Apply MPI if more than 1 process requested
if [ "$PV_MPI_PROCS" -gt 1 ] 2>/dev/null; then
    # Check if mpirun is available
    if command -v mpirun &> /dev/null; then
        PVSERVER_CMD="mpirun -np $PV_MPI_PROCS $PVSERVER_CMD"
        echo "[pvserver] Running with MPI: $PV_MPI_PROCS processes" >&2
    else
        echo "[pvserver] Warning: mpirun not found, falling back to single process" >&2
        echo "[pvserver] Install MPI with: apt-get install libopenmpi-bin" >&2
    fi
elif [ "$PV_MPI_PROCS" = "1" ]; then
    echo "[pvserver] Running single process (MPI disabled)" >&2
fi

# Auto-detect best rendering backend
if [ -z "$DISPLAY" ]; then
    # No display - determine best backend
    if [ -z "$PV_BACKEND" ] || [ "$PV_BACKEND" = "auto" ]; then
        # Check for GPU and EGL support
        if [ -e "/dev/nvidia0" ] || [ -n "$NVIDIA_VISIBLE_DEVICES" ]; then
            if ldd "${DEPS_BIN}/pvserver" 2>/dev/null | grep -q libEGL; then
                PV_BACKEND="egl"
            else
                PV_BACKEND="xvfb"
            fi
        else
            PV_BACKEND="xvfb"
        fi
    fi

    case "$PV_BACKEND" in
        egl)
            # Prefer EGL for GPU rendering - no Xvfb needed!
            echo "[pvserver] Using EGL GPU rendering (hardware accelerated)" >&2
            exec $PVSERVER_CMD --force-offscreen-rendering "$@"
            ;;
        xvfb|*)
            # Fall back to Xvfb software rendering with better resolution
            echo "[pvserver] Using Xvfb software rendering" >&2
            exec xvfb-run -a -s "-screen 0 1920x1080x24" $PVSERVER_CMD "$@"
            ;;
    esac
else
    # Display available - use it
    echo "[pvserver] Using display $DISPLAY" >&2
    exec $PVSERVER_CMD "$@"
fi
EOF
    chmod +x "${DEPS_BIN}/pvserver-headless"
    
    # Check EGL support
    log_info "Checking ParaView rendering backend support..."
    if ldd "${DEPS_BIN}/pvserver" 2>/dev/null | grep -q libEGL; then
        log_success "ParaView supports EGL rendering"
    else
        log_info "ParaView using software rendering via xvfb (installed)"
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

# Performance recommendations
cat << 'EOF'

=================================================================
ParaView Performance Optimization Tips:
=================================================================

SERVER SIDE (already configured):
  ✓ Smart MPI auto-detection (uses half of available cores)
  ✓ EGL GPU rendering when available
  ✓ Optimized resolution (1920x1080)
  ✓ Display test skipping for faster startup

CLIENT SIDE (configure in ParaView GUI):
  1. Enable Image Compression:
     Edit > Settings > Render View > Image Compression
     - Select "LZ4" for fast compression
     - Or "NVPipe" if you have NVIDIA GPU

  2. Enable Interactive Subsampling:
     Edit > Settings > Render View > Interactive Rendering
     - Set "Image Reduction Factor" to 2 or 4
     - Reduces resolution during rotation/zoom

  3. For Large Data (>1GB):
     - Apply D3 filter immediately after loading
     - This distributes data across MPI processes

USAGE EXAMPLES:
  pvserver-headless                    # Auto-detect cores
  PV_MPI_PROCS=1 pvserver-headless    # Debug mode (no MPI)
  PV_MPI_PROCS=max pvserver-headless  # Maximum performance
  PV_BACKEND=egl pvserver-headless    # Force GPU rendering
=================================================================
EOF