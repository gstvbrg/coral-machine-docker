# Local Testing Plan for Single Volume Architecture

## Overview
This plan ensures our single-volume architecture works correctly before deploying to RunPod. We'll test the complete lifecycle: setup, development, persistence, and recovery.

## Pre-Test Checklist
- [ ] Docker Desktop running
- [ ] At least 50GB free disk space
- [ ] Git repository up to date
- [ ] No running containers from previous attempts

## Phase 1: Clean Slate Setup

### Step 1.1: Complete Cleanup
```bash
cd volume-setup/

# Stop all containers
docker-compose down -v

# Remove old volumes (if they exist)
docker volume rm coral-deps coral-workspace 2>/dev/null || true

# Clean local directories
rm -rf volumes/

# Verify clean state
docker ps -a | grep coral
docker volume ls | grep coral
ls -la volumes/ 2>/dev/null || echo "No volumes directory"
```

**Expected Result:** No coral containers, no coral volumes, no volumes directory

### Step 1.2: Verify Configuration
```bash
# Check .env file has single volume config
grep "VOLUME_PATH" .env

# Should show only:
# WORKSPACE_VOLUME_PATH=./volumes/workspace
# Should NOT show DEPS_VOLUME_PATH
```

## Phase 2: Build and Initial Setup

### Step 2.1: Create Directory Structure
```bash
# Create single volume structure
make prep

# Verify structure
tree -L 3 volumes/
```

**Expected Output:**
```
volumes/
└── workspace/
    ├── build/
    ├── deps/
    ├── source/
    └── vtk/
```

### Step 2.2: Build Docker Images
```bash
# Build both images
make rebuild

# Or individually:
docker-compose build setup
docker-compose build dev

# Verify images exist
docker images | grep coral
```

**Expected:** Two images: `coral-builder` and `coral-runtime`

### Step 2.3: Run Setup Process
```bash
# Start setup (30-45 minutes)
time make setup

# Or run with progress monitoring:
docker-compose --profile setup run --rm setup 2>&1 | tee setup.log
```

**Monitor for:**
- Each installer completing successfully
- No "volume not found" errors
- Final "Setup complete" message

## Phase 3: Verification Tests

### Step 3.1: Verify Volume Contents
```bash
# Check volume structure
ls -la volumes/workspace/
ls -la volumes/workspace/deps/

# Check key installations
ls -la volumes/workspace/deps/nvidia-hpc/
ls -la volumes/workspace/deps/lib/libpalabos.a
ls -la volumes/workspace/deps/bin/pvserver

# Check environment script
cat volumes/workspace/deps/env.sh | head -20

# Check size
du -sh volumes/workspace/deps/
```

**Expected:**
- deps/ contains ~15GB of data
- All key files present
- env.sh has correct paths

### Step 3.2: Test Runtime Container
```bash
# Start development container
make dev

# In another terminal, verify mounts
docker exec coral-machine-docker-dev-1 df -h /workspace
docker exec coral-machine-docker-dev-1 ls -la /workspace/
docker exec coral-machine-docker-dev-1 ls -la /workspace/deps/
```

### Step 3.3: Test Development Environment
```bash
# Connect to container
make shell

# Inside container, test environment
echo $DEPS_ROOT                    # Should be /workspace/deps
which nvc++                         # Should find compiler
which cmake                         # Should find cmake
ls -la /workspace/deps/lib/        # Should see libraries

# Test compilation
cd /workspace/source
cat > test.cpp << 'EOF'
#include <iostream>
int main() {
    std::cout << "Single volume test successful!" << std::endl;
    return 0;
}
EOF

nvc++ test.cpp -o test
./test                              # Should print success message
```

## Phase 4: Persistence Testing

### Step 4.1: Create Test Data
```bash
# Inside container
cd /workspace
echo "Test data $(date)" > test-persistence.txt
cd /workspace/source
echo "// Test source file" > my-code.cpp
```

### Step 4.2: Restart Container
```bash
# Exit container
exit

# Stop container
docker-compose --profile dev down

# Start again
make dev
make shell

# Check persistence
cat /workspace/test-persistence.txt
cat /workspace/source/my-code.cpp
ls -la /workspace/deps/              # Should still have all deps
```

**Expected:** All files persist across container restarts

