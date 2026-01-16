/* -*- mode: C; tab-width: 2; indent-tabs-mode: nil; -*- */

/*
 * This code has been contributed by the DARPA HPCS program.  Contact
 * David Koester <dkoester@mitre.org> or Bob Lucas <rflucas@isi.edu>
 * if you have questions.
 *
 *
 * GUPS (Giga UPdates per Second) is a measurement that profiles the memory
 * architecture of a system and is a measure of performance similar to MFLOPS.
 * The HPCS HPCchallenge RandomAccess benchmark is intended to exercise the
 * GUPS capability of a system, much like the LINPACK benchmark is intended to
 * exercise the MFLOPS capability of a computer.  In each case, we would
 * expect these benchmarks to achieve close to the "peak" capability of the
 * memory system. The extent of the similarities between RandomAccess and
 * LINPACK are limited to both benchmarks attempting to calculate a peak system
 * capability.
 *
 * GUPS is calculated by identifying the number of memory locations that can be
 * randomly updated in one second, divided by 1 billion (1e9). The term "randomly"
 * means that there is little relationship between one address to be updated and
 * the next, except that they occur in the space of one half the total system
 * memory.  An update is a read-modify-write operation on a table of 64-bit words.
 * An address is generated, the value at that address read from memory, modified
 * by an integer operation (add, and, or, xor) with a literal value, and that
 * new value is written back to memory.
 *
 * We are interested in knowing the GUPS performance of both entire systems and
 * system subcomponents --- e.g., the GUPS rating of a distributed memory
 * multiprocessor the GUPS rating of an SMP node, and the GUPS rating of a
 * single processor.  While there is typically a scaling of FLOPS with processor
 * count, a similar phenomenon may not always occur for GUPS.
 *
 *
 */
#include "device/nvshmemx_collective_launch_apis.h"
#include "device_host/nvshmem_types.h"
#include "host/nvshmem_api.h"
#include "host/nvshmem_coll_api.h"
#include "mpi.h"
#include "nvshmem.h"
#include "nvshmemx.h"
#include <sched.h>
#include <hpcc.h>
#include "RandomAccess.h"

//#include <shmem.h>
// Host-only includes
#ifndef __CUDA_ARCH__
#include <stdio.h>
#endif

#define MAXTHREADS 256
#define _SHMEM_BCAST_SYNC_SIZE  2
#define _SHMEM_REDUCE_SYNC_SIZE  3
#define _SHMEM_SYNC_VALUE  -1

void
do_abort(char* f)
{
#ifndef __CUDA_ARCH__
  fprintf(stderr, "%s\n", f);
#endif
}

u64Int srcBuf[] = {
  0xb1ffd1da
};
u64Int targetBuf[sizeof(srcBuf) / sizeof(u64Int)];

/* Allocate main table (in global memory) */
u64Int *HPCC_Table;

#define CUDA_CHECK(stmt)                                  \
do {                                                      \
    cudaError_t result = (stmt);                          \
    if (cudaSuccess != result) {                          \
        fprintf(stderr, "[%s:%d] CUDA failed with %s \n", \
         __FILE__, __LINE__, cudaGetErrorString(result)); \
        exit(-1);                                         \
    }                                                     \
} while (0)
__device__ void run(int mype, int numProcesses,int MyProc, 
  int LocalTableSize, int remote_val, int verify, s64Int *ran_gpu,
 s64Int *updates, u64Int *HPCC_Table, int ProcNumUpdates,
int logTableSize, int logNumProcs) {
  int j,k;
  int logTableLocal,ipartner,iterate,niterate;
  int ndata,nkeep,nsend,nrecv,index,nlocalm1;
  int numthrds;
  u64Int datum,procmask;
  int remote_proc, offset;
  s64Int remotecount;
  int thisPeId;
  int numNodes;
  int count2;

  thisPeId = mype; 
  numNodes = numProcesses;
  niterate = ProcNumUpdates;
  logTableLocal = logTableSize - logNumProcs;
  nlocalm1 = LocalTableSize - 1;
  for (iterate = 0; iterate < niterate; iterate++) {
      *ran_gpu = (*ran_gpu << 1) ^ ((s64Int) *ran_gpu < ZERO64B ? POLY : ZERO64B);
      remote_proc = (*ran_gpu >> logTableLocal) & (numNodes - 1);

      /*Forces updates to remote PE only*/
      if(remote_proc == MyProc)
        remote_proc = (remote_proc + 1) % numNodes;  // Fix: use modulo instead of division

      // Add bounds checking
      s64Int local_index = *ran_gpu & (LocalTableSize-1);
      if (local_index >= 0 && local_index < LocalTableSize
          && remote_proc >= 0 && remote_proc < numNodes) {
        // cast to the SHMEM-required long long pointer/value types
        remote_val = (u64Int)
          nvshmem_longlong_g((long long *)&HPCC_Table[local_index],
                           remote_proc);
        remote_val ^= *ran_gpu;
        nvshmem_longlong_p((long long *)&HPCC_Table[local_index],
                         (long long)remote_val,
                         remote_proc);
        nvshmem_quiet();

        if (verify)
          //nvshmem_longlong_atomic_inc((long long *)&updates[thisPeId], remote_proc);
        atomicInc((uint*)&updates[thisPeId], 1);
      }
  }
}

