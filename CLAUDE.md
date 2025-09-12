# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds Docker development environments for coral machine simulation (PORAG) optimized for RunPod GPU workstations. The project uses a **modular volume-based architecture** to achieve <90 seconds from deployment to full development productivity.

## Current Architecture: Modular Volume Setup

### Version Configuration
- **CUDA**: 12.6.2
- **NVIDIA HPC SDK**: 24.11 (NOTE: Blackwell/cc100 requires SDK 25.3+)
- **Supported GPU Architectures**:
  - cc80: Ampere (A100, A6000, RTX 3090)
  - cc86: Ampere (RTX 3080, 3070, 3060)
  - cc89: Ada Lovelace (RTX 4090, 4080, L40S)
  - cc90: Hopper (H100, H200)
  - ~~cc100: Blackwell (B200, B100)~~ **Requires HPC SDK 25.3+**

### Testing Strategy
We are currently testing in **volume-setup/** directory with a modular installer system. This approach uses:
1. **Builder image (~1GB)**: Contains build tools, used only during setup
2. **Runtime image (~500MB)**: Minimal runtime environment for development
3. **Persistent volumes**: Pre-compiled dependencies stored in volumes

### Benefits
- **Modular installation**: Each component has its own installer script
- **Idempotent**: Can safely re-run installers (checks for existing installs)
- **Fast restarts**: <90 seconds for warm starts (cached image)
- **Cost efficient**: $26/month for persistent storage vs repeated downloads
- **Perfect for development**: Frequent stop/start workflow supported

### Volume Structure (Testing Phase)
```
volume-setup/volumes/
├── deps/                   # All dependencies installed here for testing
│   ├── bin/               # All executables (pvserver, etc.)
│   ├── lib/               # All libraries (libpalabos.a, etc.)
│   ├── include/           # All headers (organized in subdirectories)
│   │   ├── eigen3/        # Eigen3 math library
│   │   ├── hdf5/          # HDF5 headers (in subdirectory)
│   │   ├── palabos/       # Palabos CFD headers
│   │   ├── geometrycentral/  # Geometry processing
│   │   ├── paraview/      # ParaView headers
│   │   └── polyscope/     # Visualization headers
│   ├── share/             # Shared data files
│   ├── nvidia-hpc/        # NVIDIA HPC SDK (special case, not flattened)
│   ├── env.sh             # Environment setup script
│   └── .installed/        # Marker files for idempotency
└── workspace/             # Separate workspace volume (for testing)
```

**Future Production Structure**: Single volume where deps/ becomes a subdirectory of /workspace/

## Repository Structure

```
coral-machine-docker/
├── volume-setup/         # CURRENT TESTING APPROACH (use this)
│   ├── config.env       # Central configuration
│   ├── lib/            # Shared utility functions
│   │   └── common.sh
│   ├── installers/     # Modular installer scripts
│   │   ├── 00-prep.sh          # Environment preparation
│   │   ├── 01-compilers.sh     # NVIDIA HPC SDK
│   │   ├── 02-build-headers.sh # Development headers
│   │   ├── 03-core-libraries.sh # Palabos, geometry-central
│   │   └── 04-visualization.sh  # ParaView, Polyscope
│   ├── docker/
│   │   ├── Dockerfile.builder  # Build environment
│   │   ├── Dockerfile.runtime  # Development environment
│   │   └── startup.sh
│   ├── docker-compose.yml
│   ├── Makefile        # Convenient commands
│   └── README.md
├── volume-based/        # Previous approach (being replaced)
└── legacy-monolithic/   # Old 25GB approach (deprecated)
```

## Common Commands

### Volume Setup Workflow (Current Testing)
```bash
cd volume-setup/

# One-time volume setup (30-45 minutes)
make setup

# Daily development (starts in <90 seconds)
make dev

# Connect via SSH
make ssh
# or
ssh coral-dev@localhost -p 2222

# Open shell directly
make shell
```

### Docker Image Management
```bash
# Build images (from volume-setup/)
make build          # Build both images
make build-builder  # Just builder image
make build-runtime  # Just runtime image

# Push to Docker Hub for RunPod (future)
docker tag coral-setup:builder gstvbrg/coral-setup:builder
docker push gstvbrg/coral-setup:builder
```

### Individual Component Installation
```bash
# Run specific installers (useful for debugging)
make install-prep       # Setup build environment
make install-compilers  # Install NVIDIA HPC SDK
make install-headers    # Install build headers
make install-libraries  # Build core libraries (Palabos, geometry-central)
make install-viz        # Install visualization tools (ParaView, Polyscope)
```

### Maintenance Commands
```bash
make test          # Test installation
make status        # Show container/volume status
make logs          # View setup logs
make clean         # Remove all data (careful!)
make rebuild       # Rebuild Docker images
```

### Development Workflow
```bash
# Inside container - typical development cycle
cd /workspace/source
git pull                    # Update source code
cmake -G Ninja -B build     # Configure (finds pre-built deps)
ninja -C build             # Incremental build (~30 seconds)
./build/coral_machine      # Run GPU simulation
```

### Build System Configuration
- **Build system**: Ninja (for fast incremental builds)
- **Compiler**: nvc++ (NVIDIA GPU-aware compiler)  
- **Cache**: ccache with 10GB limit for incremental builds
- **Target build time**: <30 seconds for typical changes, <2 minutes full rebuild

### GPU Development Tools
```bash
# GPU profiling
nsys profile -o /data/profiles/run_$(date +%s) ./build/coral_machine
ncu -o /data/profiles/kernel_analysis ./build/coral_machine

# GPU monitoring  
nvidia-smi
watch -n 1 nvidia-smi
```

### Visualization
- **ParaView server**: Runs headless on port 11111 in container
- **Client connection**: SSH tunnel from local ParaView client
- **VTK files**: Generated in `/workspace/vtk/`, organized by date
- **No local storage**: VTK files stay remote, viewed via ParaView server

## Implementation Status

**Current Phase**: Testing modular volume-setup approach locally
**Architecture**: Modular installer system with separate builder/runtime images

### Completed
- ✅ Modular installer architecture (5 separate scripts)
- ✅ Central configuration system (config.env)
- ✅ Builder and runtime Docker images
- ✅ Docker Compose orchestration
- ✅ Makefile for convenient commands
- ✅ Idempotent installation markers
- ✅ Windows line ending fixes (.gitattributes + Dockerfile handling)
- ✅ Docker build context optimization (.dockerignore)

### In Testing
- 🔄 Full orchestrated setup (make setup)
- 🔄 Individual installer validation
- 🔄 Volume persistence across restarts
- 🔄 Development workflow validation

### Next Steps
1. Complete local testing of all 7 components
2. Verify development environment (SSH, compilers, libraries)
3. Push images to Docker Hub
4. Deploy and test on RunPod
5. Migrate to single /workspace volume with deps/ as subdirectory

## Development Environment Integration

### Cursor IDE Setup
- **Connection**: SSH remote development to container
- **Compiler**: nvc++ for GPU-aware IntelliSense
- **Build integration**: CMake + Ninja build system
- **Port forwarding**: 11111 for ParaView server connection

### Performance Targets (Volume-Based)
- **First setup**: 30-45 minutes (one-time volume initialization)
- **Cold start**: 2-3 minutes (image pull + volume mount)
- **Warm start**: <90 seconds ✅ (cached image + volume mount)
- **Incremental build**: <30 seconds
- **SSH connection**: <20 seconds

## Key Design Principles

1. **Modular installation**: Each component has its own installer script
2. **Volume-based dependencies**: Heavy builds live in persistent volumes, not images
3. **Minimal Docker images**: Builder (~1GB) and Runtime (~500MB) kept small
4. **Incremental development**: Only CoralMachine source compiles during development  
5. **State persistence**: Everything important survives container restarts via volumes
6. **Remote visualization**: VTK files never leave container, viewed via ParaView server
7. **Cost optimization**: $26/month for storage vs repeated multi-GB downloads
8. **Developer velocity**: <90 second restarts for frequent stop/start workflow
9. **Idempotent operations**: Scripts can be safely re-run without breaking

## Important Configuration Notes

### Central Configuration (config.env)
- All versions, paths, and flags in one place
- Source this file to get consistent settings across all scripts
- Key variables:
  - `DEPS_ROOT="/workspace/deps"` - Where all dependencies install
  - `NVIDIA_HPC_VERSION="24.7"` - NVIDIA SDK version
  - `BUILD_JOBS=$(nproc)` - Parallel build jobs
  - `CCACHE_SIZE="10G"` - Compiler cache size

### Known Issues & Solutions

1. **Configuration Conflicts (FIXED)**:
   - **Problem**: Dual configuration system (.env vs config.env) caused BUILD_JOBS and variable name conflicts
   - **Solution**: Single Source of Truth - .env is master, config.env uses environment variables with fallbacks
   - **Pattern**: `export VAR=${VAR:-default}` ensures .env values override config.env defaults

2. **Windows Line Endings**: 
   - Fixed via .gitattributes and Dockerfile sed commands
   - All .sh files forced to LF endings

3. **Docker Build Context Size**:
   - Use .dockerignore to exclude volumes/ directory
   - Reduces context from 13GB to <100KB

4. **MPI Installation**:
   - Core libraries installer needs system MPI (libopenmpi-dev)
   - Installed automatically if not present

5. **Library Organization**:
   - Headers go in subdirectories: `include/hdf5/`, `include/palabos/`, etc.
   - Libraries in flat `lib/` directory
   - Binaries in flat `bin/` directory

6. **Storage Consistency (FIXED)**:
   - **Problem**: Individual tests used bind mounts, orchestrated setup used named volumes
   - **Solution**: docker-compose.yml configured for bind mounts consistently
   - **Result**: All storage now uses `./volumes/deps/` and `./volumes/workspace/`

## Critical Learnings: Palabos GPU Build Configuration

### MPI Implementation Issues
1. **Palabos uses deprecated MPI C++ bindings** (removed in MPI-4.0)
   - Requires symbols like `MPI::Comm::Comm()` and `ompi_mpi_comm_null`
   - OpenMPI maintains these for backwards compatibility
   - NVIDIA's MPICH-based MPI lacks full C++ binding support

2. **Compiler/MPI Consistency is Critical**
   - Palabos MUST be compiled with the same compiler as your application
   - MPI C++ bindings are compiler-specific (g++ vs nvc++ mangle differently)
   - Mixing g++-compiled Palabos with nvc++-compiled apps causes undefined references

### Correct GPU Build Approach (from Palabos GPU examples)
The Palabos hybrid GPU examples (cavity3d, sandstone, etc.) show the intended pattern:

```cmake
# GPU examples rebuild Palabos from source with nvc++
file(GLOB_RECURSE PALABOS_SRC "../../../src/*.cpp")
file(GLOB_RECURSE EXT_SRC "../../../externalLibraries/tinyxml/*.cpp")
add_library(palabos STATIC ${PALABOS_SRC} ${EXT_SRC})
```

**Key insight**: Don't pre-build Palabos separately. Build it together with your application using nvc++.

### Compiler Flags for GPU
- **nvc++**: Use `-stdpar=multicore` (not `-stdpar=gpu`) to avoid unsupported operation errors
- **GPU flags**: `-gpu=cc80,cc86,cc89,cc90` for multiple architectures  
- **Required**: `-DUSE_CUDA_MALLOC` for GPU memory management
- **OpenMP**: Use `-mp` flag, but beware of missing symbols like `__kmpc_for_static_init_16`

### MPI Configuration
- **NVIDIA HPC SDK includes OpenMPI** at multiple locations:
  - `/workspace/deps/nvidia-hpc/.../comm_libs/12.5/openmpi4/openmpi-4.1.5/`
  - `/workspace/deps/nvidia-hpc/.../comm_libs/openmpi/openmpi-3.1.5/`
- However, these OpenMPI versions don't include MPI C++ bindings
- System OpenMPI (`apt install libopenmpi-dev`) does include C++ bindings

### NVHPC Compiler Support Issue (RESOLVED)
**Problem**: Main Palabos CMakeLists.txt only recognizes GNU, Clang, AppleClang, and MSVC compilers. When encountering NVHPC (nvc++), it fails with "CXX compiler not recognized" at line 88.

**Root Cause**: Palabos-hybrid main CMakeLists.txt lacks NVHPC compiler detection, despite GPU examples showing full nvc++ support.

**Critical Investigation Findings**:
1. **GPU Examples Pattern Analysis**: All GPU examples (`examples/gpuExamples/cavity3d/`, `sandstone/`, `multiComponentPorous/`, `tgv3d/`, `rayleighTaylor3D/`) use identical NVHPC detection:
   ```cmake
   elseif(${CMAKE_CXX_COMPILER_ID} STREQUAL PGI OR ${CMAKE_CXX_COMPILER_ID} STREQUAL NVHPC) # for nvc++
       message("nvc++")
       set(CMAKE_CXX_FLAGS "-stdpar -std=c++20 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC")
       set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
       set(CMAKE_CXX_FLAGS_DEBUG "-g -DPLB_DEBUG -O1")
   ```

2. **GPU Examples Architecture**: They don't use pre-built libraries, they rebuild Palabos from source per application:
   ```cmake
   file(GLOB_RECURSE PALABOS_SRC "../../../src/*.cpp")
   file(GLOB_RECURSE EXT_SRC "../../../externalLibraries/tinyxml/*.cpp")
   add_library(palabos STATIC ${PALABOS_SRC} ${EXT_SRC})
   ```

3. **Critical GPU Compiler Flags**:
   - **`-stdpar`**: Enables GPU parallelization via C++ standard parallelism
   - **`-std=c++20`**: Modern C++ standard (some examples use c++17, cavity3d uses c++20)
   - **`-Msingle -Mfcon`**: NVIDIA compiler optimization flags
   - **`-fopenmp`**: OpenMP support (NOT `-mp` as used elsewhere)
   - **`-DUSE_CUDA_MALLOC`**: Enable CUDA memory allocation

4. **Compiler Flag Variations Observed**:
   - **cavity3d**: `-stdpar -std=c++20 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC`
   - **sandstone**: `-stdpar -std=c++20 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC`  
   - **multiComponentPorous**: `-stdpar -std=c++17 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC`
   - **Consistent pattern**: All use `-stdpar`, `-Msingle -Mfcon`, `-fopenmp`, `-DUSE_CUDA_MALLOC`

**Final Solution**: Patch main CMakeLists.txt during installation to add NVHPC support with exact GPU example flags:
```bash
# In 03-core-libraries.sh installer - Corrected version
cat > nvhpc_patch.txt << 'EOF'
elseif(${CMAKE_CXX_COMPILER_ID} STREQUAL PGI OR ${CMAKE_CXX_COMPILER_ID} STREQUAL NVHPC)
    message("NVHPC/PGI compiler detected.")
    set(CMAKE_CXX_FLAGS "-stdpar -std=c++20 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC")
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
    set(CMAKE_CXX_FLAGS_DEBUG "-g -DPLB_DEBUG -O1")
    set(CMAKE_CXX_FLAGS_TEST "-g -DPLB_DEBUG -DPLB_REGRESSION -O1")
    set(CMAKE_CXX_FLAGS_TESTMPI "-g -DPLB_DEBUG -DPLB_REGRESSION -O1")
EOF
sed -i '87r nvhpc_patch.txt' CMakeLists.txt
rm -f nvhpc_patch.txt
```

**Key Corrections from First Attempt**:
- ✅ **Added `-stdpar`**: Critical for GPU parallelization
- ✅ **Changed to `-fopenmp`**: GPU examples use this, not `-mp`
- ✅ **Added C++20**: Modern standard matching cavity3d
- ✅ **Reliable file insertion**: Avoids complex sed multi-line syntax
- ✅ **Complete flag set**: Includes TEST and TESTMPI flags

This maintains the volume architecture philosophy - Palabos built once with nvc++ during setup, not rebuilt for every application.

### Solution Strategy
For GPU-accelerated Palabos applications:
1. **Pre-build Palabos with nvc++ during setup** (maintains fast build architecture)
2. Use consistent NVIDIA MPI throughout (NVIDIA HPC SDK OpenMPI)
3. Patch main CMakeLists.txt to recognize NVHPC compiler
4. Use proven flags from GPU examples: `-std=c++17 -Msingle -Mfcon -mp -DUSE_CUDA_MALLOC`