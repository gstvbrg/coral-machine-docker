#!/bin/bash
# Script installer - copies custom scripts to persistent volume
# This runs during setup to ensure scripts are available in runtime

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Source configuration and utilities
source "${PARENT_DIR}/config.env"
source "${PARENT_DIR}/lib/common.sh"

log_section "Custom Scripts Installation"

# Create organized directory structure
log_info "Creating script directories..."
mkdir -p "${DEPS_ROOT}/scripts"
mkdir -p "${DEPS_ROOT}/runtime"

# Copy scripts to persistent location
log_info "Installing custom scripts..."
if [ -d "${PARENT_DIR}/scripts" ]; then
    # Copy all scripts except this installer
    cp -f "${PARENT_DIR}/scripts/"*.sh "${DEPS_ROOT}/scripts/" 2>/dev/null || true
    
    # Make all scripts executable
    chmod +x "${DEPS_ROOT}/scripts/"*.sh 2>/dev/null || true
    
    # Count installed scripts
    SCRIPT_COUNT=$(ls -1 "${DEPS_ROOT}/scripts/"*.sh 2>/dev/null | wc -l)
    log_success "Installed $SCRIPT_COUNT scripts to ${DEPS_ROOT}/scripts/"
else
    log_warning "No scripts directory found at ${PARENT_DIR}/scripts"
fi

# Add scripts to PATH in env.sh if not already there
if ! grep -q "${DEPS_ROOT}/scripts" "${DEPS_ROOT}/env.sh" 2>/dev/null; then
    log_info "Adding scripts directory to PATH..."
    cat >> "${DEPS_ROOT}/env.sh" << EOF

# Custom scripts
export PATH="\${PATH}:${DEPS_ROOT}/scripts"
EOF
    log_success "Scripts directory added to PATH"
fi

# Create convenience symlinks in bin directory (optional)
log_info "Creating convenience symlinks..."
if [ -f "${DEPS_ROOT}/scripts/paraview-manager.sh" ]; then
    ln -sf "${DEPS_ROOT}/scripts/paraview-manager.sh" "${DEPS_ROOT}/bin/pv" 2>/dev/null || true
    log_success "Created 'pv' symlink for ParaView manager"
fi

# Mark as installed
mark_installed "custom-scripts"

log_success "Custom scripts installation complete"
log_info "Scripts location: ${DEPS_ROOT}/scripts/"
log_info "Runtime logs/pids: ${DEPS_ROOT}/runtime/"
log_info ""
log_info "Available features:"
log_info "  - ParaView server management (pv command)"
log_info "  - Script template for creating new tools"
log_info "  - Organized runtime directory for logs/pids"