# RunPod Deployment Guide for Coral Machine Development Environment

## Overview
This guide explains how to deploy our volume-based architecture to RunPod GPU Cloud.

## Architecture Translation
- **Local**: Docker Compose with multiple services
- **RunPod**: Single container with persistent storage

## Prerequisites
1. RunPod account with credits
2. Docker Hub account (free tier is fine)
3. SSH key pair for development access

## Step 1: Build and Push Docker Images

### 1.1 Build Images Locally
```bash
cd volume-setup/

# Build both images
docker build -f docker/Dockerfile.builder -t coral-builder:latest .
docker build -f docker/Dockerfile.runtime \
  --build-arg USERNAME=runpod \
  -t coral-runtime:latest .
```

### 1.2 Tag for Docker Hub
```bash
# Replace 'yourusername' with your Docker Hub username
docker tag coral-builder:latest yourusername/coral-builder:latest
docker tag coral-runtime:latest yourusername/coral-runtime:latest
```

### 1.3 Push to Docker Hub
```bash
docker login
docker push yourusername/coral-builder:latest
docker push yourusername/coral-runtime:latest
```

## Step 2: Initial RunPod Setup (One-time)

### 2.1 Create RunPod Template
1. Go to RunPod Console → Templates → New Template
2. Configure:
   ```
   Template Name: Coral Machine Dev
   Container Image: yourusername/coral-runtime:latest
   Container Disk: 20 GB (for container and temp files)
   Volume Disk: 200 GB (for /workspace persistence)
   Volume Mount Path: /workspace
   Expose HTTP Ports: 22,11111 (SSH and ParaView)
   Docker Command: /usr/local/bin/startup.sh
   Environment Variables:
     NVIDIA_VISIBLE_DEVICES: all
     NVIDIA_DRIVER_CAPABILITIES: compute,utility,graphics
   ```

### 2.2 First-Time Volume Population
Since RunPod starts with empty volumes, we need to run setup ONCE:

1. **Create a temporary pod** with the builder image:
   ```
   Container Image: yourusername/coral-builder:latest
   Volume Mount Path: /workspace
   Container Command: /opt/volume-setup/setup.sh
   GPU Type: Any (setup doesn't need GPU)
   ```

2. **Wait 30-45 minutes** for setup to complete
   - Monitor logs in RunPod console
   - Setup will install NVIDIA HPC SDK, Palabos, ParaView, etc.

3. **Stop the builder pod** (but keep the volume!)

## Step 3: Production Deployment

### 3.1 Start Development Pod
1. Use your saved template "Coral Machine Dev"
2. **IMPORTANT**: Attach the same volume from Step 2.2
3. Select GPU type (RTX 4090, A100, etc.)
4. Start pod

### 3.2 SSH Configuration
RunPod provides SSH access via proxy:

1. Get connection details from RunPod console:
   ```
   ssh root@[PROXY_URL] -p [PROXY_PORT]
   ```

2. Add to your local SSH config:
   ```
   Host coral-runpod
       HostName [PROXY_URL]
       Port [PROXY_PORT]
       User runpod
       IdentityFile ~/.ssh/id_ed25519
   ```

### 3.3 Connect from Cursor/VS Code
1. Install "Remote - SSH" extension
2. Connect to `coral-runpod`
3. Open `/workspace/source` folder

## Step 4: Volume Management Strategy

### Volume Structure on RunPod
```
/workspace/                    # Persistent volume (200GB)
├── deps/                      # Pre-compiled dependencies (15GB)
│   ├── nvidia-hpc/           # NVIDIA HPC SDK
│   ├── lib/                  # Libraries (Palabos, etc.)
│   ├── include/              # Headers
│   └── bin/                  # Executables (pvserver, etc.)
├── source/                    # Your code goes here
├── build/                     # Build artifacts
└── vtk/                      # Visualization output
```

### Key Points:
- **/workspace is persistent** - survives pod stops
- **Container filesystem is ephemeral** - lost on pod stop
- **Never store important data outside /workspace**

## Step 5: Daily Workflow

### Starting Work
1. Start pod from RunPod console (or API)
2. Wait ~60 seconds for container startup
3. SSH in: `ssh coral-runpod`
4. Environment auto-loads from `/workspace/deps/env.sh`

### Stopping Work
1. Save all work (git commit/push)
2. Stop pod from RunPod console
3. Volume persists, only pay for storage ($0.10/GB/month)

## Step 6: Cost Optimization

### Storage Costs
- Volume: 200GB × $0.10 = $20/month (persistent)
- Container: 20GB × $0.10 = $2/month (when stopped)

### Compute Costs (only when running)
- RTX 4090: ~$0.74/hour
- RTX A5000: ~$0.54/hour  
- RTX 3090: ~$0.44/hour

### Tips:
1. **Stop pods when not in use** - only pay for storage
2. **Use spot instances** - 50-70% cheaper
3. **Choose appropriate GPU** - RTX 3090 often sufficient

## Alternative: RunPod Persistent Pods

RunPod now offers "Persistent Pods" which might simplify this:
1. Volumes automatically persist
2. Can stop/start without losing data
3. Same cost model as above

## Troubleshooting

### Volume Not Initialized
If `/workspace/deps` is empty:
1. Run the builder container again
2. Check logs for setup.sh errors
3. Ensure volume is properly mounted

### SSH Connection Issues
RunPod handles SSH keys differently:
1. Add your public key in RunPod account settings
2. RunPod injects it automatically
3. No need for authorized_keys file

### GPU Not Available
Ensure:
1. Pod has GPU attached
2. Using runtime image, not builder
3. NVIDIA environment variables are set

## Migration from Local Development

### Key Differences:
| Local Docker Compose | RunPod |
|---------------------|---------|
| Multiple services | Single container |
| docker-compose.yml | RunPod Template |
| Local volumes | RunPod Network Storage |
| localhost:2222 | RunPod SSH proxy |
| authorized_keys file | RunPod SSH key management |

### What Changes:
- SSH connection endpoint
- No docker-compose commands
- Use RunPod console/API for container management

### What Stays Same:
- Development workflow inside container
- All tools and compilers
- Volume structure at /workspace
- ParaView server setup

## Advanced: Automation with RunPod API

```python
import runpod

# Start pod programmatically
runpod.start_pod(
    template_id="your-template-id",
    gpu_type="RTX 4090",
    volume_id="your-volume-id"
)
```

## Summary

1. **One-time setup**: Run builder container to populate volume (45 min)
2. **Daily use**: Start/stop runtime container with persistent volume
3. **Cost**: ~$22/month storage + hourly GPU when running
4. **Performance**: <90 second startup with pre-built dependencies