__global__ void launch(int mype, int numProcesses,int MyProc, 
  int LocalTableSize, int remote_val, int verify, s64Int *ran_gpu,
 s64Int *updates, u64Int *HPCC_Table_gpu, int ProcNumUpdates, int logTableSize, int logNumProcs) {
  run(mype, numProcesses,MyProc, 
  LocalTableSize, remote_val, verify, ran_gpu,
 updates, HPCC_Table_gpu,ProcNumUpdates, logTableSize, logNumProcs);
}
int main(int argc, char **argv)
{
  //printf("log 0 : start\n");
  int debug = 0;
  int verify = 0; 
  s64Int i;
  int NumProcs, logNumProcs, MyProc;
  u64Int GlobalStartMyProc;
  u64Int Top;               /* Number of table entries in top of Table */
  s64Int LocalTableSize;    /* Local table width */
  u64Int MinLocalTableSize; /* Integer ratio TableSize/NumProcs */
  u64Int logTableSize, TableSize;

  double CPUTime;               /* CPU  time to update table */
  double RealTime;              /* Real time to update table */

  double TotalMem;
  int PowerofTwo;
  //printf("log 0.03\n");
  double timeBound = -1;  /* OPTIONAL time bound for execution time */
  u64Int NumUpdates_Default; /* Number of updates to table (suggested: 4x number of table entries) */
  u64Int NumUpdates;  /* actual number of updates to table - may be smaller than
                       * NumUpdates_Default due to execution time bounds */
  s64Int ProcNumUpdates; /* number of updates per processor */
  s64Int *NumErrors, *GlbNumErrors;
#ifdef RA_TIME_BOUND
  s64Int GlbNumUpdates;  /* for reduction */
#endif

  long *llpSync;
  long long *llpWrk;

  long *ipSync;
  int *ipWrk;
  dim3 gridDims(1, 1, 1);
  dim3 blockDims(1, 1, 1);
  FILE *outFile = NULL;
  double *GUPs;
  double *temp_GUPs;

  //printf("log 0.1\n");
  int numthreads;
  int *sAbort, *rAbort;
 /* ------------------- */
  int rank, numProcesses;
  MPI_Init( &argc, &argv);
	// MPI_File mpi_inputFile, mpi_compressedFile;
	MPI_Status status;
	//printf("log 0.15\n");
	// get rank and number of processes value
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);
	MPI_Comm_size(MPI_COMM_WORLD, &numProcesses);
	// init nvshmem
	MPI_Comm mpi_comm = MPI_COMM_WORLD;
	nvshmemx_init_attr_t attr = NVSHMEMX_INIT_ATTR_INITIALIZER;
	int mype;
	attr.mpi_comm = &mpi_comm;
	nvshmemx_init_attr(NVSHMEMX_INIT_WITH_MPI_COMM, &attr);
  mype = nvshmem_my_pe();
  int local_pe = nvshmem_team_my_pe(NVSHMEMX_TEAM_NODE);
	int npes  = numProcesses;
  CUDA_CHECK(cudaSetDevice(local_pe));
  //printf("log 0.2\n");
	/*----------------------------------*/

  
  //printf("log 0.201\n");
  /*Allocate symmetric memory*/
  sAbort = (int *)malloc(sizeof(int));
  rAbort = (int *)malloc(sizeof(int));
  llpSync = (long *)malloc(sizeof(long) * _SHMEM_BCAST_SYNC_SIZE);
  llpWrk = (long long *)malloc(sizeof(long long) *  _SHMEM_REDUCE_SYNC_SIZE);
  ipSync = (long *)malloc(sizeof(long) * _SHMEM_BCAST_SYNC_SIZE);
  ipWrk = (int *)malloc(sizeof(int) * _SHMEM_REDUCE_SYNC_SIZE);
  //printf("log 0.202\n");
  GUPs = (double *)malloc(sizeof(double));
  temp_GUPs = (double *)malloc(sizeof(double));
  GlbNumErrors = (s64Int *)malloc(sizeof(s64Int));
  NumErrors = (s64Int *)malloc(sizeof(s64Int));
  //printf("log 0.203\n");
  *GlbNumErrors = 0;
  //printf("log 0.204\n");
  *NumErrors = 0;
  //printf("log 0.205\n");
  for (i = 0; i < _SHMEM_BCAST_SYNC_SIZE; i += 1){
        llpSync[i] = _SHMEM_SYNC_VALUE;
        ipSync[i] = _SHMEM_SYNC_VALUE;
  }
  //printf("log 0.208\n");
  *GUPs = 0.0;
  //printf("log 0.21\n");
  NumProcs = numProcesses; // Use the number of processes from MPI
  MyProc = mype; // Use the rank from MPI

  // Add missing initialization
  for (logNumProcs = 0, i = 1; i < NumProcs; logNumProcs++, i <<= 1)
    ; /* EMPTY */
  PowerofTwo = (i == NumProcs);

  if (0 == MyProc) {
#ifndef __CUDA_ARCH__
    outFile = stdout;
    setbuf(outFile, NULL);
#endif
  }

  TotalMem = 20000000; /* max single node memory */
  TotalMem *= NumProcs;             /* max memory in NumProcs nodes */

  TotalMem /= sizeof(u64Int);

  /* calculate TableSize --- the size of update array (must be a power of 2) */
  for (TotalMem *= 0.5, logTableSize = 0, TableSize = 1;
       TotalMem >= 1.0;
       TotalMem *= 0.5, logTableSize++, TableSize <<= 1)
    ; /* EMPTY */


  MinLocalTableSize = (TableSize / NumProcs);
  LocalTableSize = MinLocalTableSize;
  GlobalStartMyProc = (MinLocalTableSize * MyProc);

  *sAbort = 0;
  //printf("log 0.22\n");
  /*Shmalloc HPCC_Table for RMA*/
  HPCC_Table = (u64Int *)malloc( sizeof(u64Int)*LocalTableSize );
  if (! HPCC_Table) *sAbort = 1;

  //printf("log 0.23\n");
  //nvshmem_barrier_all();
  MPI_Barrier(MPI_COMM_WORLD);
  MPI_Allreduce(sAbort,rAbort,1,MPI_INT,MPI_SUM,MPI_COMM_WORLD);
  MPI_Barrier(MPI_COMM_WORLD);
  //nvshmem_int_sum_reduce(NVSHMEMX_TEAM_NODE,rAbort,sAbort,1);
  //nvshmem_barrier_all();
  void* args[12];
  if (*rAbort > 0) {
#ifndef __CUDA_ARCH__
    if (MyProc == 0) fprintf(outFile, "Failed to allocate memory for the main table.\n");
#endif
    /* check all allocations in case there are new added and their order changes */
    if (HPCC_Table) nvshmem_free( HPCC_Table );  // Fix: use shmem_free instead of HPCC_free
    goto failed_table;
  }
  //printf("log 0.28\n");
  /* Default number of global updates to table: 4x number of table entries */
  NumUpdates_Default = 4 * TableSize;
  ProcNumUpdates = 4*LocalTableSize;
  NumUpdates = NumUpdates_Default;

  if (MyProc == 0) {
#ifndef __CUDA_ARCH__
    fprintf( outFile, "Running on %d processors%s\n", NumProcs, PowerofTwo ? " (PowerofTwo)" : "");
    fprintf( outFile, "Total Main table size = 2^" FSTR64 " = " FSTR64 " words\n",logTableSize, TableSize );
    if (PowerofTwo)
        fprintf( outFile, "PE Main table size = 2^" FSTR64 " = " FSTR64 " words/PE\n",
                 (logTableSize - logNumProcs), TableSize/NumProcs );
    else
        fprintf( outFile, "PE Main table size = (2^" FSTR64 ")/%d  = " FSTR64 " words/PE MAX\n",
                 logTableSize, NumProcs, LocalTableSize);

    fprintf( outFile, "Default number of updates (RECOMMENDED) = " FSTR64 "\tand actually done = %d\n", NumUpdates_Default,ProcNumUpdates*NumProcs);
#endif
  }
  //printf("log 0.3\n");
  /* Initialize main table */
  for (i=0; i<LocalTableSize; i++)
    HPCC_Table[i] = MyProc;
  //printf("log 0.301\n");
  nvshmem_barrier_all();
  //printf("log 0.302\n");
  int j,k;
  int logTableLocal,ipartner,iterate,niterate;
  int ndata,nkeep,nsend,nrecv,index,nlocalm1;
  int numthrds;
  u64Int datum,procmask;
  u64Int *data,*send;
  void * tstatus;
  int remote_proc, offset;
  u64Int *tb;
  s64Int remotecount;
  int thisPeId;
  int numNodes;
  int count2;
  //printf("log 0.303\n");
  s64Int *count;
  s64Int *updates;
  s64Int *all_updates;
  s64Int *ran;
  //printf("log 0.31\n");
  thisPeId = mype; 
  numNodes = numProcesses;

  count = (s64Int *) malloc(sizeof(s64Int));
  ran = (s64Int *) malloc(sizeof(s64Int));
  updates = (s64Int *) malloc(sizeof(s64Int) * numNodes);
  all_updates = (s64Int *) malloc(sizeof(s64Int) * numNodes);
  s64Int *count_gpu;
  s64Int *updates_gpu;
  s64Int *all_updates_gpu;
  s64Int *ran_gpu;
  count_gpu = (s64Int *) nvshmem_malloc(sizeof(s64Int));
  ran_gpu = (s64Int *) nvshmem_malloc(sizeof(s64Int));
  updates_gpu = (s64Int *) nvshmem_malloc(sizeof(s64Int) * numNodes);
  all_updates_gpu = (s64Int *) nvshmem_malloc(sizeof(s64Int) * numNodes);
  //printf("log 0.32\n");
  // Add allocation checks
  if (!count || !ran || !updates || !all_updates) {
#ifndef __CUDA_ARCH__
    if (MyProc == 0) fprintf(outFile, "Failed to allocate memory for arrays.\n");
#endif
    // Clean up any successful allocations
    if (count) nvshmem_free(count);
    if (ran) nvshmem_free(ran);
    if (updates) nvshmem_free(updates);
    if (all_updates) nvshmem_free(all_updates);
    if (HPCC_Table) free(HPCC_Table);
    goto failed_table;
  }
  //printf("log 0.33\n");
  *ran = starts(4*GlobalStartMyProc);
  //printf("log 0.4\n");
  niterate = ProcNumUpdates;
  logTableLocal = logTableSize - logNumProcs;
  nlocalm1 = LocalTableSize - 1;
  //printf("log 0.41\n");
  u64Int* HPCC_Table_gpu;
  HPCC_Table_gpu = (u64Int*)nvshmem_malloc(sizeof(u64Int) * LocalTableSize);
  cudaMemcpy(HPCC_Table_gpu, HPCC_Table, sizeof(u64Int) * LocalTableSize, cudaMemcpyHostToDevice);
  
  for (j = 0; j < numNodes; j++){
    updates[j] = 0;
    all_updates[j] = 0;  // Fix: was incorrectly setting all_updates = 0
  }
  u64Int remote_val;
  cudaMemcpy(ran_gpu, ran, sizeof(s64Int), cudaMemcpyHostToDevice);
  cudaMemcpy(updates_gpu, updates, sizeof(s64Int) * numNodes, cudaMemcpyHostToDevice);
  cudaMemcpy(all_updates_gpu, all_updates, sizeof(s64Int) * numNodes, cudaMemcpyHostToDevice);
  cudaMemcpy(count_gpu, count, sizeof(s64Int), cudaMemcpyHostToDevice);
  
  nvshmem_barrier_all();
  /* Begin timed section */

  RealTime = -RTSEC();
