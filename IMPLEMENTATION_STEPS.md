# Coral Machine Docker Implementation Strategy
**Updated**: January 2025  
**Strategy**: Incremental 5-Phase Build for Rapid Development Deployment

## Overview: Test Early, Fail Fast, Build on Success

This implementation follows an **incremental validation strategy** where each phase builds and tests independently. This ensures you can identify and fix issues quickly while maintaining a working baseline at each step.

**Core Philosophy**: Get to a working development environment ASAP, then enhance incrementally.

---

## **Phase 1: Infrastructure Validation** ⏱️ *10 minutes*
**Goal**: Verify current base image works and all infrastructure is functional

### Current State Assessment
Your current image already includes:
- ✅ NVIDIA HPC SDK with nvc++ compiler
- ✅ OpenMPI for parallel processing  
- ✅ SSH server with proper security
- ✅ ParaView server (required dependency)
- ✅ Enhanced startup.sh with MPI/security features

### Phase 1 Commands
```bash
# Build current image 
docker build -t coral-dev-phase1 .

# Test container startup
docker run --rm -it --gpus all coral-dev-phase1

# Test inside container:
# 1. SSH connectivity
# 2. ParaView server startup on port 11111
# 3. nvc++ compiler availability
# 4. MPI commands (mpirun --version)
```

### Success Criteria
- ✅ Container builds successfully (~5 min)
- ✅ SSH server accepts connections
- ✅ ParaView server starts with enhanced configuration 
- ✅ MPI environment ready for parallel processing
- ✅ GPU access confirmed (nvidia-smi works)

**🚨 CRITICAL**: If Phase 1 fails, fix infrastructure before proceeding.

---

## **Phase 2: Add geometry-central** ⏱️ *25 minutes* 
**Goal**: Add first C++ dependency to validate build toolchain

### Rationale
- **Smallest dependency** (quickest to build)
- **Tests C++ compilation** with nvc++
- **Validates CMake** dependency discovery
- **Establishes /opt/deps** structure

### Dockerfile Changes
Add after line 47 (after ParaView installation):

```dockerfile
# Phase 2: geometry-central (mesh processing library)
# Small dependency to validate C++ build toolchain
WORKDIR /tmp/build

RUN echo "🔧 Building geometry-central..." && \
    git clone --recursive --depth 1 \
    https://github.com/nmwsharp/geometry-central.git && \
    cd geometry-central && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=nvc++ && \
    make -j$(nproc) install && \
    echo "✅ geometry-central installed successfully" && \
    cd / && rm -rf /tmp/build/geometry-central

WORKDIR /workspace
```

### Phase 2 Testing
```bash
# Build Phase 2
docker build -t coral-dev-phase2 .

# Verify installation
docker run --rm coral-dev-phase2 bash -c \
  "ls -la /opt/deps/lib/ && ls -la /opt/deps/include/ && \
   find /opt/deps -name '*geometry*' -type f"

# Test CMake discovery
echo 'find_package(PkgConfig)
find_path(GC_INC geometrycentral PATHS /opt/deps/include)
message(STATUS "Found: ${GC_INC}")' > test_gc.cmake

docker run --rm -v $(pwd):/test coral-dev-phase2 \
  bash -c "cd /test && cmake -P test_gc.cmake"
```

### Success Criteria
- ✅ Build completes in ~20 minutes
- ✅ Headers installed: `/opt/deps/include/geometrycentral/`
- ✅ Libraries installed: `/opt/deps/lib/libgeometry-central*`
- ✅ CMake can discover the dependency

---

## **Phase 3: Add Palabos-hybrid** ⏱️ *60 minutes*
**Goal**: Add core simulation engine (most critical for PORAG)

### Rationale  
- **Core simulation capability** (this is the heart of PORAG)
- **Tests MPI + CUDA integration** 
- **Largest/most complex dependency**
- **Success = you can run simulations**

### Dockerfile Changes
Add after Phase 2:

```dockerfile
# Phase 3: Palabos-hybrid (core simulation engine)
# This is the critical dependency for coral morphogenesis simulation
RUN echo "🧮 Building Palabos-hybrid (this will take ~45 minutes)..." && \
    mkdir -p /tmp/build && cd /tmp/build && \
    git clone --depth 1 \
    https://gitlab.com/unigespc/palabos.git palabos-hybrid && \
    cd palabos-hybrid && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=nvc++ \
             -DPALABOS_ENABLE_MPI=ON \
             -DPALABOS_ENABLE_CUDA=ON \
             -DCUDA_ARCH="sm_75;sm_80;sm_86;sm_89" && \
    make -j$(nproc) install && \
    echo "✅ Palabos-hybrid with GPU support installed" && \
    cd / && rm -rf /tmp/build/palabos-hybrid
```

