# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds Docker development environments for coral machine simulation (PORAG) optimized for RunPod GPU workstations. The project now uses a **volume-based architecture** to achieve <90 seconds from deployment to full development productivity.

## Current Architecture: Volume-Based Strategy

### Two-Part System
1. **Minimal base image (5GB)**: NVIDIA HPC SDK + essential tools only
2. **Persistent volumes (175GB)**: Pre-compiled dependencies + workspace

### Benefits
- **Fast restarts**: <90 seconds for warm starts (cached image)
- **Cost efficient**: $26/month for persistent storage vs repeated downloads
- **Perfect for development**: Frequent stop/start workflow supported

### Volume Structure
```
/workspace/deps/            # Pre-compiled dependencies (mounted from volume)
├── paraview/              # ParaView server (headless)
├── palabos-hybrid/        # Pre-compiled Palabos library
├── geometry-central/      # Mesh processing library
└── include/               # All library headers

/workspace/                # Persistent development area (volume)
├── source/               # Git repository (CoralMachine)
├── build/                # Ninja build outputs  
├── .ccache/              # Compiler cache (10GB)
└── vtk/                  # VTK simulation outputs
```

## Repository Structure

```
coral-machine-docker/
├── volume-based/         # CURRENT APPROACH (use this)
│   ├── docker/          # Dockerfile.base + Dockerfile.setup
│   ├── scripts/         # setup-volume.sh + startup.sh
│   ├── docker-compose.yml
│   └── README.md
├── legacy-monolithic/    # Old 25GB approach (deprecated)
└── docs/                # Shared documentation
```

## Common Commands

### Volume-Based Workflow
```bash
cd volume-based/

# One-time volume setup (30-45 minutes)
docker-compose --profile setup run setup

# Daily development (starts in <90 seconds)
docker-compose --profile dev up -d dev

# Connect via SSH
ssh dev@localhost -p 2222
```

### Docker Image Management
```bash
# Build minimal base image (5GB)
docker build -f docker/Dockerfile.base -t coral-dev:base .

# Push to Docker Hub for RunPod
docker tag coral-dev:base gstvbrg/coral-dev:volume-based
docker push gstvbrg/coral-dev:volume-based
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

**Current Phase**: Volume-based architecture implemented and ready for testing
**Architecture**: Switched from monolithic 25GB image to 5GB base + persistent volumes

### Completed
- ✅ Volume-based architecture design
- ✅ Minimal base image (Dockerfile.base)
- ✅ Volume setup automation (Dockerfile.setup + setup-volume.sh)
- ✅ Docker Compose orchestration
- ✅ Repository reorganization for clarity

### Next Steps
1. Test volume initialization locally
2. Push base image to Docker Hub
3. Deploy and test on RunPod
4. Optimize based on real-world usage

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

1. **Volume-based dependencies**: Heavy builds live in persistent volumes, not images
2. **Minimal base images**: Only essential runtime components in Docker image
3. **Incremental development**: Only CoralMachine source compiles during development  
4. **State persistence**: Everything important survives container restarts via volumes
5. **Remote visualization**: VTK files never leave container, viewed via ParaView server
6. **Cost optimization**: $26/month for storage vs repeated multi-GB downloads
7. **Developer velocity**: <90 second restarts for frequent stop/start workflow