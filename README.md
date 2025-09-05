# Coral Machine Docker Development Environment

This repository builds a pre-compiled Docker development environment for coral machine simulation (PORAG) optimized for RunPod GPU workstations.

## Architecture Options

### 🚀 Volume-Based (Recommended)
**Location**: `volume-based/`  
**Startup Time**: <90 seconds after first setup  
**Image Size**: 5GB base + 175GB persistent volume  

Fast development workflow using persistent volumes for dependencies. Perfect for frequent start/stop patterns on RunPod.

### 📦 Legacy Monolithic  
**Location**: `legacy-monolithic/`  
**Startup Time**: 10-15 minutes  
**Image Size**: 25GB single image  

Original approach with everything pre-built in one image. Kept for reference but not recommended for daily use.

## Quick Start

```bash
cd volume-based/
# Follow README.md in that directory
```

## Repository Structure

```
├── volume-based/          # ⭐ CURRENT APPROACH
│   ├── docker/           # Dockerfiles  
│   ├── scripts/          # Setup and startup scripts
│   ├── docker-compose.yml
│   └── README.md         # Detailed usage guide
├── legacy-monolithic/    # Original 25GB approach
├── docs/                 # Shared documentation  
├── test-project/         # Testing resources
└── authorized_keys       # SSH keys
```
