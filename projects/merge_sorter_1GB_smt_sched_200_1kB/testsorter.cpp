#include <pthread.h>
#include <sys/time.h>
#include <iostream>

#include "SorterIndication.h"
#include "SorterRequest.h"
#include "ConnectalProjectConfig.h"


#define CL_SZ 80

// sem_t done_sem;
pthread_mutex_t mutex;

unsigned long numCL = 0;

uint64_t iter = 0;

bool done = false;

bool doneTrace0 = false;
bool doneTrace1 = false;
#define TraceSz 1024
uint32_t baseReq[2] = {0,0};
uint32_t reqMinCycle[2] = {UINT32_MAX, UINT32_MAX};
uint32_t baseResp[2] = {0,0};
uint32_t respMinCycle[2] = {UINT32_MAX, UINT32_MAX};
uint64_t reqCycle[2][TraceSz];
uint64_t reqAddr[2][TraceSz];
int     reqRNW[2][TraceSz];
uint64_t respCycle[2][TraceSz];
uint64_t respAddr[2][TraceSz]; 

class SorterIndication : public SorterIndicationWrapper{
public:
	virtual void sortingDone(uint64_t int_unsorted_cnt, uint64_t ext_unsorted_cnt, uint64_t cycles){
		fprintf(stderr, "Sorting done in %lu cycles\n", cycles);
		fprintf(stderr, "\tCycles per beat (%lu,%lu) = %lf\n",
				cycles, iter*SORT_SZ_L2/64, (double)cycles/(double)(iter*SORT_SZ_L2/64));
		fprintf(stderr, "\tInternal Unsorted Count %lu\n", int_unsorted_cnt);
		fprintf(stderr, "\tExternal Unsorted Count %lu\n", ext_unsorted_cnt);
        pthread_mutex_lock(&mutex);
        done = true;
        pthread_mutex_unlock(&mutex);
		// sem_post(&done_sem);
	}
    
    virtual void ackStatus(uint32_t iterCnt, uint32_t inCnt, uint32_t outCnt){
		fprintf(stderr, "Sorter status (iter, inCnt, outCnt) =  (%u, %u, %u), elemPerIter = %u\n", iterCnt, inCnt, outCnt, SORT_SZ_L2/4);
    }

    virtual void dramSorterStatus(uint64_t writes0, uint64_t reads0, uint64_t readResps0,
                                  uint64_t writes1, uint64_t reads1, uint64_t readResps1){
		fprintf(stderr, "DramSorterStatus to ctr 0 (writes, reads, readResps) =  (%lu, %lu, %lu)\n", writes0, reads0, readResps0);
        fprintf(stderr, "DramSorterStatus to ctr 1 (writes, reads, readResps) =  (%lu, %lu, %lu)\n", writes1, reads1, readResps1);
    }
    virtual void dramCtrlStatus(uint64_t writes0, uint64_t reads0, uint64_t readResps0,
                                uint64_t writes1, uint64_t reads1, uint64_t readResps1){
        fprintf(stderr, "DramCtrlStatus 0 (writes, reads, readResps) =  (%lu, %lu, %lu)\n", writes0, reads0, readResps0);
        fprintf(stderr, "DramCtrlStatus 1 (writes, reads, readResps) =  (%lu, %lu, %lu)\n", writes1, reads1, readResps1);
    }
    virtual void dramCntrDump0(uint64_t req_cycle, uint64_t req_addr, int req_rnw, uint64_t resp_cycle, uint64_t resp_addr){
        fprintf(stderr, "DramCtrlDump 0 dumpIdx0 = %u, (req_cycle, req_addr, req_rnw, resp_cycle, resp_addr) =  (%lu, %lu, %u, %lu, %lu)\n",
                dumpIdx0, req_cycle, req_addr, req_rnw, resp_cycle, resp_addr);

        pthread_mutex_lock(&mutex);
        reqCycle[0][dumpIdx0]  = req_cycle; 
        reqAddr[0][dumpIdx0]   = req_addr;  
        reqRNW[0][dumpIdx0]    = req_rnw;   
        respCycle[0][dumpIdx0] = resp_cycle;
        respAddr[0][dumpIdx0]  = resp_addr;
        if ( reqMinCycle[0] >  req_cycle && req_cycle != 0){
            reqMinCycle[0] = req_cycle;
            baseReq[0] = dumpIdx0;
        }
        if ( respMinCycle[0] >  resp_cycle && resp_cycle != 0){
            respMinCycle[0] = resp_cycle;
            baseResp[0] = dumpIdx0;
        }

        if ( ++dumpIdx0 == TraceSz){
            doneTrace0 = true;
        }
        pthread_mutex_unlock(&mutex);
    }
    