## Phase 5: RunPod Simulation

### Step 5.1: Simulate RunPod Mount
```bash
# Stop dev container
docker-compose --profile dev down

# Create a test that mimics RunPod's single mount
docker run --rm -it \
  -v $(pwd)/volumes/workspace:/workspace \
  coral-runtime:latest \
  bash -c "ls -la /workspace/ && ls -la /workspace/deps/"
```

### Step 5.2: Test Setup Recovery
```bash
# Simulate corrupted setup - remove marker file
rm volumes/workspace/deps/.setup-complete

# Run setup again - should detect existing installation
make setup

# Should ask to continue or skip existing components
```

## Phase 6: Stress Tests

### Step 6.1: Multi-Container Access
```bash
# Start dev container
make dev

# In parallel, run test container
docker-compose --profile test run --rm test

# Both should work without conflicts
```

### Step 6.2: Large File Operations
```bash
# Inside container
cd /workspace/build
dd if=/dev/zero of=testfile bs=1M count=1000  # Create 1GB file
rm testfile

# Verify no issues with volume
```

## Phase 7: Final Validation Checklist

Run through this checklist before declaring success:

- [ ] Single volume at `volumes/workspace/` contains everything
- [ ] No references to `coral-deps` volume anywhere
- [ ] Dependencies in `/workspace/deps/` (~15GB)
- [ ] Development container can compile code
- [ ] SSH access works: `ssh -p 2222 gstvbrg@localhost`
- [ ] ParaView server accessible on port 11111
- [ ] Files persist across container restarts
- [ ] Environment variables correctly set
- [ ] `nvc++` compiler accessible
- [ ] CMake can find dependencies

## Troubleshooting Guide

### Issue: "deps directory is empty"
```bash
# Check if volume is properly mounted
docker inspect coral-machine-docker-dev-1 | grep -A5 Mounts

# Should show /workspace mounted to volumes/workspace
```

### Issue: "Compiler not found"
```bash
# Inside container
source /workspace/deps/env.sh
echo $PATH | tr ':' '\n' | grep deps
```

### Issue: "Permission denied"
```bash
# Check ownership
ls -la volumes/workspace/

# Fix if needed (from host)
sudo chown -R $(id -u):$(id -g) volumes/workspace/
```

### Issue: "Volume not mounting"
```bash
# Verify Docker Compose is using correct path
docker-compose config | grep -A5 volumes

# Should show single coral-workspace volume
```

## Success Criteria

The test is successful when:
1. ✅ Setup completes without errors
2. ✅ All dependencies are in `/workspace/deps/`
3. ✅ Development container can compile code
4. ✅ Data persists across restarts
5. ✅ No references to dual-volume structure
6. ✅ Single `volumes/workspace/` directory contains everything

## Next Steps After Success

Once all tests pass:
1. Document any issues found and resolutions
2. Tag the git commit as "single-volume-tested"
3. Build and push images to Docker Hub
4. Proceed with RunPod deployment

## Test Commands Summary

```bash
# Quick test sequence
make clean          # Warning: deletes everything
make prep           # Create structure
make rebuild        # Build images
make setup          # Run installation (30-45 min)
make dev            # Start dev container
make shell          # Connect to container
# Inside container:
cd /workspace/source
echo 'int main(){}' > test.cpp
nvc++ test.cpp      # Test compilation
exit
# Back on host:
docker-compose down
ls -la volumes/workspace/deps/  # Verify persistence
```

## Report Template

After testing, fill out:

```markdown
## Test Report - [DATE]

### Environment
- Docker version: 
- OS: Windows 11
- Available disk: 
- Available RAM: 

### Test Results
- [ ] Phase 1: Cleanup - PASS/FAIL
- [ ] Phase 2: Build - PASS/FAIL  
- [ ] Phase 3: Verification - PASS/FAIL
- [ ] Phase 4: Persistence - PASS/FAIL
- [ ] Phase 5: RunPod Simulation - PASS/FAIL
- [ ] Phase 6: Stress Tests - PASS/FAIL
- [ ] Phase 7: Final Validation - PASS/FAIL

### Issues Found
1. 
2. 

### Resolution
1. 
2. 

### Conclusion
Ready for RunPod deployment: YES/NO
```