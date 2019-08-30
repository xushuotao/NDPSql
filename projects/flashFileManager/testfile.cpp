#include "flashmanage.h"
#include <string.h>
#include <stdio.h>

#if defined(SIMULATION)
std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
#else
std::string db_path = "bat/";
#endif

std::string c_mktsegment = "03/344"; // varchar 8-byte
std::string c_custkey = "04/425"; //int

std::string o_custkey = "07/755"; // int
std::string o_orderdate = "07/746"; // int


#if defined(SIMULATION)
size_t rows_customers = 450000;
size_t rows_orders    = 4500000;
#else
size_t rows_customers = 45000000;
size_t rows_orders    = 450000000;

#endif

read_cb cb_array[128];




void check_read_data(FlashManager* fmng, std::string fname, void* ref_array){
  int fd = fmng->openfile(fname.c_str());

  size_t fs = fmng->filesize(fd);

  fprintf(stderr, "%s file is of size %lu bytes\n", fname.c_str(), fs);


  // for ( int i = 0; i < 128; i++ ) cb_array[i].busy = false;

  size_t req_offset = 0;
  size_t processed = 0;

  int bufid = 0;  
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
        size_t offset = cb_array[i].offset;
        if ( memcmp(cb_array[i].buf_ptr, (char*)(ref_array) + offset, offset+8192 > fs ? fs - offset : 8192) != 0 ) {
          fprintf(stderr, "LOG::page comparasion error of file %s, at offset = %lu, pageNum = %lu\n",fname.c_str(), offset, offset/8192);
          exit(0);
        }
        else {
          // fprintf(stderr, "LOG::page comparasion success of file %s, at offset = %lu\n",fname.c_str(), cb_array[i].offset);
        }
        fmng->aio_done(cb_array+i);
        processed+=8192;
      }
    }

    // fprintf(stderr, "loopping:: end\n");
  }
  fprintf(stderr, "file %s read test passed\n", fname.c_str());
  fmng->closefile(fd);


}


int main(){
  FlashManager* fmng = new FlashManager("testdir");
  printf("fmng = %p\n",fmng);
  std::string fname_c_custkey = db_path+c_custkey+".tail";
#ifndef SIMULATION
  std::string fname_c_mktsegment = db_path+c_mktsegment+".tail";
  std::string fname_o_custkey = db_path+o_custkey+".tail";
  std::string fname_o_orderdate = db_path+o_orderdate+".tail";
#endif  
  
  auto c_custkey_rec = mmapfile_readonly(fname_c_custkey.c_str());
#ifndef SIMULATION  
  auto c_mktsegment_rec = mmapfile_readonly(fname_c_mktsegment.c_str());
  auto o_custkey_rec = mmapfile_readonly(fname_o_custkey.c_str());
  auto o_orderdate_rec = mmapfile_readonly(fname_o_orderdate.c_str());
#endif

  memset(cb_array, 0, sizeof(read_cb)*128);

  fmng->writefile(fname_c_custkey.c_str(), (const char*) c_custkey_rec->base, rows_customers*sizeof(int));
#ifndef SIMULATION
  fmng->writefile(fname_c_mktsegment.c_str(), (const char*) c_mktsegment_rec->base, rows_customers*sizeof(int));
  fmng->writefile(fname_o_custkey.c_str(), (const char*) o_custkey_rec->base, rows_orders*sizeof(int));
  fmng->writefile(fname_o_orderdate.c_str(), (const char*) o_orderdate_rec->base, rows_orders*sizeof(int));
#endif

  check_read_data(fmng, fname_c_custkey, c_custkey_rec->base);
#ifndef SIMULATION
  check_read_data(fmng, fname_c_mktsegment, c_mktsegment_rec->base);
  check_read_data(fmng, fname_o_custkey, o_custkey_rec->base);
  check_read_data(fmng, fname_o_orderdate, o_orderdate_rec->base);
#endif
  

  unmmapfile(c_custkey_rec);
#ifndef SIMULATION  
  unmmapfile(c_mktsegment_rec);
  unmmapfile(o_custkey_rec);
  unmmapfile(o_orderdate_rec);
#endif

  delete fmng;
}
