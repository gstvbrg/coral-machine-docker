# Single Volume Architecture Changes

## Summary of Critical Fix

We corrected a fundamental architecture mismatch between local development (two volumes) and RunPod deployment (single volume). This ensures our setup works correctly both locally and on RunPod.

## The Problem We Fixed

### Previous Architecture (INCORRECT)
```yaml
volumes:
  - coral-deps:/workspace/deps      # Volume 1 mounted at /workspace/deps
  - coral-workspace:/workspace       # Volume 2 mounted at /workspace (would hide deps!)
```

This created a **nested mount conflict** where the workspace mount would overlay and hide the deps subdirectory.

### New Architecture (CORRECT)
```yaml
volumes:
  - coral-workspace:/workspace       # Single volume containing everything
```

Now `deps/` is a subdirectory INSIDE the workspace volume, not a separate mount point.

## Files Modified

### 1. docker-compose.yml
- **Removed** all references to `coral-deps` volume
- **Updated** all services to use single `coral-workspace` volume
- **Deleted** the `coral-deps` volume definition

### 2. .env and .env.example
- **Removed** `DEPS_VOLUME_PATH=./volumes/deps` line
- **Updated** comments to clarify single volume structure

### 3. Makefile
- **Updated** `prep` target to create proper subdirectory structure:
  ```bash
  mkdir -p volumes/workspace/deps volumes/workspace/source volumes/workspace/build volumes/workspace/vtk
  ```

## What Didn't Change

### config.env
- Already correct: `DEPS_ROOT="/workspace/deps"`
- This path is a subdirectory, not a mount point

### Installer Scripts
- Already correct: All use `${DEPS_ROOT}` variable
- Will automatically write to `/workspace/deps/` subdirectory

### Dockerfiles
- Already correct: Create `/workspace` with subdirectories

## Final Volume Structure

```
/workspace/                  # Single mount point (RunPod network volume)
├── deps/                   # All dependencies (15GB)
│   ├── bin/               # Executables
│   ├── lib/               # Libraries
│   ├── include/           # Headers
│   ├── nvidia-hpc/        # NVIDIA HPC SDK
│   └── env.sh            # Environment setup
├── source/                 # Your code repository
├── build/                  # Build artifacts
├── vtk/                    # Visualization output
└── .ccache/               # Compiler cache
```

## RunPod Deployment Impact

This change ensures:
1. **Single network volume** in RunPod mounted at `/workspace`
2. **All data persists** in one place
3. **No mount conflicts** or hidden directories
4. **Consistent behavior** between local and cloud

## Testing Commands

To test the new single-volume setup locally:

```bash
# Clean old volumes (if they exist)
docker-compose down -v
rm -rf volumes/

# Create new structure and test
make prep          # Creates proper directory structure
make setup         # Runs full installation
make dev           # Start development environment
```

## Key Insight

The installers were always writing to the correct paths (`/workspace/deps/...`). The problem was the volume mounting strategy - we were trying to mount two volumes where RunPod only supports one. Now everything lives harmoniously in a single volume with proper subdirectory organization.