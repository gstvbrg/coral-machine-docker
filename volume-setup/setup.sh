#!/bin/bash
# Main orchestrator for Coral Machine volume setup
# Runs all installers in sequence and manages permissions

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/common.sh"

# ============================================================================
# Pre-flight checks
# ============================================================================
log_section "Coral Machine Volume Setup"
log_info "This will install all dependencies to ${DEPS_ROOT}"
log_info "Estimated time: 30-45 minutes"
echo ""

# Check if volume is mounted
check_volume_mounted

# Check if already initialized
if [ -f "${DEPS_ROOT}/.setup-complete" ]; then
    log_warning "Volume appears to be already set up"
    log_info "To re-run setup, remove ${DEPS_ROOT}/.setup-complete"
    
    # Non-interactive mode for RunPod (check for RUNPOD env var or CI env var)
    if [ -n "${RUNPOD}" ] || [ -n "${CI}" ] || [ -n "${NONINTERACTIVE}" ]; then
        log_info "Non-interactive mode - skipping already initialized volume"
        exit 0
    else
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled"
            exit 0
        fi
    fi
fi

# ============================================================================
# Run installers
# ============================================================================
log_section "Running Installers"

# Track timing
START_TIME=$(date +%s)

# Run each installer in sequence
for installer in "${SCRIPT_DIR}"/installers/[0-9]*.sh; do
    if [ -f "$installer" ]; then
        INSTALLER_NAME=$(basename "$installer")
        log_info "Running ${INSTALLER_NAME}..."
        
        # Execute installer
        if bash "$installer"; then
            log_success "${INSTALLER_NAME} completed"
        else
            log_error "${INSTALLER_NAME} failed - see logs above"
        fi
        
        echo ""  # Spacing between installers
    fi
done

# ============================================================================
# Post-installation tasks
# ============================================================================
log_section "Post-Installation Tasks"

# Fix permissions for everything
log_info "Setting ownership for dev user (uid ${DEV_USER_UID})..."
fix_permissions "${WORKSPACE_ROOT}"
log_success "Permissions set"

# Create test script
log_info "Creating test script..."
cat > "${DEPS_ROOT}/test-installation.sh" << 'EOF'
#!/bin/bash
# Test script to verify installation

source /workspace/deps/env.sh

echo "=== Compiler Tests ==="
which nvc++ && nvc++ --version | head -1 || echo "❌ nvc++ not found"
which nvcc && nvcc --version | tail -1 || echo "❌ nvcc not found"
which mpirun && mpirun --version | head -1 || echo "❌ MPI not found"

echo ""
echo "=== Library Tests ==="
[ -f "${DEPS_LIB}/libpalabos.a" ] && echo "✅ Palabos library found" || echo "❌ Palabos not found"
[ -f "${DEPS_LIB}/libgeometry-central.a" ] && echo "✅ geometry-central found" || echo "❌ geometry-central not found"
[ -f "${DEPS_BIN}/pvserver" ] && echo "✅ ParaView server found" || echo "❌ pvserver not found"

echo ""
echo "=== Header Tests ==="
[ -d "${DEPS_INCLUDE}/eigen3" ] && echo "✅ Eigen3 headers found" || echo "❌ Eigen3 not found"
[ -d "${DEPS_INCLUDE}/palabos" ] && echo "✅ Palabos headers found" || echo "❌ Palabos headers not found"
[ -d "${DEPS_INCLUDE}/polyscope" ] && echo "✅ Polyscope headers found" || echo "❌ Polyscope not found"

echo ""
echo "=== Build Test ==="
cat > /tmp/test.cpp << 'TEST_CODE'
#include <iostream>
#include <eigen3/Eigen/Core>
int main() {
    Eigen::Vector3d v(1,2,3);
    std::cout << "✅ Build test passed: " << v.norm() << std::endl;
    return 0;
}
TEST_CODE

if g++ -I"${DEPS_INCLUDE}" /tmp/test.cpp -o /tmp/test 2>/dev/null; then
    /tmp/test
else
    echo "❌ Build test failed"
fi

rm -f /tmp/test.cpp /tmp/test
EOF

chmod +x "${DEPS_ROOT}/test-installation.sh"

# ============================================================================
# Final summary
# ============================================================================
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

log_section "Installation Complete!"

log_success "All components installed successfully"
log_info "Time taken: ${ELAPSED_MIN} minutes ${ELAPSED_SEC} seconds"
echo ""
log_info "Installed components:"
log_info "  ✅ NVIDIA HPC SDK ${NVIDIA_HPC_VERSION}"
log_info "  ✅ Build headers (Eigen3, OpenGL, X11)"
log_info "  ✅ Palabos CFD library"
log_info "  ✅ geometry-central mesh library"
log_info "  ✅ ParaView ${PARAVIEW_VERSION} server"
log_info "  ✅ Polyscope visualization headers"
echo ""
log_info "Directory structure:"
log_info "  ${DEPS_BIN}/ - Executables"
log_info "  ${DEPS_LIB}/ - Libraries"
log_info "  ${DEPS_INCLUDE}/ - Headers"
log_info "  ${DEPS_ROOT}/env.sh - Environment setup"
echo ""
log_info "To use this environment:"
log_info "  source ${DEPS_ROOT}/env.sh"
echo ""
log_info "To test the installation:"
log_info "  ${DEPS_ROOT}/test-installation.sh"

# Mark as complete
echo "$(date)" > "${DEPS_ROOT}/.setup-complete"

log_success "Volume setup complete!"