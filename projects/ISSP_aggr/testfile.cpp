#include "flashmanage.h"
#include "issp_programmer.h"
#include "pageaddr_feeder.h"
#include "ISSPIndication.h"
#include <string.h>
#include <stdio.h>
#include "TableTasks.h"
#include <iostream>

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



read_cb cb_array[128];

void check_read_data(FlashManager* fmng, std::string fname, void* ref_array){
    int fd = fmng->openfile(fname.c_str());

    size_t  fs = fmng->filesize(fd);

    fprintf(stderr, "%s file is of size %lu bytes\n", fname.c_str(), fs);


    // for ( int i = 0; i < 128; i++ ) cb_array[i].busy = false;

    size_t  req_offset = 0;
    size_t  processed  = 0;

    int bufid = 0;
	bool badread_dectected = false;
    while ( processed < fs ) {

        // sending reqs
        // fprintf(stderr, "loopping:: req_offset = %lu, bufid = %d, processed= %lu\n", req_offset, bufid, processed);
        if ( req_offset < fs && !cb_array[bufid].busy ){
            cb_array[bufid].fildes = fd;
            cb_array[bufid].offset = req_offset;
            if ( fmng->aio_read_page(cb_array+bufid) ) {
                req_offset += PAGE_SIZE;
            }
        }
        bufid=(bufid+1)%128;

        // checking resps
        for ( int i = 0; i < 128; i++ ){
            if ( fmng->aio_return(cb_array+i) ){
                size_t  offset = cb_array[i].offset;
                if ( memcmp(cb_array[i].buf_ptr, (char*)(ref_array) + offset, offset+8192 > fs ? fs - offset : 8192) != 0 && !badread_dectected) {
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

void check_col_files(FlashManger* fmng, std::string list_name){
	std::ifstream file((dir_path+"/filemap.txt").c_str());
	std::string line;
	if ( file.good() ){
		std::string colname;
		std::string fileid;
		uint32_t colBytes;
		uint64_t numRows;
		while ( file >> colname >> fileid >> colBytes >> numRows ) {
			std::string filename = db_path+fileid+".tail";
			auto rec = mmapfile_readonly(filename.c_str());
			uint64_t fs = colBytes * numRows;
			assert(fs <= rec.fs);
			check_read_data(fmng, filename, rec->base);
		}
	}
	file.close();
}

void write_col_files(FlashManger* fmng, std::string list_name){
	std::ifstream file((dir_path+"/filemap.txt").c_str());
	std::string line;
	if ( file.good() ){
		std::string colname;
		std::string fileid;
		uint32_t colBytes;
		uint64_t numRows;
		while ( file >> colname >> fileid >> colBytes >> numRows ) {
			std::string filename = db_path+fileid+".tail";
			auto rec = mmapfile_readonly(filename.c_str());
			uint64_t fs = colBytes * numRows;
			assert(fs <= rec.fs);
			fmng->writefile(filename.c_str(), (const char*)rec->base, fs);
			unmmapfile(rec);
		}
	}
	file.close();
}



int main(){
    FlashManager* fmng = new FlashManager("testdir");
	
    ISSPProgrammer* issp_programmer = new ISSPProgrammer();
	PageAddrFeeder* issp_pagefeeder = new PageAddrFeeder();
    ISSPIndication* issp_indication = new ISSPIndication(IfcNames_ISSPIndicationH2S);
	
	bool done = false;

	write_col_files(fmng, "filelist.txt");
	check_col_files(fmng, "filelist.txt");

	// if ( issp_pagefeeder->sendTableTask(&task, fmng, &done) != 0 ){
	// 	return 1;
	// }
	// issp_programmer->sendTableTask(&task);

    // while (true){}


    // delete issp_programmer;
	// delete issp_pagefeeder;

	delete fmng;
}