### Phase 3 Testing
```bash
# Build Phase 3 (expect 45-60 minutes)
docker build -t coral-dev-phase3 .

# Test MPI + GPU + Palabos integration
docker run --rm --gpus all coral-dev-phase3 bash -c \
  "ls /opt/deps/lib/libpalabos* && \
   mpirun -np 2 --allow-run-as-root echo 'MPI working' && \
   nvidia-smi && \
   echo 'Phase 3 SUCCESS: Simulation engine ready'"
```

### Success Criteria
- ✅ Palabos builds with CUDA support
- ✅ MPI integration functional  
- ✅ GPU compilation successful
- ✅ Libraries available for CoralMachine linking

### 🚨 Phase 3 Recovery Strategies
If Phase 3 fails:

**Option A**: Build without CUDA first
```dockerfile
-DPALABOS_ENABLE_CUDA=OFF \
```

**Option B**: Try different compiler
```dockerfile
-DCMAKE_CXX_COMPILER=g++ \
```

**Option C**: Check specific error and adjust flags

---

## **Phase 4: Add Polyscope** ⏱️ *30 minutes*  
**Goal**: Optional additional visualization (can skip if needed)

### Rationale
- **Optional enhancement** (ParaView provides core visualization)
- **Additional debugging/development tools**
- **Can be skipped if Phase 3 works**

### Dockerfile Changes
Add after Phase 3:

```dockerfile
# Phase 4: Polyscope (additional visualization - optional)  
# Can be skipped if you only need ParaView for visualization
RUN echo "🎨 Building Polyscope (optional visualization)..." && \
    mkdir -p /tmp/build && cd /tmp/build && \
    git clone --recursive --depth 1 \
    https://github.com/nmwsharp/polyscope.git && \
    cd polyscope && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DPOLYSCOPE_BACKEND=OPENGL3_GLFW \
             -DPOLYSCOPE_ENABLE_RENDER_BACKEND_OPENGL3=ON && \
    make -j$(nproc) install && \
    echo "✅ Polyscope visualization library installed" && \
    cd / && rm -rf /tmp/build/polyscope || \
    echo "⚠️  Polyscope build failed - continuing without it"
```

### Phase 4 Testing
```bash
# Build Phase 4
docker build -t coral-dev-phase4 .

# Test Polyscope availability
docker run --rm coral-dev-phase4 bash -c \
  "find /opt/deps -name '*polyscope*' -type f"
```

### Success Criteria
- ✅ Polyscope builds successfully OR fails gracefully
- ✅ OpenGL integration works in headless environment
- ✅ Core system still functional if Polyscope fails

**Note**: If this phase fails, you can skip it entirely. ParaView provides all necessary visualization.

---

## **Phase 5: Integration Testing** ⏱️ *15 minutes*
**Goal**: Verify complete system works end-to-end with CoralMachine

### Create Integration Test
Create `test-integration.cmake`:

```cmake
cmake_minimum_required(VERSION 3.20)
project(CoralMachineIntegrationTest CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_PREFIX_PATH /opt/deps)

# Test all critical dependencies
message(STATUS "🧪 Testing dependency discovery...")

# Test geometry-central
find_path(GEOMETRY_CENTRAL_INC geometrycentral PATHS /opt/deps/include)
find_library(GEOMETRY_CENTRAL_LIB geometry-central PATHS /opt/deps/lib)

if(GEOMETRY_CENTRAL_INC AND GEOMETRY_CENTRAL_LIB)
    message(STATUS "✅ geometry-central: ${GEOMETRY_CENTRAL_LIB}")
else()
    message(FATAL_ERROR "❌ geometry-central not found")
endif()

# Test Palabos
find_path(PALABOS_INC palabos PATHS /opt/deps/include)
find_library(PALABOS_LIB palabos PATHS /opt/deps/lib)

if(PALABOS_INC AND PALABOS_LIB)
    message(STATUS "✅ Palabos-hybrid: ${PALABOS_LIB}")
else()
    message(FATAL_ERROR "❌ Palabos-hybrid not found")
endif()

# Test Polyscope (optional)
find_path(POLYSCOPE_INC polyscope PATHS /opt/deps/include)
find_library(POLYSCOPE_LIB polyscope PATHS /opt/deps/lib)

if(POLYSCOPE_INC AND POLYSCOPE_LIB)
    message(STATUS "✅ Polyscope: ${POLYSCOPE_LIB}")
else()
    message(STATUS "⚠️  Polyscope not found (optional)")
endif()

message(STATUS "🎉 Integration test completed successfully!")
```

