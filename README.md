# Volume Setup - Modular Installation System

This directory contains a complete, self-contained setup system for the Coral Machine development environment. It includes modular installers, Docker integration, and convenient automation.

## Architecture

The setup is organized into independent, focused installer scripts that can be run individually or orchestrated together:

```
volume-setup/
├── config.env           # Central configuration (versions, paths, flags)
├── lib/
│   └── common.sh       # Shared utility functions
├── installers/
│   ├── 00-prep.sh      # Environment preparation, ccache setup
│   ├── 01-compilers.sh # NVIDIA HPC SDK installation
│   ├── 02-build-headers.sh # Development headers (Eigen3, GL, X11)
│   ├── 03-core-libraries.sh # Palabos CFD, geometry-central
│   └── 04-visualization.sh  # ParaView server, Polyscope
└── setup.sh            # Main orchestrator
```

## Key Improvements Over Monolithic Script

1. **Modularity**: Each component in its own script
2. **Configurability**: Central `config.env` for all settings
3. **Idempotency**: Can safely re-run scripts (checks for existing installs)
4. **Flat Directory Structure**: All outputs go to standard locations
5. **Better Error Handling**: Each script can fail independently
6. **Easier Testing**: Can run individual installers
7. **Clear Dependencies**: Numbered files show execution order

## Quick Start with Docker

The easiest way to use this setup is with Docker and Make:

```bash
# 1. Clone and enter directory
cd coral-machine-docker/volume-setup

# 1.5 Check prerequisites
./validate.sh

# 2. Copy environment template
cp .env.example .env
# Edit .env if needed (e.g., change USERNAME to match your user)

# 3. Run complete setup (30-45 minutes)
make setup

# 4. Start development environment
make dev

# 5. Connect via SSH
ssh coral-dev@localhost -p 2222
# 5.5
make ssh/c

# Or open shell directly
make shell
```

## Docker Architecture

The setup includes two Docker images:

1. **Builder Image** (`Dockerfile.builder`)
   - Contains all build tools and compilers
   - Used only during setup
   - Runs the modular installers
   - ~1GB image size

2. **Runtime Image** (`Dockerfile.runtime`)
   - Minimal runtime environment
   - Uses pre-built dependencies from volume
   - For daily development work
   - ~500MB image size

### Docker Services

The `docker-compose.yml` defines several services:

- **setup**: Runs full installation
- **installer**: Runs individual installers
- **dev**: Development environment
- **test**: Validates installation
- **clean**: Resets volumes

## Usage

### Using Make (Recommended)

```bash
# Initial setup
make setup          # Full installation (30-45 min)

# Daily development
make dev           # Start container
make shell         # Open shell in container
make ssh           # SSH into container

# Maintenance
make test          # Test installation
make status        # Show container/volume status
make rebuild       # Rebuild Docker images
make clean         # Remove all data (careful!)

# Individual installers
make install-compilers   # Just NVIDIA SDK
make install-libraries   # Just Palabos/geometry-central
```

### Using Docker Compose Directly

Run the main orchestrator to install everything:

```bash
cd volume-setup
sudo ./setup.sh
```

This will:
1. Prepare the build environment
2. Install NVIDIA HPC SDK compilers
3. Install development headers
4. Build core libraries (Palabos, geometry-central)
5. Install visualization tools (ParaView, Polyscope)
6. Set proper permissions for the dev user

### Individual Components

You can also run specific installers:

```bash
# Just install build headers
sudo ./installers/02-build-headers.sh

# Just build Palabos
sudo ./installers/03-core-libraries.sh
```

### Configuration

Edit `config.env` to:
- Change versions (NVIDIA SDK, ParaView, etc.)
- Enable/disable components
- Adjust build settings (jobs, ccache size)
- Modify installation paths

Example:
```bash
# Disable ParaView installation
export INSTALL_PARAVIEW=false

# Use different compiler
export DEFAULT_CXX_COMPILER="clang++"

# Increase ccache size
export CCACHE_SIZE="20G"
```

