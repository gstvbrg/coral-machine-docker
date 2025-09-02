# PORAG Remote GPU Development Environment Requirements

**Last Updated**: August 27 2025   
**Purpose**: Specification for PORAG coral simulation remote GPU workstation

## Executive Summary

Deploy a **pre-built GPU development image** to RunPod that functions as a remote GPU workstation, enabling **instant development productivity** with all heavy dependencies pre-compiled, requiring only source code synchronization and incremental builds.

### Architecture (with idealized execution time targets)

1. **One-Time Setup**: Build a complete Docker image with Palabos-hybrid, geometry-central, Polyscope, ParaView server, and all tools pre-compiled. Push to Docker Hub.

2. **Daily Development**:
   - Deploy pre-built image to RunPod (30 seconds)
   - Container auto-pulls your latest code from GitHub (10 seconds)
   - CMake finds pre-built dependencies (20 seconds)
   - Build only your CoralMachine source (30 seconds with warm ccache)
   - **Total: <90 seconds to full productivity**

3. **Work Session**:
   - SSH from Cursor IDE for remote development
   - Edit code with full IntelliSense
   - Incremental builds in <30 seconds
   - GPU-accelerated simulations
   - Remote ParaView visualization
   - Commit to GitHub when done

4. **Cost Savings**: Stop pod when done, preserving all state on persistent volume

**This is NOT about building Docker images daily. It's about using RunPod as a remote GPU workstation with everything pre-installed.**

### Core Business Drivers
- **Cost Optimization**: Utilize on-demand, high-end GPUs (RTX 4090, A100) only during active development
- **Development Velocity**: Sub-30-second incremental builds via pre-compiled dependencies
- **Zero Setup Time**: Deploy pre-built image and immediately start coding
- **Professional Workflow**: SSH remote development via Cursor IDE with full GPU capabilities
- **Intensive Visualization**: Remote ParaView server for immediate VTK analysis

## Primary Objective

Deploy a **single pre-built Docker image** containing all compiled dependencies to RunPod, functioning as a remote GPU workstation that requires only **git pull and incremental build** to achieve full development productivity in under 90 seconds.

## Core Development Workflow

### Target User Experience
1. **Deploy**: Launch RunPod with pre-built image (< 90 seconds to coding)
2. **Auto-sync**: Container automatically pulls latest code from GitHub (< 10 seconds)
3. **Connect**: SSH from Cursor IDE with port forwarding ready (< 20 seconds)
4. **Develop**: Full remote development with GPU-aware IntelliSense
5. **Build**: Incremental builds with ccache (< 30 seconds for typical changes)
6. **Simulate**: GPU-accelerated execution with profiling
7. **Visualize**: Remote ParaView server (data stays remote)
8. **Commit**: Push changes to GitHub from container
9. **Stop**: Shutdown pod to save costs (state persists)

### Development Flow
```
Deploy Image → [Auto: git pull + cmake] → SSH Connect → Edit → 
Incremental Build (30s) → GPU Simulate → ParaView Visualize → 
Git Commit → Stop Pod
```

** Performance Targets (Achieved via Pre-built Dependencies):**
- **Pod deployment to coding**: < 90 seconds (image start + git pull + cmake)
- **SSH connection**: < 20 seconds from Cursor IDE  
- **Incremental build**: < 30 seconds (only CoralMachine source, deps pre-built)
- **First build after deploy**: < 2 minutes (with cold ccache)
- **Subsequent builds**: < 30 seconds (warm ccache)
- **Full rebuild**: < 5 minutes (all deps pre-compiled in image)
- **Simulation startup**: < 10 seconds
- **VTK visualization**: < 5 seconds via ParaView server

## Infrastructure Architecture

### Single Pre-Built Image Strategy

The system deploys a **complete pre-built development image** to RunPod, functioning as a remote GPU workstation with all heavy dependencies already compiled.

#### Architecture Philosophy
- **Everything pre-compiled**: Palabos-hybrid, geometry-central, Polyscope, ParaView server all built into image
- **Source code only**: Container startup only pulls and builds CoralMachine source
- **Instant productivity**: < 90 seconds from deploy to coding (just git pull + cmake)
- **Persistent state**: ccache, VTK files, and development configurations preserved
- **Remote workstation**: Treat as powerful remote machine, not container platform

### Data Management

#### 1. Local Machine (M1 MacBook Pro)
**Role**: Development interface and remote control center

**Primary Components:**
- **Cursor IDE**: 
  - Code editing with remote SSH development
  - IntelliSense
  - Integrated debugging 
  - Access to LLM Models through Cursor Pro + Claude Code Max
- **ParaView Client**: 
  - Connects to remote ParaView server on GPU container
  - Renders VTK visualization locally while data stays remote
  - Handles 50-200MB VTK files without local storage