//   launch<<<1,1>>>(mype, numProcesses,MyProc, 
//   LocalTableSize, remote_val, verify, ran_gpu,
//  updates, HPCC_Table_gpu,ProcNumUpdates, logTableSize,logNumProcs);
  args[0] = (void *)&mype;
  args[1] = (void *)&numProcesses;
  args[2] = (void *)&MyProc;
  args[3] = (void *)&LocalTableSize;
  args[4] = (void *)&remote_val;
  args[5] = (void *)&verify;
  args[6] = (void *)&ran_gpu;
  args[7] = (void *)&updates_gpu;
  args[8] = (void *)&HPCC_Table_gpu;
  args[9] = (void *)&ProcNumUpdates;
  args[10] = (void *)&logTableSize;
  args[11] = (void *)&logNumProcs;
  nvshmemx_collective_launch((void *)launch, gridDims,blockDims, args, 0, 0);
  cudaDeviceSynchronize();

  nvshmem_barrier_all();
  /* End timed section */
  RealTime += RTSEC();

  //printf("log 1\n");

  /* Print timing results */
  if (MyProc == 0){
    *GUPs = 1e-9*NumUpdates / RealTime;
#ifndef __CUDA_ARCH__
    fprintf( outFile, "Real time used = %.6f seconds\n", RealTime );
    fprintf( outFile, "%.9f Billion(10^9) Updates    per second [GUP/s]\n",
             *GUPs );
    fprintf( outFile, "%.9f Billion(10^9) Updates/PE per second [GUP/s]\n",
             *GUPs / NumProcs );
#endif
  }
 
  if(verify){
    for (j = 1; j < numNodes; j++)
      updates[0] += updates[j];
    int cpu = sched_getcpu();
#ifndef __CUDA_ARCH__
    printf("PE%d CPU%d  updates:%lld\n",MyProc,cpu,(long long)updates[0]);
#endif

    nvshmem_longlong_sum_reduce(NVSHMEMX_TEAM_NODE,all_updates,updates,numNodes); // Fix: use numNodes instead of NumProcs
    if(MyProc == 0){
      for (j = 1; j < numNodes; j++)
        all_updates[0] += all_updates[j];
      if(ProcNumUpdates*NumProcs == all_updates[0])
        printf("Verification passed!\n");
      else
        printf("Verification failed!\n");
    }
  }
  nvshmem_barrier_all();
  /* End verification phase */

  // Fix memory deallocation order - free in reverse allocation order
  free(all_updates);
  free(updates);
  free(ran);
  free(count);
  nvshmem_barrier_all();
  //printf("log 0.5\n");
  /* Deallocate memory (in reverse order of allocation which should
 *      help fragmentation) */

  nvshmem_free( HPCC_Table );  // Fix: use shmem_free instead of HPCC_free
  failed_table:

