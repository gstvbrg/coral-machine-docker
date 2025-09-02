# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds a pre-compiled Docker development environment for coral machine simulation (PORAG) optimized for RunPod GPU workstations. The core philosophy is **everything pre-built** - all heavy dependencies (Palabos-hybrid, geometry-central, Polyscope, ParaView server) are compiled into a single Docker image to achieve <90 seconds from deployment to full development productivity.

## Architecture

### Single Pre-Built Image Strategy
- **Base**: NVIDIA HPC SDK 24.7 with CUDA 12.5
- **Pre-compiled dependencies**: Palabos-hybrid, geometry-central, Polyscope, ParaView server
- **Development tools**: nvc++ (GPU compiler), ninja, ccache, tmux, zsh
- **Target deployment**: RunPod GPU instances (RTX 4090/A6000/A100)
- **Storage strategy**: Persistent volumes for `/workspace` (source code, builds, VTK files)

### Container Directory Structure
```
/opt/deps/          # Pre-built dependencies (read-only, in image)
/workspace/         # Persistent development area
├── source/         # Git repository (CoralMachine)
├── build/          # Ninja build outputs  
├── .ccache/        # Compiler cache (10GB)
├── vtk/            # VTK simulation outputs
└── profiles/       # GPU profiling results
```

## Common Commands

### Docker Image Management
```bash
# Build the complete development image (done once)
docker build -t gstvbrg/coral-machine-dev:latest .

# Push to Docker Hub for RunPod access
docker push gstvbrg/coral-machine-dev:latest

# Test image locally
docker run --rm -it --gpus all gstvbrg/coral-machine-dev:latest
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

**Current Phase**: Documentation and planning
**Next Phase**: Dockerfile implementation following incremental strategy in IMPLEMENTATION_STEPS.md

Key files to create:
- `Dockerfile` - Main image definition with pre-compiled dependencies
- `scripts/startup.sh` - Container initialization (git pull + build)
- `config/` directory - zsh, tmux, and development configurations

## Development Environment Integration

### Cursor IDE Setup
- **Connection**: SSH remote development to container
- **Compiler**: nvc++ for GPU-aware IntelliSense
- **Build integration**: CMake + Ninja build system
- **Port forwarding**: 11111 for ParaView server connection

### Performance Targets
- **Pod deployment to coding**: <90 seconds
- **Incremental build**: <30 seconds  
- **SSH connection**: <20 seconds
- **Full rebuild**: <5 minutes (deps pre-compiled)

## Key Design Principles

1. **Pre-compilation over runtime builds**: All heavy dependencies built once into image
2. **Incremental development**: Only CoralMachine source compiles during development  
3. **State persistence**: Development work survives container restarts via volumes
4. **Remote visualization**: VTK files never leave container, viewed via ParaView server
5. **Cost optimization**: Start/stop RunPod instances without losing development state