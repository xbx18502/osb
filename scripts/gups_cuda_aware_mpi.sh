#!/bin/bash
#PJM -L rscgrp=b-batch
#PJM -L node=1
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

export NVSHMEM_BOOTSTRAP=MPI
# 禁用 OpenIB 相关警告和错误
export OMPI_MCA_btl_openib_warn_no_device_params_found=0
export OMPI_MCA_btl_openib_allow_ib=0
export OMPI_MCA_btl="^openib"
export OMPI_MCA_plm_rsh_agent="/usr/bin/pjrsh"

# ---------------------------------------------------
export OMPI_MCA_opal_cuda_support=true
export UCX_MEMTYPE_CACHE=n
export UCX_TLS=rc,sm,cuda_copy,cuda_ipc     # 安全的GPU传输
export UCX_RNDV_SCHEME=put_zcopy            # 使用put方式
export UCX_RNDV_THRESH=8192                 # 设置阈值
export HCOLL_ENABLE_GPU=1
# ---------------------------------------------------
cd ../bin
mpirun --display-allocation --display-map --map-by socket --bind-to socket \
  -hostfile ${PJM_O_NODEINF} \
  -np 4 --npernode 4 \
  -x PATH -x LD_LIBRARY_PATH -x CUDA_HOME -x NVSHMEM_HOME -x MPI_HOME -x NCCL_HOME \
  -x NVSHMEM_BOOTSTRAP -x OMPI_MCA_btl_openib_warn_no_device_params_found \
  -x OMPI_MCA_btl_openib_allow_ib -x OMPI_MCA_btl \
  --mca btl_openib_warn_no_device_params_found 0 \
  --mca btl ^openib \
  --mca orte_base_help_aggregate 0 \
  --mca plm_rsh_args "-o StrictHostKeyChecking=no" \
  ./gups_cuda_aware_mpi.out