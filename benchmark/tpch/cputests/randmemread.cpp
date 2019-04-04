#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <iostream>
#include <chrono>
#include <omp.h>

#define ARRAY_SZ 1ULL<<(32)

#define ITER 1ULL<<30

static unsigned long x=123456789, y=362436069, z=521288629;

static inline unsigned long xorshf96() {          //period 2^96-1
  unsigned long t;
  x ^= x << 16;
  x ^= x >> 5;
  x ^= x << 1;

  t = x;
  x = y;
  y = z;
  z = t ^ x ^ y;

  return z;
}


int main(){
  char* probeArray = (char*) malloc(ARRAY_SZ);
  uint64_t sum = 0;

  memset(probeArray, 1, ARRAY_SZ);
  int threadcnt;

  auto t_start = std::chrono::high_resolution_clock::now();
#pragma omp parallel
  {
    threadcnt = omp_get_num_threads();
    for ( int i = 0; i < threadcnt; i++) xorshf96();

    for (uint64_t i = 0; i < ITER; i++ ){
      auto rand = xorshf96();
      uint64_t ind = rand & ((ARRAY_SZ)-1);
      char b = probeArray[ind];
      sum += b;
      // fprintf(stderr, "threadid = %d, ind = %lx, rand = %lx\n", omp_get_thread_num(), ind, rand);
    }

  }
  auto t_end = std::chrono::high_resolution_clock::now();


  size_t size = ITER;
  double t_diff = std::chrono::duration<double, std::milli>(t_end-t_start).count();
  fprintf(stderr, "DONE (%lu) Throughput = (%lu*%u/%lfms)%lfMops\n", sum, size, threadcnt, t_diff, (double)size*threadcnt/t_diff/1000);
    
}
