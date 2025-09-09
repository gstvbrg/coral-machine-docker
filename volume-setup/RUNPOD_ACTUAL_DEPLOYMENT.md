# RunPod Actual Deployment Guide - Network Volumes

## How RunPod Network Volumes Actually Work

### Key Concepts:
- **Network Volumes**: Persistent storage separate from pods
- **Pods**: Compute instances (GPU + container)
- **Templates**: Saved pod configurations

## Step 1: Create Network Volume (One-time)

### Via RunPod Web Console:
1. Go to **Storage** → **Network Volumes**
2. Click **+ New Network Volume**
3. Configure:
   - Name: `coral-machine-deps`
   - Size: 200 GB
   - Region: Same as your pods (e.g., US-EAST)
4. Click **Create**
5. Note the **Volume ID** (like `abc123xyz`)

### Via RunPod CLI:
```bash
runpodctl create volume \
  --name coral-machine-deps \
  --size 200 \
  --region US-EAST
```

## Step 2: Initial Volume Population

### 2.1 Create Setup Pod
```bash
runpodctl create pod \
  --name coral-setup \
  --imageName yourusername/coral-builder:latest \
  --gpuType "CPU" \
  --volumeId abc123xyz \
  --volumeMountPath /workspace \
  --containerDiskSize 10 \
  --command "/opt/volume-setup/setup.sh"
```

Or via Web Console:
1. **Pods** → **+ Deploy**
2. Select **CPU Pod** (no GPU needed for setup)
3. Configure:
   - Container Image: `yourusername/coral-builder:latest`
   - Container Start Command: `/opt/volume-setup/setup.sh`
4. **Attach Network Volume**:
   - Select: `coral-machine-deps`
   - Mount Path: `/workspace`
5. **Deploy**

### 2.2 Monitor Setup
- Watch logs in RunPod console
- Setup takes 30-45 minutes
- Look for "Setup complete" message

### 2.3 Stop Setup Pod
- **Important**: Stop pod but KEEP the volume
- Volume now contains all dependencies

## Step 3: Create Production Template

### Via Web Console:
1. **Templates** → **+ New Template**
2. Configure:

```yaml
Template Name: Coral Machine Dev
Container Configuration:
  Image: yourusername/coral-runtime:latest
  Start Command: /usr/local/bin/startup.sh
  Disk Size: 20 GB
  
Volume Configuration:
  Volume: coral-machine-deps (select from dropdown)
  Mount Path: /workspace
  
Ports:
  - 22 (SSH)
  - 11111 (ParaView)
  
Environment Variables:
  NVIDIA_VISIBLE_DEVICES: all
  NVIDIA_DRIVER_CAPABILITIES: compute,utility,graphics
  
Advanced:
  Enable SSH: Yes
  Run Type: On-Demand or Spot
```

## Step 4: Deploy Development Pod

### Option A: On-Demand Pod
```bash
runpodctl create pod \
  --templateId your-template-id \
  --gpuType "RTX 4090" \
  --networkVolumeId abc123xyz
```

### Option B: Spot Pod (cheaper)
```bash
runpodctl create pod \
  --templateId your-template-id \
  --gpuType "RTX 4090" \
  --spot \
  --bidPrice 0.50 \
  --networkVolumeId abc123xyz
```

### Via Web Console:
1. **Pods** → **+ Deploy**
2. Select your template: "Coral Machine Dev"
3. Choose GPU (RTX 4090, A100, etc.)
4. **Verify** Network Volume is attached
5. Deploy

## Step 5: Connect to Pod

### Get SSH Details:
```bash
runpodctl get pod your-pod-id
```

Returns something like:
```
SSH Command: ssh root@a1b2c3d4.proxy.runpod.net -p 12345 -i ~/.ssh/runpod
```

### Add to SSH Config:
```ssh-config
Host coral-runpod
    HostName a1b2c3d4.proxy.runpod.net
    Port 12345
    User root
    IdentityFile ~/.ssh/id_ed25519
```

## The Critical Difference: Volume Persistence

### What Persists (in Network Volume):
```
/workspace/                    ✅ Persists
├── deps/                     ✅ All dependencies
├── source/                   ✅ Your code
├── build/                    ✅ Build artifacts
└── vtk/                      ✅ Output files
```

### What's Lost (container filesystem):
```
/root/                        ❌ Lost on stop
/tmp/                         ❌ Lost on stop
/var/                         ❌ Lost on stop
```

## Complete Workflow Example

### First Time Setup (45 minutes):
```bash
# 1. Create network volume
runpodctl create volume --name coral-deps --size 200

# 2. Run setup pod (CPU is fine)
runpodctl create pod \
  --name setup \
  --imageName yourusername/coral-builder:latest \
  --volumeId VOLUME_ID \
  --volumeMountPath /workspace \
  --gpuType CPU \
  --command "/opt/volume-setup/setup.sh"

# 3. Wait for completion, then stop
runpodctl stop pod SETUP_POD_ID
```

### Daily Development (90 seconds):
```bash
# 1. Start dev pod with GPU
runpodctl create pod \
  --name dev \
  --imageName yourusername/coral-runtime:latest \
  --volumeId VOLUME_ID \
  --volumeMountPath /workspace \
  --gpuType "RTX 4090"

# 2. Get SSH details
runpodctl get pod DEV_POD_ID

# 3. Connect
ssh root@proxy.runpod.net -p PORT
```

## Alternative: RunPod Pods API

```python
import requests

# Your API key from RunPod settings
API_KEY = "your-api-key"
headers = {"Authorization": f"Bearer {API_KEY}"}

# Create network volume
volume_data = {
    "name": "coral-machine-deps",
    "size": 200,
    "region": "US-EAST"
}
response = requests.post(
    "https://api.runpod.io/v2/volumes",
    json=volume_data,
    headers=headers
)
volume_id = response.json()["id"]

# Create pod with volume
pod_data = {
    "name": "coral-dev",
    "imageName": "yourusername/coral-runtime:latest",
    "gpuType": "RTX 4090",
    "networkVolumeId": volume_id,
    "volumeMountPath": "/workspace",
    "ports": "22/tcp,11111/tcp",
    "env": {
        "NVIDIA_VISIBLE_DEVICES": "all"
    }
}
response = requests.post(
    "https://api.runpod.io/v2/pods",
    json=pod_data,
    headers=headers
)
```

## Cost Breakdown

### Network Volume Storage:
- 200 GB × $0.10/GB/month = $20/month
- Persists even when no pods running

### Pod Costs (only when running):
- Setup pod (CPU): ~$0.10/hour × 1 hour = $0.10 (one-time)
- Dev pod (RTX 4090): ~$0.74/hour (on-demand)
- Dev pod (RTX 4090): ~$0.40/hour (spot)

### Monthly Estimate:
- Storage: $20 (always)
- Compute: $0.74 × 8 hours × 20 days = $118 (on-demand)
- Or: $0.40 × 8 hours × 20 days = $64 (spot)

## Important Notes

1. **Network Volumes are Regional**: Must be in same region as pods
2. **Multiple Pods Can Share Volume**: But not simultaneously (unless read-only)
3. **Volume Backups**: Create snapshots for important data
4. **SSH Keys**: Add in RunPod account settings, not in container

## Troubleshooting

### Volume Not Mounting:
- Check volume and pod are in same region
- Verify mount path is `/workspace`
- Ensure volume ID is correct

### Setup Failed:
- Check builder image has setup scripts
- Verify volume has enough space
- Review pod logs for errors

### Can't Connect via SSH:
- Add SSH key in RunPod account settings
- Check pod status is "Running"
- Verify firewall allows SSH port