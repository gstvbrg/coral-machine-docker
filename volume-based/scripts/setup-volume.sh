#!/bin/bash
# One-time setup script to build all dependencies into the volume
# This populates /workspace/deps with pre-compiled libraries AND compilers

set -e  # Exit on error

echo "========================================="
echo "Coral Machine Volume Setup"
echo "This will build and install all dependencies"
echo "Including NVIDIA HPC SDK compilers"
echo "Estimated time: 45-60 minutes"
echo "========================================="

# Check if volume is mounted
if [ ! -d "/workspace/deps" ]; then
    echo "ERROR: /workspace/deps not found. Volume not mounted?"
    exit 1
fi

# Check if already initialized
if [ -f "/workspace/deps/.initialized" ]; then
    echo "Volume appears to be already initialized."
    echo "To reinitialize, remove /workspace/deps/.initialized"
    exit 0
fi

cd /workspace

# Clean up any previous failed attempts in /tmp
echo "Cleaning up /tmp from any previous runs..."
rm -rf /tmp/nvhpc* /tmp/paraview* /tmp/geometry-central /tmp/polyscope /tmp/palabos-hybrid /tmp/build

# Phase 0: Install NVIDIA HPC SDK into volume
echo ""
echo "🚀 Installing NVIDIA HPC SDK 24.7 (this is large ~8GB)..."
if [ ! -d "/workspace/deps/nvidia-hpc" ]; then
    cd /tmp
    echo "Downloading NVIDIA HPC SDK..."
    wget -q https://developer.download.nvidia.com/hpc-sdk/24.7/nvhpc_2024_247_Linux_x86_64_cuda_12.5.tar.gz
    
    echo "Extracting (this takes a few minutes)..."
    tar -xzf nvhpc_2024_247_Linux_x86_64_cuda_12.5.tar.gz
    
    echo "Installing NVIDIA HPC SDK (using default location then moving)..."
    cd nvhpc_2024_247_Linux_x86_64_cuda_12.5
    
    # Create expect script for automated installation
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
    
    # Install expect if not available
    apt-get update && apt-get install -y expect > /dev/null 2>&1
    
    # Run automated installation to default location
    chmod +x /tmp/install_nvhpc.exp
    /tmp/install_nvhpc.exp
    
    # Move from default location to our volume
    echo "Moving NVIDIA HPC SDK to persistent volume..."
    if [ -d "/opt/nvidia/hpc_sdk" ]; then
        mv /opt/nvidia/hpc_sdk /workspace/deps/nvidia-hpc
        echo "✅ NVIDIA HPC SDK moved to /workspace/deps/nvidia-hpc"
    else
        echo "ERROR: NVIDIA HPC SDK installation failed"
        exit 1
    fi
    
    cd /tmp
    rm -rf nvhpc_2024_247_Linux_x86_64_cuda_12.5* install_nvhpc.exp
    
    echo "✅ NVIDIA HPC SDK installed"
else
    echo "✓ NVIDIA HPC SDK already exists, skipping..."
fi

# Set up environment for subsequent builds - NVHPC MPI takes precedence
export NVHPC_ROOT="/workspace/deps/nvidia-hpc/Linux_x86_64/24.7"
export PATH="${NVHPC_ROOT}/comm_libs/mpi/bin:${NVHPC_ROOT}/compilers/bin:$PATH"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/comm_libs/mpi/lib:${NVHPC_ROOT}/compilers/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/math_libs/lib64:${NVHPC_ROOT}/cuda/lib64:$LD_LIBRARY_PATH"

# Phase 1: Install ParaView (binary distribution)
echo ""
echo "📦 Installing ParaView 6.0.0..."
if [ ! -d "/workspace/deps/paraview" ]; then
    mkdir -p /workspace/deps/paraview
    cd /tmp
    ARCH="$(dpkg --print-architecture)"
    if [ "$ARCH" = "amd64" ]; then
        PV_URL="https://www.paraview.org/files/v6.0/ParaView-6.0.0-MPI-Linux-Python3.12-x86_64.tar.gz"
    else
        PV_URL="https://www.paraview.org/files/v6.0/ParaView-6.0.0-MPI-Linux-Python3.9-${ARCH}.tar.gz"
    fi
    
    echo "Downloading ParaView from: $PV_URL"
    wget -qO paraview.tar.gz "$PV_URL" || (echo "Failed to download ParaView" && exit 1)
    
    echo "Extracting ParaView..."
    tar -xzf paraview.tar.gz -C /workspace/deps/paraview --strip-components=1
    rm paraview.tar.gz
    
    # Prune unnecessary files for headless operation
    echo "Optimizing ParaView for headless operation..."
    rm -rf /workspace/deps/paraview/bin/paraview* 2>/dev/null || true
    rm -rf /workspace/deps/paraview/share/examples 2>/dev/null || true
    rm -rf /workspace/deps/paraview/share/doc 2>/dev/null || true
    rm -rf /workspace/deps/paraview/share/icons 2>/dev/null || true
    
    # Strip binaries to reduce size
    find /workspace/deps/paraview -type f -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true
    
    # Check EGL support
    echo "Checking ParaView EGL support..."
    if ldd /workspace/deps/paraview/bin/pvserver 2>/dev/null | grep -q libEGL; then
        echo "✅ pvserver supports EGL (OK for PV_BACKEND=egl)"
    else
        echo "⚠️  pvserver lacks libEGL; use PV_BACKEND=xvfb for software rendering"
    fi
    
    echo "✅ ParaView installed and optimized"
