# 设置 CMake 最低版本要求
cmake_minimum_required(VERSION 3.18)

# 设置项目名称
project(osb)

# 添加子目录
add_subdirectory(GUPs_nvshmem)
add_subdirectory(GUPs_oshm_gpu_mem)
add_subdirectory(GUPs_cuda_aware_mpi)
add_subdirectory(GUPs_nvshmem_with_launcher)