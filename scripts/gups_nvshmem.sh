#!/bin/bash
#PJM -L rscgrp=b-batch
#PJM -L node=1
#PJM -L elapse=00:03:00
#PJM -j
#PJM -S


# module purge
# module load gcc/8 ompi/4.1.6

# module load nvidia/24.11 hpcx/2.17.1

# export OMPI_HOME=/home/app/hpcx/2.17.1/ompi
export OMPI_HOME=/home/app/gcc/8/ompi/4.1.6
export PATH=$OMPI_HOME/bin:$PATH
# export LD_LIBRARY_PATH=$OMPI_HOME/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=${OMPI_HOME}/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/home/tmp/libosmcomp:$LD_LIBRARY_PATH

# 禁用 OpenIB 相关警告和错误
export OMPI_MCA_btl_openib_warn_no_device_params_found=0
export OMPI_MCA_btl_openib_allow_ib=0
export OMPI_MCA_btl="^openib"

cd ../GUPs_nvshmem
mpirun -np 8 --map-by ppr:8:node \
  --mca btl_openib_warn_no_device_params_found 0 \
  --mca btl ^openib \
  --mca orte_base_help_aggregate 0 \
  ./gups.out