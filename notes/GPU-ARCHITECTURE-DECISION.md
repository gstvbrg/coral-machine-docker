# GPU Architecture Decision: MPI vs GPU Parallelism

## Executive Summary
**Decision**: Disable MPI in pre-built Palabos library, rely on GPU parallelism via `-stdpar` for single-machine development.

## The MPI C++ Bindings Problem

### Root Issue
1. Palabos uses **deprecated MPI C++ bindings** (removed in MPI-4.0)
2. NVIDIA HPC SDK's OpenMPI **lacks these C++ bindings**
3. Mixing compilers/MPI implementations causes **undefined reference errors**

### Failed Approaches
- ❌ Using NVIDIA's MPI with nvc++ (no C++ bindings)
- ❌ Using system MPI with nvc++ (compiler mixing issues)
- ❌ Patching CMakeLists.txt (brittle, incomplete)

## Architectural Analysis

### GPU Examples Pattern Discovery
The GPU examples (`cavity3d`, `sandstone`, etc.) handle this differently:
```cmake
# They rebuild Palabos from source every time
file(GLOB_RECURSE PALABOS_SRC "../../../src/*.cpp")
add_library(palabos STATIC ${PALABOS_SRC} ${EXT_SRC})
```
This ensures consistent compiler/MPI throughout, avoiding pre-built library issues.

### Two Valid Architectures

#### Architecture 1: **Pre-built Library WITHOUT MPI** ✅ (Chosen)
```bash
cmake .. \
    -DCMAKE_CXX_COMPILER=nvc++ \
    -DCMAKE_CXX_FLAGS="-stdpar -std=c++20 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC" \
    -DENABLE_MPI=OFF \
    -DPALABOS_ENABLE_MPI=OFF
```

**Benefits:**
- No MPI C++ binding issues
- Clean, simple builds
- GPU parallelism via `-stdpar` (replaces MPI for single-node)
- Fast incremental builds (<30 seconds)
- Perfect for RunPod single-GPU development

**Limitations:**
- No multi-node distribution
- Single machine only

#### Architecture 2: **Source-Include Pattern** (GPU Examples)
```cmake
# Application includes Palabos source directly
file(GLOB_RECURSE PALABOS_SRC "${PALABOS_PATH}/src/*.cpp")
add_library(palabos_static STATIC ${PALABOS_SRC})
```

**Benefits:**
- Can use ANY MPI implementation
- Consistent compiler throughout
- Supports multi-node if needed

**Limitations:**
- Longer build times (rebuilds Palabos each time)
- More complex CMake setup

## Implementation Changes

### 1. Modified `03-core-libraries.sh`
- Removed MPI configuration
- Added `-DENABLE_MPI=OFF`
- Updated compiler flags to match GPU examples
- Added explanatory comments

### 2. Updated Local `CMakeLists.txt`
- Added NVHPC compiler support
- Prepared for both MPI and non-MPI builds

### 3. Documentation Updates
- Created this architecture decision document
- Updated PALABOS-GITHUB-CHANGES.md
- Clear guidance for both approaches

## Developer Workflow Impact

### For Single-GPU Development (99% use case)
```bash
# Your application CMakeLists.txt
set(CMAKE_CXX_COMPILER nvc++)
set(CMAKE_CXX_FLAGS "-stdpar -std=c++20 -Msingle -Mfcon -fopenmp -DUSE_CUDA_MALLOC")

target_link_libraries(coral_machine 
    palabos      # Pre-built, no MPI
    tbb          # CPU parallelism
)
```

### For Multi-Node Development (1% use case)
Follow GPU examples pattern - include Palabos source directly, build with desired MPI.

## Performance Implications

### GPU Parallelism (`-stdpar`)
- **Vertical scaling**: Fully utilizes single GPU
- **Memory bandwidth**: Optimized for GPU memory
- **Kernel fusion**: Compiler optimizations for GPU
- **No network overhead**: All computation local

### MPI Parallelism
- **Horizontal scaling**: Across multiple nodes
- **Network overhead**: Communication between nodes
- **Useful when**: Problem exceeds single GPU memory

## Conclusion

For RunPod GPU development focused on single-machine performance:
- **GPU parallelism > MPI parallelism**
- **Avoiding MPI C++ binding issues > Supporting edge cases**
- **Simple, robust builds > Complex configurations**

The pre-built library without MPI provides the cleanest path to GPU-accelerated development while avoiding the entire class of MPI C++ binding issues that have plagued this project.