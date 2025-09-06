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

# Extract
log_info "Extracting NVIDIA HPC SDK (this takes a few minutes)..."
tar -xzf "${NVHPC_ARCHIVE}"
rm -f "${NVHPC_ARCHIVE}"

# Find extracted directory
NVHPC_DIR=$(ls -d nvhpc_* | head -n1)
cd "${NVHPC_DIR}"

# Create expect script for automated installation
log_info "Preparing automated installation..."
cat > /tmp/install_nvhpc.exp << 'EXPECT_SCRIPT'
#!/usr/bin/expect -f
set timeout -1
spawn ./install
expect "Press enter to continue..."
send "\r"
expect "Please choose install option:"
send "1\r"
expect "Installation directory?"
send "\r"
expect eof
EXPECT_SCRIPT

chmod +x /tmp/install_nvhpc.exp

# Run automated installation to default location
log_info "Installing NVIDIA HPC SDK (this will take 10-15 minutes)..."
/tmp/install_nvhpc.exp

# Move from default location to our volume
log_info "Moving NVIDIA HPC SDK to persistent volume..."
if [ -d "/opt/nvidia/hpc_sdk" ]; then
    # Remove any existing installation
    rm -rf "${DEPS_ROOT}/nvidia-hpc"
    mv /opt/nvidia/hpc_sdk "${DEPS_ROOT}/nvidia-hpc"
    log_success "NVIDIA HPC SDK moved to ${DEPS_ROOT}/nvidia-hpc"
else
    log_error "NVIDIA HPC SDK installation failed - not found at /opt/nvidia/hpc_sdk"
fi

# Clean up
cd /tmp
rm -rf "${NVHPC_DIR}" /tmp/install_nvhpc.exp

# Update environment file
log_info "Updating environment configuration..."
cat >> "${DEPS_ROOT}/env.sh" << 'EOF'

# NVIDIA HPC SDK
export NVHPC_ROOT="${DEPS_ROOT}/nvidia-hpc/Linux_x86_64/24.7"
export PATH="${NVHPC_ROOT}/compilers/bin:$PATH"
export PATH="${NVHPC_ROOT}/comm_libs/mpi/bin:$PATH"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/compilers/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/math_libs/lib64:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/cuda/lib64:$LD_LIBRARY_PATH"

# CUDA
export CUDA_HOME="${NVHPC_ROOT}/cuda"
export PATH="${CUDA_HOME}/bin:$PATH"

# MPI Configuration
export OPAL_PREFIX="${NVHPC_ROOT}/comm_libs/12.5/hpcx/hpcx-2.19/ompi"
export OMPI_MCA_orte_tmpdir_base="/tmp"

# GPU Support
export NVIDIA_VISIBLE_DEVICES="all"
export NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics"
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