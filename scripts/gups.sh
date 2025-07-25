#!/bin/bash
#PJM -L rscgrp=a-batch
#PJM -L node=1
#PJM -L elapse=00:03:00
#PJM -j
#PJM -S


module purge
module load gcc/8 ompi/4.1.6

# module load nvidia/24.11 hpcx/2.17.1

cd ../GUPs
oshrun -np 8  --map-by ppr:8:node ./gups.out