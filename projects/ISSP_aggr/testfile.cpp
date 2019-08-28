#include "flashmanage.h"
#include "issp_programmer.h"
#include "ISSPIndication.h"
#include <string.h>
#include <stdio.h>
#include "TableTasks.h"
#include <iostream>

#if defined(SIMULATION)
std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
#else
std::string db_path = "bat/";
#endif

std::string c_mktsegment = "03/344";	 // varchar 8-byte
std::string c_custkey	 = "04/425";	 //int

std::string o_custkey	= "07/755";		 // int
std::string o_orderdate = "07/746";		 // int


#if defined(SIMULATION)
size_t	rows_customers = 450000;
size_t	rows_orders    = 4500000;
#else
size_t	rows_customers = 45000000;
size_t	rows_orders    = 450000000;

#endif

read_cb cb_array[128];




void check_read_data(FlashManager* fmng, std::string fname, void* ref_array){
	int fd = fmng->openfile(fname.c_str());

	size_t	fs = fmng->filesize(fd);

	fprintf(stderr, "%s file is of size %lu bytes\n", fname.c_str(), fs);


	// for ( int i = 0; i < 128; i++ ) cb_array[i].busy = false;

	size_t	req_offset = 0;
	size_t	processed  = 0;

	int bufid = 0;  
	while ( processed < fs ) {

		// sending reqs
		// fprintf(stderr, "loopping:: req_offset = %lu, bufid = %d, processed= %lu\n", req_offset, bufid, processed);
		if ( req_offset < fs && !cb_array[bufid].busy ){
			cb_array[bufid].fildes	= fd;
			cb_array[bufid].offset	= req_offset;
			if ( fmng->aio_read_page(cb_array+bufid) ) {
				req_offset		   += PAGE_SIZE;
			}
		}
		bufid=(bufid+1)%128;

		// checking resps
		for ( int i = 0; i < 128; i++ ){
			if ( fmng->aio_return(cb_array+i) ){
				size_t	offset																						  = cb_array[i].offset;
				if ( memcmp(cb_array[i].buf_ptr, (char*)(ref_array) + offset, offset+8192 > fs ? fs - offset : 8192) != 0 ) {
					fprintf(stderr, "LOG::page comparasion error of file %s, at offset = %lu, pageNum = %lu\n",fname.c_str(), offset, offset/8192);
					exit(0);
				}
				else {
					// fprintf(stderr, "LOG::page comparasion success of file %s, at offset = %lu\n",fname.c_str(), cb_array[i].offset);
				}
				fmng->aio_done(cb_array+i);
				processed += 8192;
			}
		}

		// fprintf(stderr, "loopping:: end\n");
	}
	fprintf(stderr, "file %s read test passed\n", fname.c_str());
	fmng->closefile(fd);


}

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

class ISSPIndication : public ISSPIndicationWrapper{
public:
	virtual void aggrResp ( const uint8_t colId, const AggrRespTransport v ){

		fprintf(stderr, "colId = %d received aggrResp\n", colId);
		print(v);
		
	}
    ISSPIndication(unsigned int id) : ISSPIndicationWrapper(id){}
};



int main(){
	// FlashManager* fmng = new FlashManager("testdir");
	// printf("fmng		  = %p\n",fmng);

	ISSPProgrammer* issp = new ISSPProgrammer();

	ISSPIndication* issp_indication = new ISSPIndication(IfcNames_ISSPIndicationH2S);
	issp->sendTableTask(&task);

	while (true){}

	// delete fmng;
	delete issp;
	//delete issp_indication;
}
