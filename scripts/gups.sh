#!/bin/bash
#PJM -L rscgrp=a-batch
#PJM -L node=1
#PJM -L elapse=00:03:00
#PJM -j
#PJM -S


module purge
module load gcc/8 ompi/4.1.6

# module load nvidia/24.11 hpcx/2.17.1
export OMPI_MCA_plm_rsh_agent="/usr/bin/pjrsh"

cd ../GUPs
oshrun -np 4  -hostfile ${PJM_O_NODEINF} \
--map-by ppr:4:node ./gups.out