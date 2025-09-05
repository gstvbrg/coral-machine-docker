# Volume-Based Coral Machine Development Environment

This approach uses persistent volumes to achieve <90 second container startup times on RunPod.

## Architecture

- **5GB base image**: Minimal NVHPC + SSH + essential tools
- **25GB deps volume**: Pre-compiled ParaView, Palabos, geometry-central  
- **150GB workspace volume**: Source code, builds, ccache, VTK outputs

## Quick Start (Local Testing)

```bash
# 1. Build the images
docker build -f Dockerfile.base -t coral-dev:base .
docker build -f Dockerfile.setup -t coral-dev:setup .

# 2. Initialize the volume (one-time, ~30 minutes)
docker run -v coral-deps:/workspace/deps coral-dev:setup

# 3. Run the development container
docker run -d \
  -v coral-deps:/workspace/deps:ro \
  -v coral-workspace:/workspace \
  --gpus all \
  -p 2222:22 -p 11111:11111 \
  coral-dev:base
```

## RunPod Deployment

### Step 1: Push base image to Docker Hub
```bash
docker tag coral-dev:base gstvbrg/coral-dev:volume-based
docker push gstvbrg/coral-dev:volume-based
```

### Step 2: Create RunPod Template
- **Image**: `gstvbrg/coral-dev:volume-based`
- **Persistent Volume**: 175GB mounted to `/workspace`
- **Ports**: 22 (SSH), 11111 (ParaView)

### Step 3: First-time Volume Setup
SSH into RunPod instance and run:
```bash
docker run -v /workspace:/workspace coral-dev:setup
```

### Step 4: Daily Usage
Container starts in <90 seconds with all dependencies pre-built!

## Performance Characteristics

| Scenario | Time | Description |
|----------|------|-------------|
| First setup | 30-45 min | One-time volume initialization |
| Cold start (new server) | 2-3 min | Base image pull + volume mount |
| Warm start (cached) | 30-60 sec | Volume mount only |
| Subsequent restarts | <30 sec | Everything cached |

## Volume Contents

```
/workspace/deps/
├── paraview/          # ParaView 6.0 (headless optimized)
├── palabos-hybrid/    # Pre-compiled Palabos library
├── geometry-central/  # Mesh processing library
├── include/           # Headers for all libraries
└── .initialized       # Setup completion marker

/workspace/
├── source/           # Your coral machine code
├── build/            # CMake/Ninja build directory
├── .ccache/          # Compiler cache (10GB)
└── vtk/              # Simulation outputs
```

## Cost Analysis

- **Docker Hub storage**: Free (5GB image)
- **RunPod volume**: 175GB × $0.15/GB = $26.25/month
- **Time savings**: 10+ minutes per restart × multiple daily restarts

## Advantages

✅ Sub-90 second startup after first daily pull
✅ Minimal network dependency  
✅ Pre-compiled dependencies never re-download
✅ Perfect for frequent stop/start workflow
✅ Shared base image likely cached on RunPod servers

## Troubleshooting

If volume not initialized:
```bash
docker exec -it <container> bash
/setup-volume.sh
```

Check volume contents:
```bash
ls -la /workspace/deps/
du -sh /workspace/deps/*
```

Verify ParaView:
```bash
/workspace/deps/paraview/bin/pvserver --version
```