- **SSH Configuration**: 
  - Automated port forwarding for ParaView (11111)
  - Persistent connection management
  - Key-based authentication

**Storage Responsibilities:**
- **Documentation**: Local markdown files, notes, requirements
- **Git Repository**: Local clone for offline work, branching, merging
- **ParaView Client Settings**: Visualization preferences and layouts
- **SSH Configurations**: Connection profiles and forwarding rules

**Explicitly NOT Stored Locally:**
- Large VTK files (stay on GPU container)
- GPU builds (occur on container)
- Simulation data (generated on container)
- Development dependencies (containerized)

#### 2. GPU Container (RunPod/Cloud)
**Role**: Pre-built remote GPU workstation for PORAG development

**Pre-Built Image Contents (coral-gpu-dev:latest):**
- **Base**: NVIDIA HPC SDK 24.7 with CUDA 12.5
- **Pre-Compiled Libraries**:
  - Palabos-hybrid prerelease (fully built, headers + libs)
  - geometry-central (optimized static library)
  - Polyscope (visualization library built)
  - ParaView server (complete installation)
  - Eigen3, X11, and all other dependencies
- **Development Tools**:
  - nvc++ compiler (GPU-aware)
  - ninja build system
  - ccache (10GB configured)
  - cmake (latest version)
  - Git, zsh, tmux pre-configured
  - CUDA toolkit, Nsight tools
- **Image Size**: ~15GB (but downloaded once, cached by RunPod)
- **Build Frequency**: Monthly or when major dependencies update

**Runtime Requirements:**
- **GPU**: RTX 4090, A6000, or A100 with 16GB+ VRAM
- **CPU**: 8+ cores for parallel builds
- **Memory**: 32GB+ RAM for simulations
- **Network**: SSH (22), ParaView Server (11111)

**What Happens on Container Start:**
1. **Automatic Git Sync** (10 seconds):
   ```bash
   git clone/pull https://github.com/user/coralMachine.git /workspace/source
   ```
2. **CMake Configuration** (20 seconds - finds pre-built deps):
   ```bash
   cmake -G Ninja -B /workspace/build \
     -DCMAKE_PREFIX_PATH=/opt/deps \
     -DCMAKE_BUILD_TYPE=RelWithDebInfo
   ```
3. **Initial Build** (60 seconds - only CoralMachine source):
   ```bash
   ninja -C /workspace/build
   ```
4. **Services Start** (parallel with build):
   - ParaView server launches on port 11111
   - GPU monitoring in tmux session
   - SSH server ready for connections

**Persistent Storage Strategy:**
- **Primary Volume**: `/workspace` (100GB+ SSD)
  - Source code synchronized with GitHub
  - Build directories with incremental state
  - ccache compiler cache (critical for build speed)
  - Development configuration (zsh, tmux, editor settings)
- **Data Volume**: `/data` (200GB+ SSD for intensive VTK workflow)  
  - VTK animation sequences (50-200MB per frame)
  - Simulation checkpoints and profiling data
  - Historical results for comparison analysis
- **Cache Volume**: `/cache` (50GB+ SSD)
  - Temporary build artifacts
  - GPU profiling traces
  - Intermediate processing files

**Container Lifecycle Management:**
- **Startup Script**: Automated initialization restoring full development state
- **Background Services**: ParaView server, GPU monitoring, tmux sessions
- **State Preservation**: All development work persists across container restarts
- **Rapid Deployment**: < 5 minutes from pod launch to full productivity

#### 3. GitHub Repository
**Role**: Source code only (all dependencies pre-built in image)

**Repository Structure (Simplified):**
```
coralMachine/
├── src/                    # CoralMachine source only
│   ├── FluidSolver/
│   ├── NutrientSolver/
│   ├── CoralMesh/
│   └── SimulationController/
├── CMakeLists.txt         # Finds pre-built deps in /opt/deps
├── README.md
└── .gitignore             # Excludes builds, VTK files
```

**What's NOT in the repository:**
- **Dependencies**: Palabos, geometry-central, etc. (pre-built in image)
- **Docker files**: Image built once, used forever
- **Build artifacts**: Generated locally in container
- **VTK files**: Stay on persistent volume

### Container Directory Structure

**Critical Understanding**: The container has two distinct storage areas:
- `/opt/` - Pre-built dependencies (in image, never changes)
- `/workspace/` - Your development work (persistent volume, survives restarts)

