#include "pageaddr_feeder.h"
#include <algorithm>

bool				PageAddrFeeder::devInit		= false;
PageFeederProxy*	PageAddrFeeder::page_feeder = NULL;


PageAddrFeeder::PageAddrFeeder(){
    if ( !devInit ){
        page_feeder = new PageFeederProxy(IfcNames_PageFeederS2H);
		page_feeder->pint.busyType = BUSY_ERROR; // return error when fifo is full
        devInit     = true;
    }
}


PageAddrFeeder::~PageAddrFeeder(){
    if ( devInit ){
        delete page_feeder;
        page_feeder = NULL;
        devInit     = false;
    }
}


typedef struct {
	int*			fds;
	uint64_t*		fss;
	FlashManager*	fmng;
	bool*			done;
	uint32_t*       gear;
} WorkerInfo;

#define CaseMarco(colId, pgAddr, last) case colId:			\
	retval = page_feeder->sendPageAddr_##colId(pgAddr, last);	\
	break


int inline PageAddrFeeder::sendToFPGA(uint8_t colId, uint32_t pageAddr, bool last){
	int retval = 1;
	switch (colId){
		CaseMarco(0,  pageAddr, last);
		CaseMarco(1,  pageAddr, last);
		CaseMarco(2,  pageAddr, last);
		CaseMarco(3,  pageAddr, last);
		CaseMarco(4,  pageAddr, last);
		CaseMarco(5,  pageAddr, last);
		CaseMarco(6,  pageAddr, last);
		CaseMarco(7,  pageAddr, last);
		CaseMarco(8,  pageAddr, last);
		CaseMarco(9,  pageAddr, last);
		CaseMarco(10, pageAddr, last);
		CaseMarco(11, pageAddr, last);
	default:
		break;
	}
	return retval;
}

void *PageAddrFeeder::sender_thread(void* args){
	
	int*			fds	 = ((WorkerInfo*)args)->fds;
	uint64_t*		fss	 = ((WorkerInfo*)args)->fss;
	FlashManager*	fmng = ((WorkerInfo*)args)->fmng;
	bool*			done = ((WorkerInfo*)args)->done;
	uint32_t*		gear = ((WorkerInfo*)args)->gear;

	uint64_t offsets[NUM_SELS+NUM_COLS];

	uint32_t colDones = 0, valids = 0;

	for ( uint32_t i = 0; i < NUM_SELS+NUM_COLS; i++ ) {
		offsets[i] = 0;
		if (fds[i] != -1) valids++;
	}
	uint8_t colId = 0;
	while ( true ) {
		if ( colDones == valids ) break;
		if ( fds[colId] == -1 ){
			// fprintf(stderr, "skipping colId = %u\n", (uint32_t)colId);
			colId = (colId + 1) % (NUM_SELS+NUM_COLS);
			continue;
		}

		if ( offsets[colId] < fss[colId] ){
			// for ( int i = 0; i < colBytes
			uint32_t pgAddr = fmng->getPhysPageAddr(fds[colId], offsets[colId]);
			if ( sendToFPGA(colId, pgAddr, offsets[colId]+8192>=fss[colId]) == 0 ) {
				// fprintf(stderr, "sending colId = %u succeeded\n", (uint32_t)colId);
				offsets[colId]+=8192;
				if ( offsets[colId] >= fss[colId] ) colDones++;
			}
			else {
				// fprintf(stderr, "sending colId = %u failed\n", (uint32_t)colId);
				// if ( colId < NUM_SELS ){
				// 	colId++;
				// 	continue;
				// }
			}
		}
		
		if ( (offsets[colId] >> 13) % gear[colId] == 0 || offsets[colId] >= fss[colId]){
			colId = (colId + 1) % (NUM_SELS+NUM_COLS);
		}
	}
	*done = true;
	fprintf(stderr, "PageAddr Sender thread exits\n");
	return 0;
}