    virtual void dramCntrDump1(uint64_t req_cycle, uint64_t req_addr, int req_rnw, uint64_t resp_cycle, uint64_t resp_addr){
        fprintf(stderr, "DramCtrlDump 1 dumpIdx0 = %u, (req_cycle, req_addr, req_rnw, resp_cycle, resp_addr) =  (%lu, %lu, %u, %lu, %lu)\n",
                dumpIdx1, req_cycle, req_addr, req_rnw, resp_cycle, resp_addr);

        pthread_mutex_lock(&mutex);
        reqCycle[1][dumpIdx1]  = req_cycle; 
        reqAddr[1][dumpIdx1]   = req_addr;  
        reqRNW[1][dumpIdx1]    = req_rnw;   
        respCycle[1][dumpIdx1] = resp_cycle;
        respAddr[1][dumpIdx1]  = resp_addr;
        if ( reqMinCycle[1] >  req_cycle && req_cycle != 0){
            reqMinCycle[1] = req_cycle;
            baseReq[1] = dumpIdx1;
        }
        if ( respMinCycle[1] >  resp_cycle && resp_cycle != 0){
            respMinCycle[1] = resp_cycle;
            baseResp[1] = dumpIdx1;
        }

        if ( ++dumpIdx1 == TraceSz){
            doneTrace1 = true;
        }
        pthread_mutex_unlock(&mutex);
    }

  
	SorterIndication(unsigned int id) : SorterIndicationWrapper(id){dumpIdx0=0; dumpIdx1=0;}
private:
    uint32_t dumpIdx0;
    uint32_t dumpIdx1;
};

void doMergeTrace(uint32_t ctrId){
    uint32_t i = 0, j = 0, total=0;
    fprintf(stderr, "DRAM Cntr 0 Trace::::\n");
    fprintf(stderr, "%25s|%25s|%25s|%25s|%25s\n", "req_cycle", "req_addr", "req_rnw", "resp_cycle", "resp_addr");
    while ( (i < TraceSz || j < TraceSz) && total < TraceSz*2){
        uint32_t idx_i = (i + baseReq[ctrId])%TraceSz;
        uint32_t idx_j = (j + baseResp[ctrId])%TraceSz;
        if ( reqCycle[ctrId][idx_i] < respCycle[ctrId][idx_j] ) {
            fprintf(stderr, "%25lu|%25lu|%25u|%25s|%25s\n", reqCycle[ctrId][idx_i], reqAddr[ctrId][idx_i], reqRNW[ctrId][idx_i],
                    "", "");
            i++;
        } else if ( reqCycle[ctrId][idx_i] < respCycle[ctrId][idx_j] ) {
            fprintf(stderr, "%25s|%25s|%25s|%25lu|%25lu\n", "","","",respCycle[ctrId][idx_j], respAddr[ctrId][idx_j]);
            j++;
        } else {
            fprintf(stderr, "%25lu|%25lu|%25u|%25lu|%25lu\n", reqCycle[ctrId][idx_i], reqAddr[ctrId][idx_i], reqRNW[ctrId][idx_i],
                    respCycle[ctrId][idx_j], respAddr[ctrId][idx_j]);
            i++;
            j++;
        }
        total++;
    }
}

int main(int argc, const char **argv){
    
    SorterRequestProxy *device = new SorterRequestProxy(IfcNames_SorterRequestS2H);
    SorterIndication testIndication(IfcNames_SorterIndicationH2S);

    if (pthread_mutex_init(&mutex, NULL)){
        fprintf(stderr, "failed to init mutex\n");
        return -1;
    }

  // if(sem_init(&done_sem, 1, 0)){
  //   fprintf(stderr, "failed to init done_sem\n");
  //   return -1;
  // }

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

  // uint32_t iterCnt = 0;

  while ( true ){
      pthread_mutex_lock(&mutex);
      if (done) {
          pthread_mutex_unlock(&mutex);
          break;
      }
      pthread_mutex_unlock(&mutex);
      // device->getStatus();
      // if (++iterCnt > 10)
          // break;
#ifdef SIMULATION
      sleep(10);
#else
      usleep(1000);
#endif
  }

  device->getDramCntrsDump();
  while( true ) {
      pthread_mutex_lock(&mutex);
      if (doneTrace0 && doneTrace1) {
          pthread_mutex_unlock(&mutex);
          break;
      }
      pthread_mutex_unlock(&mutex);
  }
  doMergeTrace(0);
  doMergeTrace(1);
  device->getDramSorterStatus();
  device->getDramCntrStatus();

  sleep(1);
  pthread_mutex_destroy(&mutex);

  return 0;
}