```
/
├── opt/                          # PRE-BUILT IN IMAGE (read-only)
│   ├── deps/                     # All compiled libraries
│   │   ├── include/              # Headers for dependencies
│   │   │   ├── palabos/          # Palabos-hybrid headers
│   │   │   ├── geometrycentral/  # geometry-central headers
│   │   │   └── polyscope/        # Polyscope headers
│   │   └── lib/                  # Compiled static libraries
│   │       ├── libpalabos.a      
│   │       ├── libgeometry-central.a
│   │       └── libpolyscope.a
│   │
│   ├── ParaView-5.11/            # ParaView server installation
│   │   └── bin/pvserver          # Headless ParaView server
│   │
│   └── nvidia/hpc_sdk/           # NVIDIA GPU compiler toolchain
│       └── .../bin/nvc++         # GPU-aware C++ compiler
│
├── workspace/                    # PERSISTENT VOLUME (your work)
│   ├── source/                   # Your git repository
│   │   ├── CMakeLists.txt        # Finds deps in /opt/deps
│   │   ├── src/                  # Your CoralMachine source
│   │   │   ├── main.cpp
│   │   │   ├── SimulationController/
│   │   │   ├── FluidSolver/
│   │   │   ├── NutrientSolver/
│   │   │   ├── CoralMesh/
│   │   │   └── CoralVox/
│   │   │
│   │   └── build/                # Build output
│   │       ├── compile_commands.json
│   │       └── coral_machine     # Your executable
│   │
│   ├── .ccache/                  # Compiler cache (10GB)
│   │
│   ├── vtk/                      # Simulation outputs
│   │   └── 2025-08-27/           # Organized by date
│   │       └── *.vtu             # VTK files
│   │
│   └── profiles/                 # GPU profiling results
│       └── nsight_reports/
│
└── usr/local/bin/
    └── startup.sh               # Auto-runs on container start
```

#### Key Path References for CMakeLists.txt
```cmake
# Your CMakeLists.txt will use these paths
cmake_minimum_required(VERSION 3.20)
project(CoralMachine)

# Find pre-installed dependencies (no compilation needed!)
find_package(Palabos REQUIRED PATHS /opt/deps)
find_package(GeometryCentral REQUIRED PATHS /opt/deps)
find_package(Polyscope REQUIRED PATHS /opt/deps)

# Build only your source code
add_executable(coral_machine
    src/main.cpp
    src/FluidSolver/FluidSolver.cpp
    # ... your sources only
)

# Link to pre-compiled libraries
target_link_libraries(coral_machine
    Palabos::Palabos        # Already compiled in image
    GeometryCentral::Core   # Already compiled in image
    Polyscope::Polyscope    # Already compiled in image
)
```

### Data Flow Architecture

```
┌─────────────────────────────┐    Git Push/Pull    ┌─────────────────────────┐
│ Local MacBook Pro           │◄──────────────────► │ GitHub Repository       │
│                             │                     │                         │
│ ┌─────────────────────────┐ │                     │ - Source Code (C++)     │
│ │ Cursor IDE              │ │                     │ - Build Scripts         │
│ │ - Remote SSH Dev        │ │                     │ - Docker Configs        │
│ │ - IntelliSense          │ │                     │ - Documentation         │
│ │ - Claude Code           │ │                     │ - Container Templates   │
│ └─────────────────────────┘ │                     └─────────────────────────┘
│ ┌─────────────────────────┐ │                               │
│ │ ParaView Client         │ │                               │ Git Clone/Pull
│ │ - Remote VTK Rendering  │ │                               │ (Container Startup)
│ │ - Animation Playback    │ │                               ▼
│ │ - No Local VTK Storage  │ │     ┌─────────────────────────────────────────────┐
│ └─────────────────────────┘ │     │ GPU Container (RunPod - Ephemeral)          │
└─────────────────────────────┘     │                                             │
         │                          │ ┌─────────────────────────────────────────┐ │
         │ SSH + Port Forward       │ │ Container Startup Sequence              │ │
         │ (22, 11111)              │ │ 1. Git clone/pull from GitHub           │ │
         ▼                          │ │ 2. Restore ccache from persistent volume│ │
┌─────────────────────────────────┐ │ │ 3. Initialize ninja build system        │ │
│ Development Interface           │ │ │ 4. Start ParaView server (port 11111)   │ │
│ - SSH Terminal (zsh)            │ │ │ 5. Launch GPU monitoring (tmux)         │ │
│ - Remote File Editing           │ │ │ 6. Ready for development (< 5 minutes)  │ │
│ - Integrated Debugging          │ │ └─────────────────────────────────────────┘ │
└─────────────────────────────────┘ │                                             │
                                    │ ┌─────────────────────────────────────────┐ │
                                    │ │ Development Environment                 │ │ 
                                    │ │ - nvc++ compiler + ninja build          │ │
                                    │ │ - ccache (10GB+ for incremental builds) │ │
                                    │ │ - Source code sync with GitHub          │ │
                                    │ │ - tmux persistent sessions              │ │
                                    │ └─────────────────────────────────────────┘ │
                                    │ ┌─────────────────────────────────────────┐ │
                                    │ │ Simulation & Analysis                   │ │
                                    │ │ - PORAG GPU-accelerated execution       │ │
                                    │ │ - Real-time GPU profiling (Nsight)      │ │
                                    │ │ - VTK sequence generation (50-200MB)    │ │
                                    │ │ - Performance monitoring & analysis     │ │
                                    │ └─────────────────────────────────────────┘ │
                                    │ ┌─────────────────────────────────────────┐ │
                                    │ │ Visualization Infrastructure            │ │
                                    │ │ - ParaView Server (headless rendering)  │ │
                                    │ │ - VTK animation sequences               │ │
                                    │ │ - Remote client connection (port 11111) │ │
                                    │ │ - No VTK file downloads required        │ │
                                    │ └─────────────────────────────────────────┘ │
                                    └─────────────────────────────────────────────┘
                                                      │
                                    ┌─────────────────────────────────────────────┐
                                    │ Persistent Storage (Survives Container)     │
                                    │                                             │
                                    │ /workspace (100GB SSD)                      │
                                    │ - Source code + Git state                   │
                                    │ - Build cache (ccache)                      │  
                                    │ - Development configurations                │
                                    │                                             │
                                    │ /data (200GB SSD)                           │
                                    │ - VTK animation sequences                   │
                                    │ - Simulation checkpoints                    │
                                    │ - Historical analysis results               │
                                    │                                             │
                                    │ /cache (50GB SSD)                           │
                                    │ - Build artifacts                           │
                                    │ - GPU profiling traces                      │
                                    │ - Temporary processing files                │
                                    └─────────────────────────────────────────────┘
```