## Directory Structure

After installation, the volume will have this flat structure:

```
/workspace/deps/
├── bin/              # All executables (pvserver, etc.)
├── lib/              # All libraries (libpalabos.a, etc.)
├── include/          # All headers
│   ├── eigen3/
│   ├── palabos/
│   ├── geometrycentral/
│   ├── polyscope/
│   └── GL/
├── share/            # Shared data files
├── nvidia-hpc/       # NVIDIA SDK (special case, not flattened)
├── env.sh            # Environment setup script
└── .installed/       # Marker files for idempotency
```

## Environment Setup

The installation creates `/workspace/deps/env.sh` which sets up:
- Compiler paths (nvc++, nvcc, mpirun)
- Include paths for headers
- Library paths for linking
- CUDA configuration
- MPI settings

Source this file in your shell or container:
```bash
source /workspace/deps/env.sh
```

## Testing

After installation, run the test script:
```bash
/workspace/deps/test-installation.sh
```

This verifies:
- Compilers are accessible
- Libraries were built
- Headers are in place
- Basic compilation works

## Customization

### Adding a New Component

1. Create a new installer in `installers/` (e.g., `05-my-library.sh`)
2. Use the common functions from `lib/common.sh`
3. Check for existing installation with `is_installed`
4. Mark completion with `mark_installed`
5. Update environment in `/workspace/deps/env.sh` if needed

### Changing Installation Order

Rename the installer files - they run in numerical order:
- `00-` runs first (preparation)
- `01-` through `04-` run in sequence
- Higher numbers run later

## Troubleshooting

### Installation Fails

Check the specific installer that failed:
```bash
# Run with verbose output
bash -x ./installers/03-core-libraries.sh
```

### Missing Dependencies

The installers check for their dependencies. If something is missing:
```bash
# Check what's installed
ls /workspace/deps/.installed/
```

### Permission Issues

The main setup.sh fixes permissions at the end. If running individual installers:
```bash
# Fix permissions manually
chown -R 1000:1000 /workspace
```

## Design Principles

1. **Single Source of Truth**: `.env` is master config, `config.env` uses environment variables with fallbacks
2. **Fail Fast**: Scripts exit on first error
3. **Idempotent**: Can run multiple times safely
4. **Clear Output**: Consistent logging with emoji indicators
5. **Flat Structure**: Everything in standard bin/, lib/, include/ locations
6. **User-Friendly**: Clear messages and progress indicators

## Configuration Architecture

**Problem Solved**: Previously had conflicting configuration in two files (.env and config.env) leading to inconsistent build settings and variable naming conflicts.

**Solution Implemented**: Single Source of Truth pattern
- `.env` = Master configuration file (used by Docker Compose)
- `config.env` = Uses environment variables from .env with intelligent fallbacks
- **Clear precedence**: .env values override config.env defaults

**Benefits**:
- ✅ Zero configuration duplication or conflicts
- ✅ Single place to change settings (.env file)
- ✅ Docker Compose and bash scripts use identical values
- ✅ Environment variables can override any setting
- ✅ Maintains backward compatibility

**Example Flow**:
```bash
# .env (master)
BUILD_JOBS=8
CMAKE_BUILD_TYPE=Release

# Docker Compose passes to container
- BUILD_JOBS=${BUILD_JOBS:-8}

# config.env uses environment with fallbacks
export BUILD_JOBS=${BUILD_JOBS:-$(nproc)}
export CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE:-"Release"}
```

## Time Estimates

- Full setup: 30-45 minutes
- NVIDIA HPC SDK: 10-15 minutes
- Palabos build: 10-15 minutes
- Other components: 1-2 minutes each

## Requirements

- Ubuntu 22.04 base system
- ~30GB free space in volume
- Internet connection for downloads
- Build tools (cmake, ninja, git)