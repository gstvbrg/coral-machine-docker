# Legacy Monolithic Approach

This directory contains the original 25GB "everything in one image" approach.

## Files

- `Dockerfile` - Original monolithic build (~25GB)
- `startup.sh` - Original startup script

## Issues

- 25GB image size causes 10-15 minute startup times on RunPod
- Too large for reliable Docker Hub distribution
- Poor fit for frequent start/stop development workflow

## Status

**⚠️ DEPRECATED** - Use the `volume-based/` approach instead for production work.

This is kept for reference and fallback purposes only.