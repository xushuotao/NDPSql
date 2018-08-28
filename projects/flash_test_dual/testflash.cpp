
#include <sys/time.h>
#include <iostream>
#include <stdlib.h>
#include <time.h>

#include "FlashTestIndication.h"
#include "FlashTestRequest.h"

#define CL_SZ 80

sem_t sem;

unsigned long numCL = 0;

class FlashTestIndication : public FlashTestIndicationWrapper{
public:
  virtual void eraseDone1(uint64_t cycles, uint32_t erased_blocks, uint32_t bad_blocks){
#ifndef SIMULATION
    fprintf(stderr, "Erase Benchmark 1 Finished: cycles = %lu, erased_block = %u, bad_blocks = %u, BW = %lf MB/s, %lf blks/us \n", cycles, erased_blocks, bad_blocks, (double)(erased_blocks*16*8192/(1<<20))/(double)(cycles*8e-9), (double)erased_blocks/(double)(cycles*8/1000));
#else
  fprintf(stderr, "Erase Benchmark 1 Finished: cycles = %lu, erased_block = %u, bad_blocks = %u, BW = %lf MB/s, %lf blks/us \n", cycles, erased_blocks, bad_blocks, (double)(erased_blocks*256*8192/(1<<20))/(double)(cycles*8e-9), (double)erased_blocks/(double)(cycles*8/1000));
#endif
  }
  
  virtual void writeDone1(uint64_t cycles, uint32_t written_pages){
    fprintf(stderr, "Write Benchmark 1 Finished: cycles = %lu, written_pages = %u, BW = %lf(MB/us)\n", cycles, written_pages, (written_pages*8192.0/(1<<20))/(cycles*8.0e-9));
  }

  virtual void readDone1(uint64_t cycles, uint32_t read_pages, uint32_t wrong_words, uint32_t wrong_pages){
    fprintf(stderr, "Read Benchmark 1 Finished: cycles = %lu, read_pages = %u, wrong_words = %u, wrong_pages = %u, BW = %lf(MB/s)\n",
            cycles, read_pages, wrong_words, wrong_pages, (read_pages*8192.0/(1<<20))/(cycles*8.0e-9));
    if (++readDoneCnt==2)
      exit(0);
  }

  virtual void auroraStatus1( const uint8_t channel_up, const uint8_t lane_up ){
    fprintf(stderr, "auroraIntra1 Status: channel_up = %x, lane_up = %x\n", channel_up, lane_up);
    if (++statusCnt==2)
      sem_post(&sem);
  }

  virtual void eraseDone2(uint64_t cycles, uint32_t erased_blocks, uint32_t bad_blocks){
#ifndef SIMULATION
    fprintf(stderr, "Erase Benchmark 2 Finished: cycles = %lu, erased_block = %u, bad_blocks = %u, BW = %lf MB/s, %lf blks/us \n", cycles, erased_blocks, bad_blocks, (double)(erased_blocks*16*8192/(1<<20))/(double)(cycles*8e-9), (double)erased_blocks/(double)(cycles*8/1000));
#else
  fprintf(stderr, "Erase Benchmark 2 Finished: cycles = %lu, erased_block = %u, bad_blocks = %u, BW = %lf MB/s, %lf blks/us \n", cycles, erased_blocks, bad_blocks, (double)(erased_blocks*256*8192/(1<<20))/(double)(cycles*8e-9), (double)erased_blocks/(double)(cycles*8/1000));
#endif
  }
  
  virtual void writeDone2(uint64_t cycles, uint32_t written_pages){
    fprintf(stderr, "Write Benchmark 2 Finished: cycles = %lu, written_pages = %u, BW = %lf(MB/us)\n", cycles, written_pages, (written_pages*8192.0/(1<<20))/(cycles*8.0e-9));
    
  }

  virtual void readDone2(uint64_t cycles, uint32_t read_pages, uint32_t wrong_words, uint32_t wrong_pages){
    fprintf(stderr, "Read Benchmark 2 Finished: cycles = %lu, read_pages = %u, wrong_words = %u, wrong_pages = %u, BW = %lf(MB/s)\n",
            cycles, read_pages, wrong_words, wrong_pages, (read_pages*8192.0/(1<<20))/(cycles*8.0e-9));
    if (++readDoneCnt==2)
      exit(0);
  }

  virtual void auroraStatus2( const uint8_t channel_up, const uint8_t lane_up ){
    fprintf(stderr, "auroraIntra2 Status: channel_up = %x, lane_up = %x\n", channel_up, lane_up);
    if (++statusCnt==2)
      sem_post(&sem);
  }
  int statusCnt;
  int readDoneCnt;

  FlashTestIndication(unsigned int id) : FlashTestIndicationWrapper(id){statusCnt=0;readDoneCnt=0;}
};

int main(int argc, const char **argv){
  FlashTestRequestProxy *device = new FlashTestRequestProxy(IfcNames_FlashTestRequestS2H);
  FlashTestIndication testIndication(IfcNames_FlashTestIndicationH2S);

  if(sem_init(&sem, 1, 0)){
    fprintf(stderr, "failed to init sem\n");
    return -1;
  }

  srand(time(NULL));

  device->auroraStatus();
  sem_wait(&sem);
  
  fprintf(stderr, "FPGA starts\n");

  device->start(rand());
  
  while (true);

}
