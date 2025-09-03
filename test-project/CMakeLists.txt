cmake_minimum_required(VERSION 3.20)
project(CoralMachineTest LANGUAGES CXX CUDA)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)

# Find dependencies that should be pre-built in /opt/deps
find_library(PALABOS_LIB palabos PATHS /opt/deps/lib REQUIRED)
find_library(GEOMETRY_CENTRAL_LIB geometry-central PATHS /opt/deps/lib REQUIRED)

# Include directories for headers
include_directories(/opt/deps/palabos-hybrid/src)
include_directories(/opt/deps/include)

# Find system dependencies  
find_package(CUDAToolkit REQUIRED)

# Test executable to validate all dependencies work
add_executable(coral_test main.cpp)

target_link_libraries(coral_test
    ${PALABOS_LIB}
    ${GEOMETRY_CENTRAL_LIB}
    CUDA::cudart
)

# Only add -stdpar if using nvc++ compiler
if(CMAKE_CXX_COMPILER_ID STREQUAL "NVHPC")
    target_compile_options(coral_test PRIVATE -stdpar)
endif()

# Show found libraries for debugging
message(STATUS "Palabos library: ${PALABOS_LIB}")
message(STATUS "Geometry Central library: ${GEOMETRY_CENTRAL_LIB}")