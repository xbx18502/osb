#!/bin/bash
#PJM -L rscgrp=b-batch
#PJM -L node=1
#PJM -L elapse=00:03:00
#PJM -j
#PJM -S


# module purge
# module load gcc/8 ompi/4.1.6

# module load nvidia/24.11 hpcx/2.17.1

export MPI_HOME="/home/app/nvhpc/24.11/Linux_x86_64/24.11/comm_libs/12.6/hpcx/hpcx-2.20/ompi"
export NVSHMEM_HOME="/home/app/nvhpc/24.11/Linux_x86_64/24.11/comm_libs/12.6/nvshmem"
export CUDA_HOME="/home/app/nvhpc/24.11/Linux_x86_64/24.11/cuda/12.6"
export NCCL_HOME="/home/app/nvhpc/24.11/Linux_x86_64/24.11/comm_libs/nccl"
export PATH=$MPI_HOME/bin:$PATH
# export LD_LIBRARY_PATH=$OMPI_HOME/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$MPI_HOME/lib:$NVSHMEM_HOME/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$NCCL_HOME/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH=/home/tmp/libosmcomp:$LD_LIBRARY_PATH

export NVSHMEM_BOOTSTRAP=MPI
# 禁用 OpenIB 相关警告和错误
export OMPI_MCA_btl_openib_warn_no_device_params_found=0
export OMPI_MCA_btl_openib_allow_ib=0
export OMPI_MCA_btl="^openib"

cd ../GUPs_nvshmem
mpirun -np 4 --map-by ppr:4:node \
  --mca btl_openib_warn_no_device_params_found 0 \
  --mca btl ^openib \
  --mca orte_base_help_aggregate 0 \
  ./gups.out