int PageAddrFeeder::sendTableTask(TableTask* task, FlashManager* fmng, bool *doneSending, size_t & totalBytes){
	int*		fds	= new int[NUM_SELS+NUM_COLS];
    uint64_t*	fss = new uint64_t[NUM_SELS+NUM_COLS];
	uint32_t*   gear = new uint32_t[NUM_SELS+NUM_COLS];
	uint32_t    mingear = 16;
	totalBytes = 0;
	for ( uint8_t i = 0; i < NUM_SELS; i++){
		if ( !task->rowSels[i].param.forward ) {
			fds[i] = fmng->openfile(task->rowSels[i].filename);
			fss[i] = (task->numRows)<<((uint32_t)(task->rowSels[i].param.colType));
			totalBytes+=fss[i];
			gear[i] = 1U<<((uint32_t)(task->rowSels[i].param.colType));
			// gear[i] = 64;
			mingear = std::min(gear[i], mingear);
			fprintf(stderr, "Selector:: processing column (%s),  file (%s)  (%lu B) \n",
					task->rowSels[i].colname.c_str(), task->rowSels[i].filename.c_str(), fss[i]);
			if ( fds[i] == -1 ){
				fprintf(stderr, "Selector:: column (%s),  openfile (%s) failed\n",
						task->rowSels[i].colname.c_str(), task->rowSels[i].filename.c_str());
				return 1;
			}
			if ( fss[i] > fmng->filesize(fds[i]) ) {
				fprintf(stderr, "Selector:: column (%s) has file (%s) of smaller length (%lu B) than needed (%lu B) \n",
						task->rowSels[i].colname.c_str(), task->rowSels[i].filename.c_str(), fmng->filesize(fds[i]), fss[i]);
				return 1;
			}
		} else {
			fds[i] = -1;
			gear[i] = 16;
		}
	}

	for ( uint8_t i = 0; i < NUM_COLS; i++){
		uint8_t idx = i+NUM_SELS;
		if ( i < task->numInCols ) {
			fds[idx] = fmng->openfile(task->inCols[i].filename);
			fss[idx] = (task->numRows)<<((uint32_t)(task->inCols[i].param.colType));
			totalBytes+=fss[idx];
			gear[idx] = 1U<<((uint32_t)(task->inCols[i].param.colType));
			mingear = std::min(gear[idx], mingear);
			fprintf(stderr, "ColProc:: processing column (%s),  file (%s)  (%lu B) \n",
					task->inCols[i].colname.c_str(), task->inCols[i].filename.c_str(), fss[idx]);
			if ( fds[idx] == -1 ){
				fprintf(stderr, "ColProc:: processing column (%s),  openfile (%s) failed\n",
						task->inCols[i].colname.c_str(), task->inCols[i].filename.c_str());
				return 1;
			}
			if ( fss[idx] > fmng->filesize(fds[idx]) ) {
				fprintf(stderr, "ColProc:: column (%s) has file (%s) of smaller length (%lu B) than needed (%lu B) \n",
						task->inCols[i].colname.c_str(), task->inCols[i].filename.c_str(), fmng->filesize(fds[idx]), fss[idx]);
				return 1;
			}
		} else {
			fds[idx] = -1;
			gear[idx] = 16;
		}
	}

	for ( uint8_t i = 0; i < NUM_SELS+NUM_COLS; i++ ){
		gear[i]/=mingear;
		fprintf(stderr, "Gear[%u] = %u\n", i, gear[i]);
	}

	pthread_t* senderThread = new pthread_t;

	WorkerInfo* args = new WorkerInfo;
	args->fds  = fds;
	args->fss  = fss;
	args->fmng = fmng;
	args->done = doneSending;
	args->gear = gear;
	
	int ret = pthread_create(senderThread, NULL, PageAddrFeeder::sender_thread, (void*)args);
	
	if(ret != 0) {
		printf("Error: pthread_create() failed\n");
		return 1;
	}
	return 0;
	
}

