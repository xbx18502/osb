cmake_minimum_required(VERSION 3.18)

set(CUDAToolkit_ROOT "/home/app/nvhpc/25.5/Linux_x86_64/25.5/cuda/12.9")
set(CMAKE_CUDA_COMPILER "/home/app/nvhpc/25.5/Linux_x86_64/25.5/cuda/12.9/bin/nvcc")

project(GUPs_nvshmem CUDA CXX)

set(CMAKE_CUDA_COMPILER_FORCED TRUE)

set(CMAKE_CUDA_ARCHITECTURES 70)
set(CMAKE_CUDA_COMPILER_FORCED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Set CUDA flags
# set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -rdc=true -ccbin g++")
# set(CMAKE_CUDA_LINK_FLAGS "${CMAKE_CUDA_LINK_FLAGS} -rdc=true")
# 仅让 nvcc 识别 -maxconstdata 选项
# set(CUDA_NVCC_FLAGS "${CUDA_NVCC_FLAGS};-maxconstdata=0x18000")

set(NVCC_GENCODE "arch=compute_70,code=sm_70")
set(NVSHMEM_HOME "/home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/12.9/nvshmem")
set(HYDRA_HOME "$NVSHMEM_HOME")
set(CUDA_HOME "/home/app/nvhpc/25.5/Linux_x86_64/25.5/cuda/12.9")
set(MPI_HOME "/home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/12.9/hpcx/hpcx-2.22.1/ompi")
set(NCCL_HOME "/home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/nccl")

# NVSHMEM 路径
set(NVSHMEM_HOME    /home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/12.9/nvshmem)
set(NVSHMEM_INC     ${NVSHMEM_HOME}/include)
set(NVSHMEM_LIB_DIR ${NVSHMEM_HOME}/lib)

# OpenSHMEM 路径
set(SHMEM_INC_DIR   /home/app/gcc/8/ompi/4.1.6/include)
set(SHMEM_LIB_DIR   /home/app/gcc/8/ompi/4.1.6/lib)

# 可执行 target
add_executable(GUPs_nvshmem
  SHMEMRandomAccess.cu
  RandomAccess.h
)

install(TARGETS GUPs_nvshmem
  RUNTIME DESTINATION ${CMAKE_SOURCE_DIR}/bin)

# Enable device code linking
set_target_properties(GUPs_nvshmem PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_RESOLVE_DEVICE_SYMBOLS ON
    OUTPUT_NAME "gups_nvshmem.out"
    # INSTALL_RPATH "/home/tmp/libosmcomp;${SHMEM_LIB_DIR};${NVSHMEM_LIB_DIR}"
    # BUILD_RPATH "/home/tmp/libosmcomp;${SHMEM_LIB_DIR};${NVSHMEM_LIB_DIR}"
)

# Set include directories
target_include_directories(GUPs_nvshmem PRIVATE
    ${NVSHMEM_INC}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${MPI_HOME}/include
)

# Set link directories
target_link_directories(GUPs_nvshmem PRIVATE
    ${NVSHMEM_LIB_DIR}
    ${MPI_HOME}/lib
)

# 链接库
target_link_libraries(GUPs_nvshmem PRIVATE
  mpi
  nvshmem
)
