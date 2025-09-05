#!/bin/bash
# One-time setup script to build all dependencies into the volume
# This populates /workspace/deps with pre-compiled libraries

set -e  # Exit on error

echo "========================================="
echo "Coral Machine Volume Setup"
echo "This will build and install all dependencies"
echo "Estimated time: 30-45 minutes"
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
    
    echo "✅ ParaView installed and optimized"
else
    echo "✓ ParaView already exists, skipping..."
fi

# Phase 2: Build geometry-central
echo ""
echo "🔧 Building geometry-central..."
if [ ! -d "/workspace/deps/include/geometrycentral" ]; then
    cd /tmp
    git clone --recursive --depth 1 https://github.com/nmwsharp/geometry-central.git
    cd geometry-central
    mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/workspace/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=g++ \
             -DCMAKE_CXX_STANDARD=17
    make -j$(nproc) install
    cd /tmp && rm -rf geometry-central
    echo "✅ geometry-central installed"
else
    echo "✓ geometry-central already exists, skipping..."
fi

# Phase 3: Install Polyscope headers (headers-only)
echo ""
echo "🎨 Installing Polyscope headers..."
if [ ! -d "/workspace/deps/include/polyscope" ]; then
    cd /tmp
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

# Phase 4: Build Palabos-hybrid (the big one)
echo ""
echo "🧮 Building Palabos-hybrid (this will take 10-15 minutes)..."
if [ ! -d "/workspace/deps/palabos-hybrid" ]; then
    cd /tmp
    git clone --depth 1 https://github.com/gstvbrg/palabos-hybrid-prerelease.git palabos-hybrid
    cd palabos-hybrid
    
    # Disable examples to speed up build
    sed -i -E 's|^[[:space:]]*add_subdirectory[[:space:]]*\([[:space:]]*examples/|# DISABLED: &|g' CMakeLists.txt
    
    mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=g++ \
             -DCMAKE_CXX_STANDARD=20 \
             -DCMAKE_CUDA_COMPILER=nvcc \
             -DPALABOS_ENABLE_MPI=ON \
             -DPALABOS_ENABLE_CUDA=ON \
             -DBUILD_HDF5=OFF \
             -DBUILD_EXAMPLES=OFF \
             -DBUILD_TESTING=OFF \
             -DCUDA_ARCH="sm_75;sm_80;sm_86;sm_89"
    
    # Build library only
    make -j$(nproc) palabos
    
    # Install in expected structure
    cd ..
    mkdir -p /workspace/deps/palabos-hybrid/include /workspace/deps/palabos-hybrid/lib
    cp -r src /workspace/deps/palabos-hybrid/include/
    cp -r externalLibraries /workspace/deps/palabos-hybrid/include/
    find build -name "libpalabos.a" -exec cp {} /workspace/deps/palabos-hybrid/lib/ \;
    
    # Strip debug symbols from static library
    strip -g /workspace/deps/palabos-hybrid/lib/libpalabos.a 2>/dev/null || true
    
    cd /tmp && rm -rf palabos-hybrid
    echo "✅ Palabos-hybrid installed"
else
    echo "✓ Palabos-hybrid already exists, skipping..."
fi

# Phase 5: Initialize ccache
echo ""
echo "🚀 Setting up ccache..."
mkdir -p /workspace/.ccache
echo "max_size = 10G" > /workspace/.ccache/ccache.conf

# Mark volume as initialized
echo "$(date)" > /workspace/deps/.initialized
echo ""
echo "========================================="
echo "✅ Volume setup complete!"
echo ""
echo "Installed components:"
echo "  - ParaView 6.0.0 (headless)"
echo "  - geometry-central"
echo "  - Polyscope (headers)"
echo "  - Palabos-hybrid"
echo ""
echo "Volume is ready for use with Dockerfile.base"
echo "========================================="