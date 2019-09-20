#include <vector>
#include <stdlib.h>
#include <time.h>
#include <assert.h>
#include <stdint.h>
#include <algorithm>
#include <functional>
#include <stdio.h>

std::vector<uint32_t> inputBuf0;
bool init0 = false;
uint32_t total0 = 0;
std::vector<uint32_t> inputBuf1;
bool init1 = false;
uint32_t total1 = 0;

extern "C" {
	void genSortedSeq0(uint32_t size, bool descending){
		srand(time(NULL));
		inputBuf0.clear();
		for ( uint32_t i = 0; i < size; i++){
			inputBuf0.push_back(rand());
		}
		if ( descending ) 
			std::sort(inputBuf0.begin(), inputBuf0.end(), std::greater<uint32_t>());
		else
			std::sort(inputBuf0.begin(), inputBuf0.end());
		fprintf(stdout, "getnSortedSeq0, size = %u, vec.size = %lu\n", size, inputBuf0.size());
	}

	uint32_t getNextData0(uint32_t size,bool descending, uint32_t offset, uint32_t gear){
		// fprintf(stdout, "getNextData0, size = %u, descending = %u, offset = %u, gear = %u\n", size, descending, offset, gear);
		if ( !init0 ) {
			genSortedSeq0(size, descending);
			init0 = true;
		}
		assert(gear+offset<inputBuf0.size());
		total0++;
		if ( total0==inputBuf0.size()) {
			init0=false;
			total0=0;
			fprintf(stdout, "reset for newseq 0, size = %u, descending = %u, offset = %u, gear = %u\n", size, descending, offset, gear);
		}
		return inputBuf0[gear+offset];
	}

	void genSortedSeq1(uint32_t size, bool descending){
		srand(time(NULL));
		inputBuf1.clear();
		for ( uint32_t i = 0; i < size; i++){
			inputBuf1.push_back(rand());
		}
		if ( descending ) 
			std::sort(inputBuf1.begin(), inputBuf1.end(), std::greater<uint32_t>());
		else
			std::sort(inputBuf1.begin(), inputBuf1.end());
		fprintf(stdout, "getnSortedSeq1, size = %u, vec.size = %lu\n", size, inputBuf1.size());
	}

	uint32_t getNextData1(uint32_t size, bool descending, uint32_t offset, uint32_t gear){
		// fprintf(stdout, "getNextData1, size = %u, descending = %u, offset = %u, gear = %u\n", size, descending, offset, gear);
		if ( !init1 ) {
			genSortedSeq1(size, descending);
			init1 = true;
		}
		assert(gear+offset<inputBuf1.size());
		total1++;
		if ( total1==inputBuf1.size()) {
			init1=false;
			total1=0;
			fprintf(stdout, "reset for newseq 1, size = %u, descending = %u, offset = %u, gear = %u\n", size, descending, offset, gear);
		}
		return inputBuf1[gear+offset];
	}
}
