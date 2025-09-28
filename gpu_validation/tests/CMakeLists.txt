cmake_minimum_required(VERSION 3.20)
project(palabos_minimal LANGUAGES CXX)

# Respect environment-provided compiler and flags
if(NOT CMAKE_CXX_COMPILER)
  message(FATAL_ERROR "CMAKE_CXX_COMPILER must be preset (expected nvc++)")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_EXTENSIONS OFF)

# Pull flags from NVHPC env so builds match installed libraries
if(DEFINED ENV{NVHPC_CXX_FLAGS_FOR_CMAKE})
  set(CMAKE_CXX_FLAGS "$ENV{NVHPC_CXX_FLAGS_FOR_CMAKE}")
endif()

# Palabos headers live under /workspace/deps/include/palabos
set(PALABOS_INCLUDE "$ENV{PALABOS_INCLUDE}")
if(NOT PALABOS_INCLUDE)
  message(FATAL_ERROR "PALABOS_INCLUDE is not set; source /workspace/deps/env.sh first")
endif()

include_directories(${PALABOS_INCLUDE})
link_directories(/workspace/deps/lib)

add_executable(palabos_minimal ../palabos_minimal.cpp)

# Link against the installed Palabos static library
find_library(PALABOS_LIB palabos PATHS /workspace/deps/lib REQUIRED)
target_link_libraries(palabos_minimal PRIVATE ${PALABOS_LIB})
