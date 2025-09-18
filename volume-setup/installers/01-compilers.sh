#!/bin/bash
# NVIDIA HPC SDK installer
# Installs compilers (nvc++, nvfortran, nvcc) and MPI

set -e

# Get script directory and source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"
source "${SCRIPT_DIR}/../lib/common.sh"

log_section "NVIDIA HPC SDK ${NVIDIA_HPC_VERSION} Installation"

# Skip if disabled
if [ "${INSTALL_NVIDIA_HPC}" != "true" ]; then
    log_info "NVIDIA HPC SDK installation disabled in config"
    exit 0
fi

# Check if already installed
if is_installed "nvidia-hpc-${NVIDIA_HPC_VERSION}"; then
    log_info "NVIDIA HPC SDK ${NVIDIA_HPC_VERSION} already installed"
    exit 0
fi

# Install expect for automated installation
log_info "Installing automation tools..."
install_apt_packages expect

# Download NVIDIA HPC SDK
cd /tmp
NVHPC_ARCHIVE="nvhpc_${NVIDIA_HPC_VERSION}.tar.gz"
download_file "${NVIDIA_SDK_URL}" "${NVHPC_ARCHIVE}" "NVIDIA HPC SDK"

# Extract (with progress if pv is available)
log_info "Extracting NVIDIA HPC SDK (this takes a few minutes)..."
if command -v pv &> /dev/null; then
    SIZE_BYTES=$(stat -c%s "${NVHPC_ARCHIVE}" 2>/dev/null || echo "")
    if [ -n "$SIZE_BYTES" ]; then
        pv -s "$SIZE_BYTES" "${NVHPC_ARCHIVE}" | tar -xz -f -
    else
        pv "${NVHPC_ARCHIVE}" | tar -xz -f -
    fi
else
    tar -xzf "${NVHPC_ARCHIVE}"
fi
rm -f "${NVHPC_ARCHIVE}"

# Find extracted directory
NVHPC_DIR=$(ls -d nvhpc_* | head -n1)
cd "${NVHPC_DIR}"

# Ensure the target directory doesn't exist (installer may fail otherwise)
if [ -d "${DEPS_ROOT}/nvidia-hpc" ]; then
    log_info "Removing existing NVIDIA HPC installation..."
    rm -rf "${DEPS_ROOT}/nvidia-hpc"
fi

# Create expect script for automated installation
# Note: We DON'T quote EXPECT_SCRIPT so ${DEPS_ROOT} is expanded NOW
log_info "Preparing automated installation to ${DEPS_ROOT}/nvidia-hpc..."
cat > /tmp/install_nvhpc.exp << EXPECT_SCRIPT
#!/usr/bin/expect -f
set timeout -1
spawn ./install
expect "Press enter to continue..."
send "\r"
expect "Please choose install option:"
send "1\r"
expect "Installation directory?"
send "${DEPS_ROOT}/nvidia-hpc\r"
expect eof
EXPECT_SCRIPT

chmod +x /tmp/install_nvhpc.exp

# Run automated installation directly to target location
log_info "Installing NVIDIA HPC SDK directly to: ${DEPS_ROOT}/nvidia-hpc"
log_info "This avoids moving 13GB of files after installation"
/tmp/install_nvhpc.exp

# Verify installation succeeded
if [ -d "${DEPS_ROOT}/nvidia-hpc/Linux_x86_64" ]; then
    log_success "NVIDIA HPC SDK installed directly to ${DEPS_ROOT}/nvidia-hpc"
    # Clean up examples and docs to save space (several GB)
    log_info "Removing unnecessary examples and documentation to save space..."
    rm -rf "${DEPS_ROOT}/nvidia-hpc/Linux_x86_64/${NVIDIA_HPC_VERSION}/examples" 2>/dev/null || true
    rm -rf "${DEPS_ROOT}/nvidia-hpc/Linux_x86_64/${NVIDIA_HPC_VERSION}/doc" 2>/dev/null || true
    # Also remove CUDA samples if present
    rm -rf "${DEPS_ROOT}/nvidia-hpc/Linux_x86_64/${NVIDIA_HPC_VERSION}/cuda/samples" 2>/dev/null || true
else
    log_error "NVIDIA HPC SDK installation failed - not found at ${DEPS_ROOT}/nvidia-hpc"
fi

# Clean up
cd /tmp
rm -rf "${NVHPC_DIR}" /tmp/install_nvhpc.exp

# Update environment file
log_info "Updating environment configuration..."
cat >> "${DEPS_ROOT}/env.sh" << EOF

# NVIDIA HPC SDK
export NVHPC_ROOT="${DEPS_ROOT}/nvidia-hpc/Linux_x86_64/${NVIDIA_HPC_VERSION}"
export PATH="\${NVHPC_ROOT}/compilers/bin:\$PATH"
export LD_LIBRARY_PATH="\${NVHPC_ROOT}/compilers/lib:\$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="\${NVHPC_ROOT}/math_libs/lib64:\$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="\${NVHPC_ROOT}/cuda/lib64:\$LD_LIBRARY_PATH"

# CUDA
export CUDA_HOME="\${NVHPC_ROOT}/cuda"
export PATH="\${CUDA_HOME}/bin:\$PATH"

# Use NVIDIA's OpenMPI (not system MPI)
export MPI_ROOT="\${NVHPC_ROOT}/comm_libs/12.5/openmpi4/openmpi-4.1.5"
export PATH="\${MPI_ROOT}/bin:\$PATH"
export LD_LIBRARY_PATH="\${MPI_ROOT}/lib:\$LD_LIBRARY_PATH"

# MPI Configuration
export OMPI_MCA_orte_tmpdir_base="/tmp"

# GPU Support
export NVIDIA_VISIBLE_DEVICES="all"
export NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics"

# Build system preferences
export CMAKE_GENERATOR="Ninja"
export CCACHE_DISABLE=1  # Disable ccache for nvc++ (causes issues with CUDA)

# Compiler preferences
export CC="\${NVHPC_ROOT}/compilers/bin/nvc"
export CXX="\${NVHPC_ROOT}/compilers/bin/nvc++"
EOF

# Verify installation
log_info "Verifying installation..."
NVHPC_BIN="${DEPS_ROOT}/nvidia-hpc/Linux_x86_64/${NVIDIA_HPC_VERSION}/compilers/bin"

if [ -f "${NVHPC_BIN}/nvc++" ]; then
    log_success "nvc++ found at ${NVHPC_BIN}/nvc++"
else
    log_error "nvc++ not found - installation may have failed"
fi

if [ -f "${NVHPC_BIN}/nvcc" ]; then
    log_success "nvcc found at ${NVHPC_BIN}/nvcc"
else
    log_warning "nvcc not found - CUDA compilation may not work"
fi

# Mark as installed
mark_installed "nvidia-hpc-${NVIDIA_HPC_VERSION}"

log_success "NVIDIA HPC SDK ${NVIDIA_HPC_VERSION} installation complete"
log_info "Compilers available: nvc++, nvfortran, nvcc"
log_info "MPI: OpenMPI with HPC-X"
log_info "CUDA: Version ${CUDA_VERSION}"