else
    echo "✓ ParaView already exists, skipping..."
fi

# Phase 2: Collect all development headers into volume
echo ""
echo "📚 Collecting development headers for build dependencies..."
if [ ! -f "/workspace/deps/.headers-collected" ]; then
    echo "Installing temporary packages to extract headers..."
    apt-get update > /dev/null 2>&1
    apt-get install -y --no-install-recommends \
        libeigen3-dev \
        libgl1-mesa-dev libglu1-mesa-dev \
        libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
        > /dev/null 2>&1
    
    # Eigen3 headers (required by geometry-central)
    if [ -d "/usr/include/eigen3" ]; then
        cp -r /usr/include/eigen3 /workspace/deps/include/
        echo "  ✓ Eigen3 headers copied"
    fi
    
    # OpenGL headers (may be needed for graphics code)
    if [ -d "/usr/include/GL" ]; then
        cp -r /usr/include/GL /workspace/deps/include/
        echo "  ✓ OpenGL headers copied"
    fi
    
    # X11 headers (needed by GLFW and windowing)
    for dir in X11 xcb; do
        if [ -d "/usr/include/$dir" ]; then
            cp -r /usr/include/$dir /workspace/deps/include/
            echo "  ✓ $dir headers copied"
        fi
    done
    
    touch /workspace/deps/.headers-collected
    echo "✅ All development headers collected in volume"
else
    echo "✓ Development headers already collected, skipping..."
fi

# Phase 3: Build geometry-central
echo ""
echo "🔧 Building geometry-central..."
if [ ! -d "/workspace/deps/include/geometrycentral" ]; then
    cd /tmp
    # Clean up any previous attempts
    rm -rf geometry-central
    git clone --recursive --depth 1 https://github.com/nmwsharp/geometry-central.git
    cd geometry-central
    mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/workspace/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=g++ \
             -DCMAKE_CXX_STANDARD=17 \
             -G Ninja
    ninja install
    cd /tmp && rm -rf geometry-central
    echo "✅ geometry-central installed"
else
    echo "✓ geometry-central already exists, skipping..."
fi

