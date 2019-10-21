
#include <sys/time.h>
#include <iostream>

#include "SorterIndication.h"
#include "SorterRequest.h"
#include "ConnectalProjectConfig.h"

#define CL_SZ 80

sem_t done_sem;

unsigned long numCL = 0;

uint64_t iter = 0;

class SorterIndication : public SorterIndicationWrapper{
public:
	virtual void sortingDone(uint64_t int_unsorted_cnt, uint64_t ext_unsorted_cnt, uint64_t cycles){
		fprintf(stderr, "Sorting done in %lu cycles\n", cycles);
		fprintf(stderr, "\tCycles per beat (%lu,%lu) = %lf\n",
				cycles, iter*SORT_SZ_L1/32, (double)cycles/(double)(iter*SORT_SZ_L1/32));
		fprintf(stderr, "\tInternal Unsorted Count %lu\n", int_unsorted_cnt);
		fprintf(stderr, "\tExternal Unsorted Count %lu\n", ext_unsorted_cnt);
		sem_post(&done_sem);
	}
  
	SorterIndication(unsigned int id) : SorterIndicationWrapper(id){}
};

int main(int argc, const char **argv){
  SorterRequestProxy *device = new SorterRequestProxy(IfcNames_SorterRequestS2H);
  SorterIndication testIndication(IfcNames_SorterIndicationH2S);

  if(sem_init(&done_sem, 1, 0)){
    fprintf(stderr, "failed to init done_sem\n");
    return -1;
  }

  std::cout << "Input your test iterations: ";
  std::cin >> iter;

#ifdef SIMULATION
  fprintf(stderr, "SIMULATION STARTS\n");
#else
  fprintf(stderr, "FPGA STARTS\n");
#endif

  for (int i = 0; i < 8; i++){
	  device->initSeed(rand());
  }

  device->startSorting(iter);
  sem_wait(&done_sem);
  sleep(1);
  return 0;
}
