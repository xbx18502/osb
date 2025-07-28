#!/bin/bash
#PJM -L rscgrp=a-batch
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
cd ../GUPs_nvshmem
mpirun -np 8  --map-by ppr:8:node ./gups.out