#ifndef __CUDA_ARCH__
  if (0 == MyProc) if (outFile != stderr) fclose( outFile );
#endif

  nvshmem_barrier_all();

  // Add missing deallocations
  free(NumErrors);
  free(GlbNumErrors);
  free(temp_GUPs);
  free(GUPs);
  free(ipWrk);
  free(ipSync);
  free(llpWrk);
  free(llpSync);
  free(rAbort);
  free(sAbort);

  nvshmem_barrier_all();
  //printf("log 0.6\n");
  nvshmem_finalize();

  return 0;
}

/* Utility routine to start random number generator at Nth step */
s64Int
starts(u64Int n)
{
  /* s64Int i, j; */
  int i, j;
  u64Int m2[64];
  u64Int temp, ran;

  while (n < 0)
    n += PERIOD;
  while (n > PERIOD)
    n -= PERIOD;
  if (n == 0)
    return 0x1;

  temp = 0x1;
  for (i=0; i<64; i++)
    {
      m2[i] = temp;
      temp = (temp << 1) ^ ((s64Int) temp < 0 ? POLY : 0);
      temp = (temp << 1) ^ ((s64Int) temp < 0 ? POLY : 0);
    }

  for (i=62; i>=0; i--)
    if ((n >> i) & 1)
      break;

  ran = 0x2;

  while (i > 0)
    {
      temp = 0;
      for (j=0; j<64; j++)
        if ((ran >> j) & 1)
          temp ^= m2[j];
      ran = temp;
      i -= 1;
      if ((n >> i) & 1)
        ran = (ran << 1) ^ ((s64Int) ran < 0 ? POLY : 0);
    }

  return ran;
}
