#include "flashmanage.h"
#include "issp_programmer.h"
#include "ISSPDebug.h"
#include "ISSPIndication.h"
#include "pageaddr_feeder.h"
#include "colfileloader.h"
#include <string.h>
#include <stdio.h>
#include "TableTasks.h"
// #include "TableTasks2.h"
#include <iostream>
#include <chrono>


char * sprintf_int128( __int128_t n ) {
    static char str[41] = { 0 };        // sign + log10(2**128) + '\0'
    char *s = str + sizeof( str ) - 1;  // start at the end
    bool neg = n < 0;
    if( neg )
        n = -n;
    do {
        *--s = "0123456789"[n % 10];    // save last digit
        n /= 10;                // drop it
    } while ( n );
    if( neg )
        *--s = '-';
    return s;
}

void print(const AggrRespTransport v){
    __int128 sum = ((__int128)v.sum_hi)<<64 | (__int128)v.sum_lo;
    std::cout << "Aggregate sum = " << sprintf_int128(sum) << std::endl;
    __int128 min = ((__int128)v.min_hi)<<64 | (__int128)v.min_lo;
    std::cout << "Aggregate min = " << sprintf_int128(min) << std::endl;
    __int128 max = ((__int128)v.max_hi)<<64 | (__int128)v.max_lo;
    std::cout << "Aggregate max = " << sprintf_int128(max) << std::endl;
    std::cout << "Aggregate cnt = " << v.cnt << std::endl;
}

pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
bool doneflag = false;
bool doneTrace = false;

// sem_t test_sem;

#define PageBufTraceSz 1024
uint8_t		resTagArr[PageBufTraceSz];
uint64_t	resCycArr[PageBufTraceSz];
uint8_t		relTagArr[PageBufTraceSz];
uint64_t	relCycArr[PageBufTraceSz];

class ISSPIndication : public ISSPIndicationWrapper{
public:	
    virtual void aggrResp ( const uint8_t colId, const AggrRespTransport v ){
        fprintf(stderr, "colId = %d received aggrResp\n", colId);
        print(v);
		dones++;
		fprintf(stderr, "dones = %u\n", dones);
		if (dones == 4){
			pthread_mutex_lock(&mutex);
			doneflag = true;
			pthread_mutex_unlock(&mutex);
		};
    }

	virtual void trace_PageBuf (const uint8_t resTag, const uint64_t resCycle,
								const uint8_t relTag, const uint64_t relCycle ){
        fprintf(stderr, "trace_PageBuf, idx = %5lu resTag = %3u, @ %32lu; relTag = %3u, @ %32lu\n",traceIdx, (uint32_t)resTag, resCycle, (uint32_t)relTag, relCycle);
		pthread_mutex_lock(&mutex);
		resTagArr[traceIdx] = resTag;
		resCycArr[traceIdx] = resCycle;
		relTagArr[traceIdx] = relTag;
		relCycArr[traceIdx] = relCycle;
		if ( ++traceIdx == PageBufTraceSz){
			doneTrace = true;
		}
		pthread_mutex_unlock(&mutex);
    }
	
    ISSPIndication(unsigned int id) : ISSPIndicationWrapper(id){dones=0;traceIdx=0;}
private:
	uint32_t dones;
	uint64_t traceIdx;
};


void doMergeTrace(){
	uint32_t i = 0, j = 0;
	uint64_t lastCyc_res = 0, lastCyc_rel = 0;;
	
	fprintf(stderr, "%25s|%25s|%25s|%25s|\n", "cycle delta tag res", "reserveTag", "cycle delta tag res", "releaseTag");
	while ( i < PageBufTraceSz || j < PageBufTraceSz){
		if ( resCycArr[i] < relCycArr[j] ) {
			fprintf(stderr, "%25lu|%25u|%25s|%25s|\n", resCycArr[i] - lastCyc_res, (uint32_t)resTagArr[i], "", "");
			lastCyc_res = resCycArr[i];
			i++;
		} else if ( resCycArr[i] > relCycArr[j] ) {
			fprintf(stderr, "%25s|%25s|%25lu|%25u|\n", "",  "", relCycArr[j] - lastCyc_rel, (uint32_t)relTagArr[j]);
			lastCyc_rel = relCycArr[j];
			j++;
		} else {
			fprintf(stderr, "%25lu|%25u|%25lu|%25u|\n", resCycArr[i] - lastCyc_res, (uint32_t)resTagArr[i], resCycArr[i] - lastCyc_rel ,(uint32_t)relTagArr[j]);
			lastCyc_res = resCycArr[i];
			lastCyc_rel = resCycArr[i];
			i++;
			j++;
		}
	}
}

int main(){
    FlashManager* fmng = new FlashManager("testdir");

    ISSPProgrammer* issp_programmer = new ISSPProgrammer();
    ISSPIndication* issp_indication = new ISSPIndication(IfcNames_ISSPIndicationH2S);

	ISSPDebugProxy* debug = new ISSPDebugProxy(IfcNames_ISSPDebugS2H);

	write_col_files(fmng, "filelist.txt", db_path);

	bool done = false;
	

	size_t size;
	std::chrono::high_resolution_clock::time_point tm_0 = std::chrono::high_resolution_clock::now();
	std::chrono::high_resolution_clock::time_point tm_1;
	issp_programmer->sendTableTask(&task, fmng, size);
	while (true){
		pthread_mutex_lock(&mutex);
		if (doneflag) {
			pthread_mutex_unlock(&mutex);
			break;
		}
		else {
			pthread_mutex_unlock(&mutex);
		}
	}
	tm_1 = std::chrono::high_resolution_clock::now();
	auto duration = tm_1-tm_0;
	auto secs = std::chrono::duration_cast<std::chrono::seconds>(duration).count();
	auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
	fprintf(stderr, "Time lapsed = %lu secs (%lu ms)\n", secs, millis);
	fprintf(stderr, "Total data read = %lu MB)\n", size/(1UL<<20));
	fprintf(stderr, "Effective data bandwidth = %lu MB/s)\n", size/millis/1000);

	sleep(1);


    debug->dumpTrace_PageBuf();

	while(true){
		pthread_mutex_lock(&mutex);
		if (doneTrace) {
			pthread_mutex_unlock(&mutex);
			break;
		}
		else {
			pthread_mutex_unlock(&mutex);
		}
	};

	doMergeTrace();

	sleep(1);

    delete fmng;
	delete issp_programmer;
    delete issp_indication;
}
