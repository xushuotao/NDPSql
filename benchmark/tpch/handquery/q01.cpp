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
#include "gdk_cand.h"

size_t getFilesize(const char* filename) {
  struct stat st;
  stat(filename, &st);
  return st.st_size;
}

typedef struct {
  int fd;
  size_t fs;
  void* base;
}  FRec;

FRec* mapfile(const char* fname){
  FRec *frec = new FRec;
  frec->fd = open(fname, O_RDONLY, 0);
  frec->fs = getFilesize(fname);
  assert((frec->fd)!=-1);
  frec->base = mmap(NULL, frec->fs, PROT_READ, MAP_SHARED, frec->fd, 0);
  assert((frec->base)!=MAP_FAILED);
  return frec;
}

void unmapfile(FRec* frec){
  int rc = munmap(frec->base, frec->fs);
  assert(rc==0);
  close(frec->fd);
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

gdk_return group(bte* column, BUN colsz, const BAT* s, BAT* inGroup,
                 BAT** groups, BAT** extents, BAT** histo){

  oid *restrict ngrps, ngrp, prev = 0, hseqb = 0;
  oid *restrict exts = NULL;
  lng *restrict cnts = NULL;

  BUN p, q, r;


  BUN maxgrps = (BUN) 1 << 8;

  BUN start, end, cnt;
  const oid *restrict cand, *candend;

  start = 0;
  end = colsz;

  if ( s ){
	cand = (const oid *) Tloc((s), 0);
    candend = (const oid *) Tloc((s), BATcount(s));
  }

  cnt = s ? (BUN) (candend - cand) : end - start;

  fprintf(stderr, "group, cnt = %lu, s count = %lu\n", cnt, BATcount(s));
        
  BAT* gn = COLnew(0, TYPE_oid, cnt, TRANSIENT);
  if (gn == NULL) return GDK_FAIL;
  *groups = gn;
  ngrps = (oid *) Tloc(gn, 0);

  
  BAT* en = COLnew(0, TYPE_oid, maxgrps, TRANSIENT);
  if (en == NULL) return GDK_FAIL;
  *extents = en;
  exts = (oid *) Tloc(en, 0);

  
  BAT* hn = COLnew(0, TYPE_lng, maxgrps, TRANSIENT);
  if (hn == NULL) return GDK_FAIL;
  *histo = hn;
  cnts = (lng *) Tloc(hn, 0);
  memset(cnts, 0, maxgrps * sizeof(lng));

  unsigned char *restrict bgrps =  (unsigned char *)GDKmalloc(256);
  const unsigned char *restrict w = (const unsigned char *)column;
  unsigned char v;
  if (bgrps == NULL) return GDK_FAIL;
  memset(bgrps, 0xFF, 256);
  
  ngrp = 0;
  gn->tsorted = 1;
  r = 0;
  for (;;) {
    if (s) {
      if (cand == candend)
        break;
      p = *cand++;
    } else {
      p = start++;
    }
    if (p >= end)
      break;
    if ((v = bgrps[w[p]]) == 0xFF && ngrp < 256) {
      fprintf(stderr, "new group v = %x, grpid = %lx\n", v, ngrp);
      bgrps[w[p]] = v = (unsigned char) ngrp++;
      if (extents)
        exts[v] = (oid) p;
    }
    ngrps[r] = v;
    if (r > 0 && v < ngrps[r - 1])
      gn->tsorted = 0;
    if (histo)
      cnts[v]++;
    r++;
  }

  BATsetcount(en, ngrp);
  BATsetcount(hn, ngrp);  
  GDKfree(bgrps);

  return GDK_SUCCEED;
  
}

std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
std::string shipdate = "10/1051";
std::string l_returnflag = "10/1047";
std::string l_linestatus = "10/1050";
size_t nRows = 1799989091;

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

  auto date_rec = mapfile(fname_shipdate.c_str());
  
  auto pos = select_date((int*)date_rec->base, nRows, INT_MIN, 729999);
  fprintf(stderr, "pos count = %lu, filter rate = (%lu/%lu) %.2f\n", pos->batCount, pos->batCount, nRows, (float)pos->batCount/(float)nRows*100.0);

  std::string fname_returnflag = db_path+l_returnflag+".tail";
  auto returnflag_rec = mapfile(fname_returnflag.c_str());

  BAT* grp, *ext, *hist;

  auto stat = group((bte*)(returnflag_rec->base), nRows, pos, NULL, &grp, &ext, &hist);
  assert(stat == GDK_SUCCEED);
  fprintf(stderr, "hist->cnt = %lu, ext->cnt = %lu\n", BATcount(hist), BATcount(ext));

  BATclear(pos,0);
  unmapfile(returnflag_rec);
  unmapfile(date_rec);
  return 0;
}