### Phase 5 Testing
```bash
# Final integration test
docker build -t coral-dev-final .

# Test dependency discovery
docker run --rm -v $(pwd):/test coral-dev-final \
  bash -c "cd /test && cmake -P test-integration.cmake"

# Test CoralMachine source integration
docker run --rm --gpus all \
  -e REPO_URL=https://github.com/yourusername/coralMachine.git \
  coral-dev-final bash -c \
  "cd /workspace/source && \
   cmake -B build -G Ninja \
     -DCMAKE_PREFIX_PATH=/opt/deps \
     -DCMAKE_BUILD_TYPE=RelWithDebInfo && \
   echo '✅ CoralMachine CMake configuration successful'"
```

### Success Criteria
- ✅ All dependencies discoverable by CMake
- ✅ CoralMachine source configures successfully
- ✅ Build system ready for development
- ✅ GPU + MPI + visualization stack functional

---

## **Recovery Strategies & Risk Mitigation**

### General Debugging Approach
```bash
# Drop into container for interactive debugging
docker run --rm -it --gpus all coral-dev-phaseX bash

# Check specific dependency
ls -la /opt/deps/lib/ | grep dependency-name
find /opt/deps -name "*dependency*" -type f

# Test compiler directly
nvc++ --version
mpirun --version
nvidia-smi
```

### Phase-Specific Recovery

| Phase | If Build Fails | Alternative Strategy |
|-------|----------------|----------------------|
| Phase 1 | Fix infrastructure | Critical - must work before proceeding |
| Phase 2 | Try g++ instead of nvc++ | Switch compiler temporarily |
| Phase 3 | Disable CUDA first | `-DPALABOS_ENABLE_CUDA=OFF` |
| Phase 4 | Skip entirely | ParaView provides visualization |
| Phase 5 | Fix specific CMake issues | Adjust paths and flags |

### Build Time Optimization
- **Use Docker layer caching**: Each phase creates a layer
- **Parallel builds**: `make -j$(nproc)` already included
- **Clean artifacts**: `rm -rf /tmp/build` after each phase

---

## **Timeline to Working System**

| Phase | Duration | Cumulative | Capability Achieved |
|-------|----------|------------|-------------------|
| Phase 1 | 10 min | 10 min | Basic container + SSH + ParaView |
| Phase 2 | 25 min | 35 min | C++ build toolchain validated |
| Phase 3 | 60 min | 95 min | **CORE SIMULATION READY** |
| Phase 4 | 30 min | 125 min | Full visualization stack |
| Phase 5 | 15 min | 140 min | Complete integration |

**Critical Milestone**: After Phase 3 (~95 minutes), you have a working coral simulation environment.

**Total Time**: ~2.5 hours to complete system  
**Minimum Viable**: ~1.5 hours to core functionality

---

## **Success Metrics**

### Phase Completion Checklist
- [ ] **Phase 1**: Infrastructure validated, ParaView + SSH working
- [ ] **Phase 2**: First dependency builds, CMake toolchain working  
- [ ] **Phase 3**: Palabos + GPU + MPI functional ← **CRITICAL MILESTONE**
- [ ] **Phase 4**: Optional visualization enhancements  
- [ ] **Phase 5**: End-to-end CoralMachine integration

### Final Validation Commands
```bash
# Test complete workflow
docker run --rm --gpus all \
  -e MPI_PROCESSES=2 \
  -e PV_CONNECT_ID=1234 \
  -p 2222:22 -p 11111:11111 \
  coral-dev-final

# Should see:
# ✅ SSH server on port 22
# ✅ ParaView server with MPI on port 11111  
# ✅ CoralMachine ready for development
# ✅ GPU acceleration available
```

This strategy gets you to a working remote GPU development environment with minimal risk and maximum learning at each step.