# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds Docker development environments for coral machine simulation (PORAG) optimized for RunPod GPU workstations. The project uses a **modular volume-based architecture** to achieve <90 seconds from deployment to full development productivity.

## Current Architecture: Modular Volume Setup

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