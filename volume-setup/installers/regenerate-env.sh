#!/bin/bash
# Regenerate env.sh without reinstalling packages
# This is useful when env.sh is deleted or needs updating

set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/../lib/common.sh"

# Load configuration
source "${SCRIPT_DIR}/../config.env"

log_section "Regenerating env.sh"

# Create fresh env.sh
cat > "${DEPS_ROOT}/env.sh" << EOF
#!/bin/bash
# Coral Machine environment configuration
# Generated: $(date)

# Base paths
export DEPS_ROOT="${DEPS_ROOT}"
export DEPS_BIN="\${DEPS_ROOT}/bin"
export DEPS_LIB="\${DEPS_ROOT}/lib"
export DEPS_INCLUDE="\${DEPS_ROOT}/include"

# Add all binary paths
export PATH="\${DEPS_BIN}:\$PATH"

# Library paths
export LD_LIBRARY_PATH="\${DEPS_LIB}:\$LD_LIBRARY_PATH"

# CMake prefix path
export CMAKE_PREFIX_PATH="\${DEPS_ROOT}"

# NVIDIA HPC SDK (if installed)
if [ -d "${DEPS_ROOT}/nvidia-hpc" ]; then
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
    
    # Compiler preferences
    export CC="\${NVHPC_ROOT}/compilers/bin/nvc"
    export CXX="\${NVHPC_ROOT}/compilers/bin/nvc++"
fi

# GPU Support
export NVIDIA_VISIBLE_DEVICES="all"
export NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics"

# Build system preferences
export CMAKE_GENERATOR="Ninja"

# ccache configuration
export CCACHE_DIR="/workspace/.ccache"
export CCACHE_MAXSIZE="${CCACHE_SIZE}"
# Note: Set CCACHE_DISABLE=1 when using nvc++ with CUDA

echo "Coral Machine environment loaded"
echo "==============================================="
echo "   Coral Machine CFD Development Environment"
echo "==============================================="
echo "Environment loaded. Key locations:"
echo "  /workspace/source - Source code"
echo "  /workspace/build  - Build directory"
echo "  /workspace/vtk    - VTK output files"
EOF

chmod +x "${DEPS_ROOT}/env.sh"
log_success "env.sh regenerated successfully"

# Verify key components
if [ -d "${DEPS_ROOT}/nvidia-hpc" ]; then
    log_success "NVIDIA HPC SDK found at ${DEPS_ROOT}/nvidia-hpc"
fi

if [ -f "${DEPS_ROOT}/lib/libpalabos.a" ]; then
    log_success "Palabos library found"
else
    log_warning "Palabos library not found - needs rebuild"
fi

log_success "Environment regeneration complete!"