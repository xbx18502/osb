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

#include <sched.h>
#include <hpcc.h>
#include <stdio.h>
#include "RandomAccess.h"
#include <mpi.h>
#include <cuda_runtime.h>
#define MAXTHREADS 256

#define CUDA_CHECK(stmt)                                  \
do {                                                      \
    cudaError_t result = (stmt);                          \
    if (cudaSuccess != result) {                          \
        fprintf(stderr, "[%s:%d] CUDA failed with %s \n", \
         __FILE__, __LINE__, cudaGetErrorString(result)); \
        exit(-1);                                         \
    }                                                     \
} while (0)
#define MAXTHREADS 256
#define _SHMEM_BCAST_SYNC_SIZE  2
#define _SHMEM_REDUCE_SYNC_SIZE  3
#define _SHMEM_SYNC_VALUE  -1

void
do_abort(char* f)
{
  fprintf(stderr, "%s\n", f);
}

u64Int srcBuf[] = {
  0xb1ffd1da
};
u64Int targetBuf[sizeof(srcBuf) / sizeof(u64Int)];

/* Allocate main table (in global memory) */
u64Int *HPCC_Table;

int main(int argc, char **argv)
{
  int debug = 0;

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

  FILE *outFile = NULL;
  double *GUPs;
  double *temp_GUPs;


  int numthreads;
  int *sAbort, *rAbort;

   /* ------------------- */
  int rank, numProcesses;
  MPI_Init( &argc, &argv);
	MPI_Status status;
	//printf("log 0.15\n");
	// get rank and number of processes value
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);
	MPI_Comm_size(MPI_COMM_WORLD, &numProcesses);
	// init nvshmem
	MPI_Comm mpi_comm = MPI_COMM_WORLD;
	
  // GPU设备设置
  int device_count;
  CUDA_CHECK(cudaGetDeviceCount(&device_count));
  CUDA_CHECK(cudaSetDevice(rank % device_count));
  //printf("log 0.2\n");
	/*----------------------------------*/

  /*Allocate symmetric memory*/
  sAbort = (int *)malloc(sizeof(int));
  rAbort = (int *)malloc(sizeof(int));
  llpSync = (long *)malloc(sizeof(long) *_SHMEM_BCAST_SYNC_SIZE);
  llpWrk = (long long *)malloc(sizeof(long long) * _SHMEM_REDUCE_SYNC_SIZE);
  ipSync = (long *)malloc(sizeof(long) *_SHMEM_BCAST_SYNC_SIZE);
  ipWrk = (int *)malloc(sizeof(int) * _SHMEM_REDUCE_SYNC_SIZE);

  GUPs = (double *)malloc(sizeof(double));
  temp_GUPs = (double *)malloc(sizeof(double));
  GlbNumErrors = (s64Int *)malloc(sizeof(s64Int));
  NumErrors = (s64Int *)malloc(sizeof(s64Int));

  *GlbNumErrors = 0;
  *NumErrors = 0;

  for (i = 0; i < _SHMEM_BCAST_SYNC_SIZE; i += 1){
        ipSync[i] = _SHMEM_SYNC_VALUE;
        llpSync[i] = _SHMEM_SYNC_VALUE;
  }

  *GUPs = -1;

  NumProcs = numProcesses;
  MyProc = rank;

  // Add missing initialization
  for (logNumProcs = 0, i = 1; i < NumProcs; logNumProcs++, i <<= 1)
    ; /* EMPTY */
  PowerofTwo = (i == NumProcs);

  if (0 == MyProc) {
    outFile = stdout;
    setbuf(outFile, NULL);
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

  /*Shmalloc HPCC_Table for RMA*/
  HPCC_Table = (u64Int *)malloc( sizeof(u64Int)*LocalTableSize );
  u64Int *HPCC_Table_gpu;
  CUDA_CHECK(cudaMalloc((void**)&HPCC_Table_gpu, sizeof(u64Int)*LocalTableSize));
  
  if (! HPCC_Table) *sAbort = 1;

  MPI_Barrier(MPI_COMM_WORLD);
  //shmem_int_sum_to_all(rAbort, sAbort, 1, 0, 0, NumProcs, ipWrk, ipSync);
  MPI_Allreduce(sAbort, rAbort, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
  MPI_Barrier(MPI_COMM_WORLD);

  if (*rAbort > 0) {
    if (MyProc == 0) fprintf(outFile, "Failed to allocate memory for the main table.\n");
    /* check all allocations in case there are new added and their order changes */
    if (HPCC_Table) free( HPCC_Table );  // Fix: use shmem_free instead of HPCC_free
    //goto failed_table;
  }

  /* Default number of global updates to table: 4x number of table entries */
  NumUpdates_Default = 4 * TableSize;
  ProcNumUpdates = 4*LocalTableSize;
  NumUpdates = NumUpdates_Default;

  if (MyProc == 0) {
    fprintf( outFile, "Running on %d processors%s\n", NumProcs, PowerofTwo ? " (PowerofTwo)" : "");
    fprintf( outFile, "Total Main table size = 2^" FSTR64 " = " FSTR64 " words\n",logTableSize, TableSize );
    if (PowerofTwo)
        fprintf( outFile, "PE Main table size = 2^" FSTR64 " = " FSTR64 " words/PE\n",
                 (logTableSize - logNumProcs), TableSize/NumProcs );
    else
        fprintf( outFile, "PE Main table size = (2^" FSTR64 ")/%d  = " FSTR64 " words/PE MAX\n",
                 logTableSize, NumProcs, LocalTableSize);

    fprintf( outFile, "Default number of updates (RECOMMENDED) = " FSTR64 "\tand actually done = %d\n", NumUpdates_Default,ProcNumUpdates*NumProcs);
  }

  /* Initialize main table */
  for (i=0; i<LocalTableSize; i++)
    HPCC_Table[i] = MyProc;

  MPI_Barrier(MPI_COMM_WORLD);

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

  s64Int *count;
  s64Int *updates;
  s64Int *all_updates;
  s64Int *ran;

  thisPeId = MyProc;
  numNodes = numProcesses;

  count = (s64Int *) malloc(sizeof(s64Int));
  ran = (s64Int *) malloc(sizeof(s64Int));
  updates = (s64Int *) malloc(sizeof(s64Int) * numNodes);
  all_updates = (s64Int *) malloc(sizeof(s64Int) * numNodes);

  // Add allocation checks
  if (!count || !ran || !updates || !all_updates) {
    if (MyProc == 0) fprintf(outFile, "Failed to allocate memory for arrays.\n");
    // Clean up any successful allocations
    if (count) free(count);
    if (ran) free(ran);
    if (updates) free(updates);
    if (all_updates) free(all_updates);
    if (HPCC_Table) free(HPCC_Table);
    //goto failed_table;
  }

  *ran = starts(4*GlobalStartMyProc);

  niterate = ProcNumUpdates;
  logTableLocal = logTableSize - logNumProcs;
  nlocalm1 = LocalTableSize - 1;

  
  for (j = 0; j < numNodes; j++){
    updates[j] = 0;
    all_updates[j] = 0;  // Fix: was incorrectly setting all_updates = 0
  }
  int verify=0; 
  printf("log 100\n");
  // 改进的MPI窗口创建
  MPI_Win mpi_win;
  MPI_Info win_info;
  MPI_Info_create(&win_info);
  printf("log 101\n");
  // 关键：明确告诉MPI这是GPU内存
  MPI_Info_set(win_info, "alloc_shm", "false");  // 禁用共享内存优化
  MPI_Info_set(win_info, "same_disp_unit", "true");
  MPI_Info_set(win_info, "no_locks", "true");     // 禁用锁优化
  printf("log 102\n");
  // 检查CUDA-Aware MPI支持
  // char *ompi_version;
  // int flag;
  // MPI_Get_processor_name(NULL, &flag); // 触发初始化

  printf("log 103\n");
  if (MyProc == 0) {
    // 检查环境变量
    char *cuda_support = getenv("OMPI_MCA_opal_cuda_support");
    printf("CUDA support environment: %s\n", cuda_support ? cuda_support : "not set");
    
    // 尝试检测CUDA-Aware功能
    printf("Attempting to create MPI window on GPU memory...\n");
  }
  printf("log 104\n");
  int ret = MPI_Win_create(HPCC_Table_gpu, sizeof(u64Int)*LocalTableSize, 
                          sizeof(u64Int), win_info, MPI_COMM_WORLD, &mpi_win);
  printf("log 105\n");
  if (ret != MPI_SUCCESS) {
      char error_string[MPI_MAX_ERROR_STRING];
      int length;
      MPI_Error_string(ret, error_string, &length);
      printf("Process %d: MPI_Win_create failed: %s\n", MyProc, error_string);
      
      // 回退到主机内存
      printf("Process %d: Falling back to host memory\n", MyProc);
      MPI_Win_create(HPCC_Table, sizeof(u64Int)*LocalTableSize, 
                    sizeof(u64Int), win_info, MPI_COMM_WORLD, &mpi_win);
  }
  printf("log 106\n");
  MPI_Info_free(&win_info);
  u64Int remote_val;
  CUDA_CHECK(cudaMemcpy(HPCC_Table_gpu, HPCC_Table, sizeof(u64Int)*LocalTableSize, cudaMemcpyHostToDevice));
  CUDA_CHECK(cudaDeviceSynchronize()); // 确保传输完成
  // 确保所有进程准备就绪
  MPI_Barrier(MPI_COMM_WORLD);
  MPI_Win_fence(0, mpi_win);
  CUDA_CHECK(cudaMalloc((void**)&remote_val,sizeof(u64Int)));
  /* Begin timed section */
  RealTime = -RTSEC();
  u64Int *local_index_d;
  CUDA_CHECK(cudaMalloc((void**)&local_index_d,sizeof(u64Int)));
  printf("log 107\n");
  for (iterate = 0; iterate < niterate; iterate++) {
        *ran = (*ran << 1) ^ ((s64Int) *ran < ZERO64B ? POLY : ZERO64B);
        remote_proc = (*ran >> logTableLocal) & (numNodes - 1);
        
        if(remote_proc == MyProc)
            remote_proc = (remote_proc + 1) % numNodes;
            
        s64Int local_index = *ran & (LocalTableSize-1);
        CUDA_CHECK(cudaMemcpy(local_index_d, &local_index, sizeof(u64Int), cudaMemcpyHostToDevice));
        //printf("log 108\n");
        if (local_index >= 0 && local_index < LocalTableSize && 
            remote_proc >= 0 && remote_proc < numNodes) {
            
            // CUDA-Aware MPI: 直接传输GPU内存数据
            // 添加错误处理
            int ret;
            //u64Int remote_val;
            ret = MPI_Get(&remote_val, 1, MPI_UINT64_T, remote_proc, 
                        local_index, 1, MPI_UINT64_T, mpi_win);
            if (ret != MPI_SUCCESS) {
                fprintf(stderr, "MPI_Get failed with error %d\n", ret);
                continue;
            }
            
            remote_val ^= *ran;
            
            // 直接更新GPU内存
            ret = MPI_Put(&remote_val, 1, MPI_UINT64_T, remote_proc,
                  local_index, 1, MPI_UINT64_T, mpi_win);
            if (ret != MPI_SUCCESS) {
                fprintf(stderr, "MPI_Put failed with error %d\n", ret);
            }
            //MPI_Win_flush(remote_proc, mpi_win);
        }
    }
  MPI_Win_fence(0, mpi_win);  // 添加这行
  MPI_Barrier(MPI_COMM_WORLD);
  /* End timed section */
  RealTime += RTSEC();



  /* Print timing results */
  if (MyProc == 0){
    *GUPs = 1e-9*NumUpdates / RealTime;
    fprintf( outFile, "Real time used = %.6f seconds\n", RealTime );
    fprintf( outFile, "%.9f Billion(10^9) Updates    per second [GUP/s]\n",
             *GUPs );
    fprintf( outFile, "%.9f Billion(10^9) Updates/PE per second [GUP/s]\n",
             *GUPs / NumProcs );
  }
 
  if(verify){
    for (j = 1; j < numNodes; j++)
      updates[0] += updates[j];
    int cpu = sched_getcpu();
    printf("PE%d CPU%d  updates:%lld\n",MyProc,cpu,(long long)updates[0]);  // Fix: use proper format specifier

  // 替换 shmem_longlong_sum_to_all
  MPI_Allreduce(updates, all_updates, numNodes, MPI_LONG_LONG, 
                  MPI_SUM, MPI_COMM_WORLD);
  if(MyProc == 0){
      for (j = 1; j < numNodes; j++)
        all_updates[0] += all_updates[j];
      if(ProcNumUpdates*NumProcs == all_updates[0])
        printf("Verification passed!\n");
      else
        printf("Verification failed!\n");
    }
  }
  MPI_Barrier(MPI_COMM_WORLD);
  /* End verification phase */

  // Fix memory deallocation order - free in reverse allocation order
  free(all_updates);
  free(updates);
  free(ran);
  free(count);
  MPI_Barrier(MPI_COMM_WORLD);

  /* Deallocate memory (in reverse order of allocation which should
 *      help fragmentation) */

  free( HPCC_Table );  // Fix: use shmem_free instead of HPCC_free
  failed_table:

  if (0 == MyProc) if (outFile != stderr) fclose( outFile );

  MPI_Barrier(MPI_COMM_WORLD);

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

  MPI_Barrier(MPI_COMM_WORLD);

  MPI_Finalize();

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
