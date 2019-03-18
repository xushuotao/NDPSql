#include <vector>
#include <string>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <assert.h>
#include <limits.h>
#include <omp.h>
#include <chrono>
#include <ctime>

#include "monetdb_config.h"
#include "gdk/gdk.h"

#include "gdk/gdk_bbp.h"


std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
std::string shipdate = "10/1051";
std::string l_returnflag = "10/1047";
std::string l_linestatus = "10/1050";
size_t nRows = 1799989091;

size_t getFilesize(const char* filename) {
  struct stat st;
  stat(filename, &st);
  return st.st_size;
}

BAT* select_date(int* column, size_t count, int lv, int hv){
  // std::vector<size_t>* localv = new std::vector<size_t>[omp_get_max_threads()];
  // std::vector<size_t> localcnt = std::vector<size_t>(omp_get_max_threads(),0);
  size_t cap = count;
  BAT* bn = COLnew(0, TYPE_oid, cap, TRANSIENT);
  oid* w = (oid*)(bn->theap.base);
  auto t_start = std::chrono::high_resolution_clock::now();
  BUN p = 0;
  fprintf(stderr, "bn->batCapacity = %lu\n", bn->batCapacity);
// #pragma omp parallel for
  for (size_t i = 0; i < count; i++ ){
    if ( column[i] >= lv && column[i] <= hv ) {
      if ( p + 1 == bn->batCapacity ) {
        gdk_return suc = BATextend(bn, (bn->batCapacity)+1024*1024);
        // assert(suc==GDK_SUCCEED);
        cap=(bn->batCapacity)+1024*1024;
        w = (oid*)(bn->theap.base);
        fprintf(stderr, "realloced\n");
      }
      // fprintf(stderr, "p = %lu, bn->batCapacity = %lu, heap_free = %lu, heap_size = %lu\n",p, bn->batCapacity, bn->theap.free, bn->theap.size);
      w[p++] = i;
      // p++;
      // localcnt[omp_get_thread_num()]++;
      // localv[omp_get_thread_num()].push_back(i);
    }
  }
  BATsetcount(bn, p);
  
  auto t_end = std::chrono::high_resolution_clock::now();
  size_t size = sizeof(int)*count;
  double t_diff = std::chrono::duration<double, std::milli>(t_end-t_start).count();
  fprintf(stderr, "I am here!!(p=%lu) Throughput = (%luMB/%lfms)%lfMB/s\n", p,  size/1024/1024, t_diff, (double)size/1024/t_diff);
  // std::vector<size_t> retval;
  // for ( int i = 0; i < omp_get_max_threads(); i++){
  //   fprintf(stderr, "merge %dth vector\n", i);
  //   if ( localv[i].size() > 0 )
  //     retval.insert(retval.end(), localv[i].begin(), localv[i].end());
  // }
  // //free(localv);
  return bn;
}

int main(){
  opt* set = NULL;
  int setlen = mo_builtin_settings(&set);
  char mem_size_c[1024];
  sprintf(mem_size_c, "%lu", 20*1024*1024*1024UL);
  setlen = mo_add_option(&set, setlen, opt_config, "gdk_mmap_minsize_transient", mem_size_c);
  mo_print_options(set, setlen);
  char *currdir = get_current_dir_name();
  char *dbpath = strcat(currdir, "/dbpath");
  GDKcreatedir(dbpath);
  BBPaddfarm(dbpath, 1 << PERSISTENT);
  BBPaddfarm(dbpath, 1 << TRANSIENT);
  GDKinit(set, setlen);
  std::string fname_shipdate = db_path+shipdate+".tail";
  int fd_shipdate = open(fname_shipdate.c_str(), O_RDONLY, 0);
  size_t fs_shipdate = getFilesize(fname_shipdate.c_str());
  assert(fd_shipdate!=-1);
  int* date_col = (int*) mmap(NULL, fs_shipdate, PROT_READ, MAP_SHARED, fd_shipdate, 0);
  assert(date_col!=MAP_FAILED);
  auto pos = select_date(date_col, nRows, INT_MIN, 729999);
  fprintf(stderr, "pos count = %lu, filter rate = (%lu/%lu) %.2f\n", pos->batCount, pos->batCount, nRows, (float)pos->batCount/(float)nRows*100.0);

  BATclear(pos,0);
  
  int rc = munmap((void*)date_col, fs_shipdate);
  assert(rc==0);
  close(fd_shipdate);
  return 0;
}