### Critical Data Flow Principles

1. **Source Code Flow**: GitHub → Container (never Local → Container)
2. **VTK Visualization Flow**: Container generates → ParaView Server renders → MacBook ParaView Client displays (no file transfer)
3. **Development State Flow**: All state persists on volumes, containers are stateless
4. **Build Artifact Flow**: Generated on container, cached on persistent volume, never transferred
5. **Cost Optimization Flow**: Start container → Develop → Stop container → State preserved

## Technical Requirements

### Build System Optimization (Critical for Development Velocity)

#### Ninja Build System Configuration
- **Primary Builder**: ninja (3-5x faster than make for incremental C++ builds)
- **CMake Integration**: `cmake -G Ninja` for optimal build file generation
- **Parallel Job Control**: 
  - Compile jobs: 8 concurrent (based on 8-core GPU container)
  - Link jobs: 2 concurrent (memory-limited for large PORAG executable)
- **Build Performance Targets**:
  - Single file change: < 30 seconds (ninja's strength)
  - Header file change: < 2 minutes (leveraging ccache)
  - Clean full build: < 10 minutes (parallel compilation)

#### ccache Configuration (Essential for Start/Stop Workflow)
- **Cache Size**: 10GB minimum (PORAG + dependencies + multiple build types)
- **Cache Location**: `/workspace/.ccache` (persistent across container restarts)
- **Sloppiness Settings**: `time_macros,include_file_ctime` (faster cache hits)
- **Statistics Target**: >90% cache hit rate for typical development
- **Integration**: `CMAKE_CXX_COMPILER_LAUNCHER=ccache` in CMakeLists.txt

#### CMakeLists.txt Optimization Requirements
```cmake
# Required additions for ninja + ccache optimization
if(CMAKE_GENERATOR STREQUAL "Ninja")
    set_property(GLOBAL PROPERTY JOB_POOLS compile=8 link=2)
    set(CMAKE_JOB_POOL_COMPILE compile)  
    set(CMAKE_JOB_POOL_LINK link)
endif()

# ccache integration
find_program(CCACHE_FOUND ccache)
if(CCACHE_FOUND)
    set(CMAKE_CXX_COMPILER_LAUNCHER ccache)
endif()
```

### GPU Development Tools (Professional Development Environment)

#### NVIDIA HPC Compiler Environment
- **Compiler**: nvc++ from NVIDIA HPC SDK 24.7
- **CUDA Version**: 12.5+ for latest GPU features
- **Compiler Flags**: Optimized for RTX 4090/A6000 architecture
- **Integration**: Set as CMAKE_CXX_COMPILER for GPU-aware IntelliSense

#### GPU Profiling and Analysis Tools
- **Nsight Systems**: 
  - **Purpose**: Whole-application timeline analysis for epoch-based simulation
  - **Integration**: `nsys profile -o /data/profiles/coral_$(date +%s) ./coral_machine`
  - **Analysis**: GPU kernel utilization, CPU-GPU synchronization bottlenecks
- **Nsight Compute**:
  - **Purpose**: Individual CUDA kernel optimization
  - **Integration**: `ncu -o /data/profiles/kernel_analysis ./coral_machine`
  - **Focus**: AcceleratedLattice3D kernel performance tuning
- **CUDA Debugging**:
  - **cuda-gdb**: GPU-aware debugger for CUDA kernel debugging
  - **cuda-memcheck**: Memory error detection in GPU kernels
  - **Integration**: Available in Cursor IDE via remote debugging

#### Real-time Performance Monitoring
- **GPU Utilization**: `nvidia-smi` integration with tmux monitoring
- **Memory Tracking**: GPU memory usage during large coral simulations
- **Temperature Monitoring**: Thermal throttling detection during long runs
- **Build Performance**: ccache statistics and build time tracking

### VTK Visualization Strategy (Intensive Visualization Workflow)

#### Problem Statement
- **VTK File Size**: 50-200MB per frame for detailed coral geometry
- **Animation Sequences**: Full temporal sequences required for analysis  
- **Network Limitations**: Impractical to download multi-gigabyte sequences
- **Interactive Requirements**: Real-time visualization manipulation needed

#### ParaView Server Solution Architecture

##### Server-Side Configuration (GPU Container)
```bash
# ParaView server startup configuration
pvserver \
    --server-port=11111 \
    --disable-xdisplay-test \
    --force-offscreen-rendering \
    --mesa-llvm &

# Virtual display for headless OpenGL
Xvfb :99 -screen 0 1024x768x24 &
export DISPLAY=:99
```

**Technical Specifications**:
- **Rendering**: Headless OpenGL via Mesa/EGL (no X11 dependency)
- **Port**: 11111 (standard ParaView server port)
- **Security**: SSH tunnel from local machine (no direct internet exposure)
- **GPU Acceleration**: OpenGL rendering on NVIDIA GPU for performance
- **Memory Management**: Stream large datasets without local storage

##### Client-Side Configuration (MacBook)
**ParaView Client Setup**:
- **Connection**: Server configuration pointing to SSH-tunneled localhost:11111
- **Rendering**: Local client rendering with remote data
- **Interaction**: Full ParaView UI functionality with remote datasets
- **Performance**: 15+ FPS for interactive coral visualization

**SSH Tunnel Configuration**:
```bash
# In ~/.ssh/config
Host porag-runpod
    HostName <dynamic-runpod-ip>
    User root
    Port 22
    LocalForward 11111 localhost:11111
    ServerAliveInterval 60
```

##### VTK Animation Workflow Integration
**Automated Sequence Generation** (in PORAG simulation code):
```cpp
// Custom example for demonstration, prefer VTK object export via Palabos VTK classes  
class VTKAnimationExporter {
    void exportEpochSequence(int epoch, const CoralState& coral) {
        std::string epoch_dir = "/data/vtk/epoch_" + std::to_string(epoch);
        // Export time sequence for this epoch
        for (int step = 0; step < steps_per_epoch; ++step) {
            exportTimeStep(epoch_dir, step, coral.getGeometryAtStep(step));
        }
        // Generate .pvd animation file for ParaView
        generateAnimationDescriptor(epoch_dir);
    }
};
```

**File Management Strategy**:
- **Storage Location**: `/data/vtk/` on persistent volume
- **Organization**: Simulation start time + date
- **Cleanup**: Automated cleanup of old VTK files based on age/size limits

### Container Lifecycle Management

#### Ultra-Fast Deployment via Pre-Built Image
With all dependencies pre-compiled, the container achieves **full productivity in under 90 seconds**.

##### Actual Container Startup Script
```bash
#!/bin/bash
# /usr/local/bin/startup.sh - Minimal, fast startup
echo "🚀 PORAG Dev Environment Starting (90 seconds to productivity)"

# 1. Pull latest source code (10 seconds)
if [ -d "/workspace/source/.git" ]; then
    cd /workspace/source && git pull
else
    git clone https://github.com/username/coralMachine.git /workspace/source
fi

# 2. Configure build (20 seconds - deps already built in /opt/deps)
cd /workspace/source
cmake -G Ninja -B build \
    -DCMAKE_PREFIX_PATH=/opt/deps \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_COMPILER=nvc++

# 3. Build CoralMachine only (60 seconds first time, 30s incremental)
echo "🔨 Building CoralMachine (deps pre-compiled)..."
ccache -s  # Show cache stats
ninja -C build

# 4. Start services (parallel with build)
{
    # ParaView server (already installed)
    Xvfb :99 -screen 0 1024x768x24 &
    export DISPLAY=:99
    pvserver --server-port=11111 --disable-xdisplay-test &
    
    # GPU monitoring
    tmux new-session -d -s gpu 'watch -n 1 nvidia-smi'
} &

echo "✅ Ready for development! Connect via SSH from Cursor."
exec zsh
```

##### What Actually Gets Persisted
**Persistent Volume Contents** (`/workspace/`):
- **Source code**: Your cloned/modified CoralMachine code
- **Build artifacts**: `/workspace/source/build/` directory
- **ccache**: `/workspace/.ccache` (10GB of cached compilations)
- **VTK outputs**: `/workspace/vtk/` simulation results
- **Shell history**: Development command history

**What's Already in the Image** (no download/build needed):
- All compiled dependencies (Palabos, geometry-central, Polyscope)
- ParaView server installation
- Development tools (nvc++, ninja, cmake, debugging tools)
- Pre-configured environment

#### Pre-Built Image Creation (One-Time)
```dockerfile
# This Dockerfile is built ONCE and pushed to Docker Hub
# docker build -t gstvbrg/coral-machine-dev:latest .
# docker push gstvbrg/coral-machine-dev:latest
FROM nvcr.io/nvidia/nvhpc:24.7-devel-cuda12.5-ubuntu22.04

# Install dev tools
RUN apt-get update && apt-get install -y \
    cmake ninja-build ccache git zsh tmux \
    nsight-systems-cli nsight-compute-cli wget curl \
    && rm -rf /var/lib/apt/lists/*

# Build and install all heavy dependencies
WORKDIR /tmp/deps

# Palabos-hybrid prerelease
RUN git clone https://github.com/palabos/palabos-hybrid.git && \
    cd palabos-hybrid && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps && \
    make -j$(nproc) install

# geometry-central
RUN git clone --recursive https://github.com/nmwsharp/geometry-central.git && \
    cd geometry-central && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps && \
    make -j$(nproc) install

# Polyscope
RUN git clone --recursive https://github.com/nmwsharp/polyscope.git && \
    cd polyscope && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps && \
    make -j$(nproc) install

# ParaView server
RUN wget -O paraview.tar.gz "https://www.paraview.org/paraview-downloads/download.php?submit=Download&version=v5.11&type=binary&os=Linux&downloadFile=ParaView-5.11.0-MPI-Linux-Python3.9-x86_64.tar.gz" && \
    tar -xzf paraview.tar.gz -C /opt && \
    rm paraview.tar.gz

ENV PATH="/opt/ParaView-5.11.0-MPI-Linux-Python3.9-x86_64/bin:$PATH"
ENV CMAKE_PREFIX_PATH="/opt/deps"
ENV CCACHE_DIR=/workspace/.ccache
ENV CCACHE_MAXSIZE=10G

# Copy startup script
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

WORKDIR /workspace
CMD ["/usr/local/bin/startup.sh"]
```

### RunPod Deployment

#### Pre-Built Image Deployment
```yaml
RunPod Template:
  Name: "Coral-Machine-Workstation"
  Container Image: "gstvbrg/coral-machine-dev:latest"  # Pre-built, 15GB
  
  GPU Selection (cost-optimized):
    - RTX 4090: $0.34/hour (best value)
    - RTX A6000: $0.79/hour (more VRAM)
    - A100: $1.10/hour (maximum performance)
  
  Minimum Requirements:
    - GPU: 16GB+ VRAM
    - CPU: 8 cores
    - RAM: 32GB
    - Disk: 30GB container + 200GB persistent volume
  
  Persistent Volume Mount:
    - /workspace → 200GB SSD (source, builds, VTK files)
  
  Exposed Ports:
    - 22: SSH
    - 11111: ParaView Server
  
  Startup Command: /usr/local/bin/startup.sh
```

#### Actual Deployment Steps
1. **One-time setup**:
   ```bash
   # Create RunPod template with above config
   # Attach persistent volume for /workspace
   ```

2. **Daily workflow**:
   ```bash
   # Start pod (30 seconds)
   runpod pods create --templateId=your-template
   
   # Wait for startup (60 seconds for git pull + build)
   # SSH connect from Cursor
   ssh root@pod-ip -L 11111:localhost:11111
   
   # Work all day...
   
   # Stop pod (saves money, preserves state)
   runpod pods stop pod-id
   ```

3. **Next day**:
   ```bash
   # Restart same pod (30 seconds)
   runpod pods start pod-id
   
   # Incremental build only (ccache warm)
   # Back to full productivity in < 90 seconds
   ```

#### Cost Analysis
- **Active development**: ~$3-8/day (8-10 hours on RTX 4090)
- **Storage**: ~$20/month (200GB persistent volume)
- **Total monthly**: ~$80-180 (vs $500+/month for always-on)
- **Time to productivity**: 90 seconds (vs 30+ minutes building deps)

### Development Environment Configuration

#### Cursor IDE Integration
**SSH Configuration** (`~/.ssh/config`):
```
Host porag-dev
    HostName dynamic-runpod-ip
    User root  
    Port 22
    ForwardX11 no
    LocalForward 11111 localhost:11111
    ServerAliveInterval 60
    ServerAliveCountMax 3
    IdentityFile ~/.ssh/id_rsa
```

**Cursor Settings** (`.vscode/settings.json`):
```json
{
    "cmake.generator": "Ninja",
    "cmake.buildDirectory": "/workspace/build", 
    "cmake.buildArgs": ["-j", "8"],
    "cmake.defaultVariants": {
        "buildType": "RelWithDebInfo"
    },
    
    "C_Cpp.default.compilerPath": "/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin/nvc++",
    "C_Cpp.default.intelliSenseMode": "linux-gcc-x64",
    "C_Cpp.default.cppStandard": "c++20",
    
    "terminal.integrated.defaultProfile.linux": "zsh",
    "terminal.integrated.cwd": "/workspace",
    
    "files.watcherExclude": {
        "**/build/**": true,
        "**/.ccache/**": true,
        "**/data/vtk/**": true,
        "**/*.vtu": true,
        "**/*.pvd": true
    },
    
    "remote.SSH.defaultExtensions": [
        "ms-vscode.cpptools-extension-pack",
        "ms-vscode.cmake-tools", 
        "nvidia.nsight-vscode-edition",
        "ms-vscode.remote-ssh"
    ]
}
```

#### Zsh Shell Configuration
**Custom `.zshrc` for PORAG development**:
```bash
# PORAG development environment
export WORKSPACE=/workspace
export CCACHE_DIR=/workspace/.ccache
export CUDA_VISIBLE_DEVICES=all

# Development aliases
alias pdev='cd $WORKSPACE && tmux new-session -d -s porag'
alias pbuild='ninja -C /workspace/build'
alias prun='./build/coral_machine'
alias pprofile='nsys profile -o /data/profiles/run_$(date +%s) ./build/coral_machine'
alias pmonitor='tmux attach-session -t monitoring'
alias pvtk='ls -lah /data/vtk/'

# Git shortcuts  
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push origin main'

# GPU monitoring
alias gpu='nvidia-smi'
alias gpuw='watch -n 1 nvidia-smi'

# ParaView server management
alias pvstart='pvserver --server-port=11111 --disable-xdisplay-test --force-offscreen-rendering &'
alias pvstop='pkill pvserver'

# Build performance
alias cache='ccache -s'
alias cacheclean='ccache -C'

echo "🐠 PORAG Development Environment Ready"
echo "   Build: pbuild"
echo "   Run: prun  
echo "   Profile: pprofile"
echo "   Monitor: pmonitor"
echo "   ParaView: Connect client to localhost:11111"
```

## Workflow Integration Points

### GitHub Integration
- **Container Startup**: Auto-clone/pull from GitHub on deployment
- **Development**: Regular commits from container environment  
- **Collaboration**: Standard Git workflow for team development
- **Backup**: Source code always safely stored in GitHub

### IDE Integration (Cursor)
- **SSH Connection**: Seamless connection to container development environment
- **IntelliSense**: C++ language server with NVIDIA compiler awareness
- **Debugging**: Remote debugging through SSH with GPU extensions
- **Terminal**: Multiple persistent terminals (tmux) for long simulations
- **File Sync**: Automatic synchronization of edited files

### Simulation Development
- **Quick Iteration**: Edit → Build → Test cycle optimized for < 2 minutes
- **GPU Profiling**: Integrated kernel analysis during development
- **Epoch Analysis**: Performance tracking for coral growth simulations  
- **Parameter Tuning**: Easy adjustment of simulation parameters
- **Result Analysis**: Python scripts for post-processing coral data

### Developer Experience Validation

#### IDE Integration Quality
- [ ] **Full IntelliSense functionality** via remote SSH development
  - **Validation Procedure**:
    1. Open PORAG source file in Cursor via SSH
    2. Verify code completion for PORAG classes (CoralMesh, FluidSolver)
    3. Verify error highlighting for syntax issues
    4. Verify "Go to Definition" for custom classes
    5. Verify "Find All References" across project
  - **Success Criteria**: Feature parity with local development experience

- [ ] **Integrated debugging** with GPU extensions
  - **Validation Procedure**:
    1. Set breakpoints in coral simulation code
    2. Launch debug session from Cursor IDE  
    3. Verify GPU thread inspection with cuda-gdb integration
    4. Verify variable inspection during GPU kernel execution
  - **Success Criteria**: Full debugging workflow without manual tool switching

- [ ] **Git workflow integration** from container environment
  - **Validation Procedure**:
    1. Make code changes in container
    2. Verify Git status/diff from Cursor IDE
    3. Commit changes with descriptive message
    4. Push to GitHub main branch
    5. Verify no conflicts with local Git repository
  - **Success Criteria**: Seamless version control without manual synchronization

#### Workflow Persistence Validation
- [ ] **Development state preservation** across container restarts
  - **Validation Procedure**:
    1. Perform development session (build, modify code, run simulation)
    2. Stop RunPod container  
    3. Restart container after 24 hours
    4. Verify ccache statistics preserved
    5. Verify Git state preserved
    6. Verify zsh history preserved
    7. Verify tmux sessions restored
  - **Success Criteria**: Zero setup time for resumed development

- [ ] **VTK file persistence** and organization
  - **Validation Procedure**:
    1. Generate VTK sequences from coral simulation
    2. Verify files organized by epoch and timestamp
    3. Restart container and verify VTK files accessible
    4. Verify ParaView can load historical sequences
  - **Success Criteria**: No data loss, logical file organization

## Implementation Roadmap

### Phase 1: Build Pre-Built Image (One-Time)
**Timeline**: 1-2 days
**Purpose**: Create the complete development image with all dependencies

#### Tasks:
- [ ] **Create comprehensive Dockerfile** with all dependencies
- [ ] **Build Palabos-hybrid** from source with GPU support
- [ ] **Build geometry-central** optimized for PORAG  
- [ ] **Build Polyscope** visualization library
- [ ] **Install ParaView server** with headless support
- [ ] **Configure development environment** (zsh, tmux, tools)
- [ ] **Write minimal startup.sh** (just git pull + cmake + build)
- [ ] **Build and test image locally** with Docker
- [ ] **Push to Docker Hub** for RunPod access

**Deliverable**: `coral-gpu-dev:latest` image (~15GB) on Docker Hub

### Phase 2: RunPod Setup & Testing
**Timeline**: 2-3 hours
**Purpose**: Deploy and validate the remote GPU workstation

#### Tasks:
- [ ] **Create RunPod template** pointing to Docker Hub image
- [ ] **Configure persistent volume** (200GB for /workspace)
- [ ] **Deploy test pod** with RTX 4090
- [ ] **Verify startup time** (target: <90 seconds)
- [ ] **Test SSH connection** from Cursor IDE
- [ ] **Validate ParaView server** connection
- [ ] **Run test simulation** with GPU acceleration
- [ ] **Verify persistent state** after stop/restart

**Deliverable**: Working RunPod template for daily use

### Phase 3: Development Workflow Optimization
**Timeline**: Ongoing during first week of use
**Purpose**: Fine-tune the development experience

#### Tasks:
- [ ] **Optimize CMakeLists.txt** to find pre-built deps efficiently
- [ ] **Tune ccache settings** for CoralMachine patterns
- [ ] **Create shell aliases** for common operations
- [ ] **Set up tmux layouts** for monitoring + development
- [ ] **Configure Cursor SSH** for optimal responsiveness
- [ ] **Document common workflows** in README

**Deliverable**: Smooth, <30-second incremental build workflow

### Total Implementation Time: 3-4 Days

#### Day 1-2: Build and push the pre-built image
#### Day 3: Deploy to RunPod and test
#### Day 4: Fine-tune and document

## Conclusion & Implementation Principles

### Design Philosophy

This document describes a **remote GPU workstation** approach using RunPod, where:

1. **Everything is pre-built**: One Docker image contains all compiled dependencies
2. **Deployment is instant**: <90 seconds from pod start to coding
3. **Development is seamless**: SSH remote development via Cursor IDE
4. **Builds are incremental**: Only your source code compiles (deps are done)
5. **State persists**: Stop/start pods without losing work

### Why This Architecture Works

#### Simplicity Wins
- **No Docker builds during development** - just deploy and code
- **No dependency compilation** - everything pre-built in image
- **No complex orchestration** - treat as remote workstation
- **No data transfer** - VTK stays remote, viewed via ParaView server

#### Performance Achieved
- **90-second deployment** (vs 30+ minutes building dependencies)
- **30-second incremental builds** (ccache + only your code)
- **Instant dependency access** (pre-compiled in image)
- **Full GPU acceleration** (nvc++ with Palabos-hybrid)

### Implementation Simplicity

The entire system requires just:

1. **One Dockerfile** to build the complete image (once)
2. **One startup script** to pull code and build (90 seconds)
3. **One RunPod template** to deploy consistently
4. **One persistent volume** for all your work

### Real Developer Experience

```bash
# Monday morning
runpod pods start my-gpu-pod          # 30 seconds
ssh root@pod-ip                        # Pod auto-pulled code, built it
cd /workspace/source
ninja -C build                         # 30 seconds (warm ccache)
./build/coral_machine                  # GPU-accelerated simulation
# ... productive development all day ...
runpod pods stop my-gpu-pod            # Save money overnight

# Tuesday morning  
runpod pods start my-gpu-pod          # 30 seconds
# Back to exactly where you left off
```

---

**Document Status**: Simplified and Ready  
**Implementation Time**: 3-4 days total
**Daily Time to Productivity**: <90 seconds