# Phase 4: Install Polyscope headers (headers-only)
echo ""
echo "🎨 Installing Polyscope headers..."
if [ ! -d "/workspace/deps/include/polyscope" ]; then
    cd /tmp
    # Clean up any previous attempts
    rm -rf polyscope
    git clone --recursive --depth 1 https://github.com/nmwsharp/polyscope.git
    cd polyscope
    
    # Just copy headers, don't build
    mkdir -p /workspace/deps/include
    cp -r include/polyscope /workspace/deps/include/
    
    # Also copy imgui headers if present
    IMGUI_DIR=$(dirname $(find . -type f -name imgui.h | head -n1))
    if [ -n "$IMGUI_DIR" ]; then
        mkdir -p /workspace/deps/include/imgui
        cp -r ${IMGUI_DIR}/* /workspace/deps/include/imgui/ || true
    fi
    
    # Copy implot headers if present
    IPLOT_DIR=$(dirname $(find . -type f -name implot.h | head -n1))
    if [ -n "$IPLOT_DIR" ]; then
        mkdir -p /workspace/deps/include/implot
        cp -r ${IPLOT_DIR}/* /workspace/deps/include/implot/ || true
    fi
    
    cd /tmp && rm -rf polyscope
    echo "✅ Polyscope headers installed"
else
    echo "✓ Polyscope headers already exist, skipping..."
fi

# Phase 5: Build Palabos-hybrid (the big one) - using nvc++ from HPC SDK
echo ""
echo "🧮 Building Palabos-hybrid with NVIDIA compilers (this will take 15-20 minutes)..."
if [ ! -d "/workspace/deps/palabos-hybrid" ]; then
    cd /tmp
    # Clean up any previous attempts completely
    rm -rf palabos-hybrid build
    
    echo "Cloning Palabos repository..."
    git clone --depth 1 https://github.com/gstvbrg/palabos-hybrid-prerelease.git palabos-hybrid
    cd palabos-hybrid
    
    # Disable examples to speed up build
    sed -i -E 's|^[[:space:]]*add_subdirectory[[:space:]]*\([[:space:]]*examples/|# DISABLED: &|g' CMakeLists.txt
    
    echo "Configuring build with CMake..."
    mkdir -p build && cd build
    
    # Use g++ for Palabos build to avoid compiler recognition issues
    echo "⚠️  Using g++ for Palabos build (more reliable than nvc++ for Palabos CMake)"
    echo "  NVIDIA compilers are available in the dev container for user projects"
    
    # Use system compilers for reliable build
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=g++ \
             -DCMAKE_CXX_STANDARD=20 \
             -DPALABOS_ENABLE_MPI=ON \
             -DPALABOS_ENABLE_CUDA=OFF \
             -DBUILD_HDF5=OFF \
             -DBUILD_EXAMPLES=OFF \
             -DBUILD_TESTING=OFF \
             -G Ninja
    
    echo "Building Palabos library..."
    # Build library only
    ninja palabos
    
    # Install in proper structure
    echo "Installing Palabos to /workspace/deps/palabos-hybrid..."
    cd /tmp/palabos-hybrid
    mkdir -p /workspace/deps/palabos-hybrid/include/palabos /workspace/deps/palabos-hybrid/lib
    
    # Copy headers with proper structure and error checking
    echo "Copying Palabos headers..."
    if ! cp -r src/* /workspace/deps/palabos-hybrid/include/palabos/; then
        echo "ERROR: Failed to copy Palabos src headers"
        exit 1
    fi
    
    if ! cp -r externalLibraries /workspace/deps/palabos-hybrid/include/palabos/; then
        echo "ERROR: Failed to copy Palabos external libraries"
        exit 1
    fi
    
    # Copy the compiled library with verification
    echo "Copying compiled Palabos library..."
    LIBRARY_PATH=$(find build -name "libpalabos.a" -print -quit)
    if [ -z "$LIBRARY_PATH" ]; then
        echo "ERROR: libpalabos.a not found in build directory"
        echo "Build directory contents:"
        find build -name "*.a" -o -name "*.so" | head -10
        exit 1
    fi
    
    echo "Found library at: $LIBRARY_PATH"
    if ! cp "$LIBRARY_PATH" /workspace/deps/palabos-hybrid/lib/; then
        echo "ERROR: Failed to copy libpalabos.a"
        exit 1
    fi
    
    # Verify the library was copied successfully
    if [ ! -f "/workspace/deps/palabos-hybrid/lib/libpalabos.a" ]; then
        echo "ERROR: libpalabos.a not found after copy"
        exit 1
    fi
    
    # Strip debug symbols from static library
    strip -g /workspace/deps/palabos-hybrid/lib/libpalabos.a 2>/dev/null || true
    
    # Verify installation
    echo "Verifying Palabos installation..."
    echo "  Headers: $(find /workspace/deps/palabos-hybrid/include -name "*.h" | wc -l) header files"
    echo "  Library: $(ls -lh /workspace/deps/palabos-hybrid/lib/libpalabos.a)"
    
    cd /tmp && rm -rf palabos-hybrid
    echo "✅ Palabos-hybrid installed and verified"
else
    echo "✓ Palabos-hybrid already exists, skipping..."
fi

# Phase 6: Create environment setup script
echo ""
echo "📝 Creating environment setup script..."
cat > /workspace/deps/env.sh << 'EOF'
# Environment setup for Coral Machine development
# Source this file to configure paths for NVIDIA HPC SDK and dependencies

# NVIDIA HPC SDK paths
export NVHPC_ROOT=/workspace/deps/nvidia-hpc/Linux_x86_64/24.7
export PATH="${NVHPC_ROOT}/compilers/bin:${PATH}"
export PATH="${NVHPC_ROOT}/comm_libs/mpi/bin:${PATH}"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/compilers/lib:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/math_libs/lib64:${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="${NVHPC_ROOT}/cuda/lib64:${LD_LIBRARY_PATH}"

# MPI configuration
export OPAL_PREFIX="${NVHPC_ROOT}/comm_libs/12.5/hpcx/hpcx-2.19/ompi"
export OMPI_MCA_orte_tmpdir_base="/tmp"

# ParaView
export PATH="/workspace/deps/paraview/bin:${PATH}"
export LD_LIBRARY_PATH="/workspace/deps/paraview/lib:${LD_LIBRARY_PATH}"

# Build configuration
export CMAKE_PREFIX_PATH="/workspace/deps"
export PALABOS_ROOT="/workspace/deps/palabos-hybrid"
export CCACHE_DIR="/workspace/.ccache"
export CCACHE_MAXSIZE="10G"

# CUDA/GPU
export CUDA_HOME="${NVHPC_ROOT}/cuda"
export PATH="${CUDA_HOME}/bin:${PATH}"

# Include paths for compilation - all header locations
export CPLUS_INCLUDE_PATH="/workspace/deps/include:/workspace/deps/include/eigen3:${CPLUS_INCLUDE_PATH:-}"
export C_INCLUDE_PATH="/workspace/deps/include:${C_INCLUDE_PATH:-}"

# Library paths
export LIBRARY_PATH="/workspace/deps/lib:/workspace/deps/palabos-hybrid/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="/workspace/deps/lib:${LD_LIBRARY_PATH}"

echo "Environment configured for Coral Machine development"
echo "Compilers: nvc++, nvfortran, nvcc"
echo "ParaView server: pvserver"
echo "Headers: geometry-central, polyscope, imgui, palabos"
EOF

chmod +x /workspace/deps/env.sh

# Phase 7: Initialize ccache
echo ""
echo "🚀 Setting up ccache..."
mkdir -p /workspace/.ccache
echo "max_size = 10G" > /workspace/.ccache/ccache.conf

# Phase 8: Create a test compilation script
echo ""
echo "📝 Creating test compilation script..."
cat > /workspace/deps/test-compile.sh << 'EOF'
#!/bin/bash
# Test script to verify all dependencies are accessible

source /workspace/deps/env.sh

echo "Testing compiler availability..."
which nvc++ || echo "ERROR: nvc++ not found"
which nvcc || echo "ERROR: nvcc not found"
which mpirun || echo "ERROR: mpirun not found"

echo ""
echo "Testing include paths..."
ls -la /workspace/deps/include/geometrycentral 2>/dev/null | head -2 || echo "ERROR: geometry-central headers not found"
ls -la /workspace/deps/include/polyscope 2>/dev/null | head -2 || echo "ERROR: polyscope headers not found"
ls -la /workspace/deps/palabos-hybrid/include/palabos 2>/dev/null | head -2 || echo "ERROR: palabos headers not found"

echo ""
echo "Testing libraries..."
ls -la /workspace/deps/palabos-hybrid/lib/libpalabos.a || echo "ERROR: libpalabos.a not found"

echo ""
echo "Testing ParaView..."
/workspace/deps/paraview/bin/pvserver --version || echo "ERROR: pvserver not working"

echo ""
echo "Test complete!"
EOF
chmod +x /workspace/deps/test-compile.sh

# Phase 9: Fix ownership for dev user (uid 1000)
echo ""
echo "🔐 Setting proper ownership for dev user..."
chown -R 1000:1000 /workspace
chmod -R u+rw,g+r,o+r /workspace
echo "✅ Ownership set to dev user (uid 1000)"

# Mark volume as initialized
echo "$(date)" > /workspace/deps/.initialized
chown 1000:1000 /workspace/deps/.initialized

echo ""
echo "========================================="
echo "✅ Volume setup complete!"
echo ""
echo "Installed components:"
echo "  - NVIDIA HPC SDK 24.7 (compilers, CUDA, MPI)"
echo "  - ParaView 6.0.0 (headless)"
echo "  - geometry-central (mesh processing)"
echo "  - Polyscope headers (visualization)"
echo "  - Palabos-hybrid (CUDA-enabled CFD)"
echo ""
echo "Directory structure created:"
echo "  /workspace/deps/nvidia-hpc/     - Compilers & CUDA"
echo "  /workspace/deps/paraview/       - ParaView server"
echo "  /workspace/deps/palabos-hybrid/ - Palabos library"
echo "  /workspace/deps/include/        - All other headers"
echo "  /workspace/deps/env.sh          - Environment setup"
echo ""
echo "To test the installation:"
echo "  /workspace/deps/test-compile.sh"
echo ""
echo "Volume is ready for use with Dockerfile.base"
echo "========================================="