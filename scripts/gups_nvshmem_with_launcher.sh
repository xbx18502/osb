#!/bin/bash
#PJM -L rscgrp=b-batch
#PJM -L node=2
#PJM -L elapse=00:08:00
#PJM -j
#PJM -S


# module purge
# module load gcc/8 ompi/4.1.6

# module load nvidia/25.5 hpcx/2.17.1

export MPI_HOME="/home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/12.9/hpcx/hpcx-2.22.1/ompi"
export NVSHMEM_HOME="/home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/12.9/nvshmem"
export CUDA_HOME="/home/app/nvhpc/25.5/Linux_x86_64/25.5/cuda/12.9"
export NCCL_HOME="/home/app/nvhpc/25.5/Linux_x86_64/25.5/comm_libs/nccl"
export PATH=$MPI_HOME/bin:$PATH
# export LD_LIBRARY_PATH=$OMPI_HOME/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$MPI_HOME/lib:$NVSHMEM_HOME/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$NCCL_HOME/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH=/home/tmp/libosmcomp:$LD_LIBRARY_PATH


export OMPI_MCA_plm_rsh_agent="/usr/bin/pjrsh"

cd ../bin
mpirun --display-allocation --display-map --map-by socket --bind-to socket \
  -hostfile ${PJM_O_NODEINF} \
  -np 8 --npernode 4 \
  ./gups_nvshmem_with_launcher.out