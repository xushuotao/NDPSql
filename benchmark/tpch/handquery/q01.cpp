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
#include "gdk_private.h"

#include "gdk/gdk_bbp.h"
#include "gdk_cand.h"

#define GRPnotfound()                                           \
  do {                                                          \
    /* no equal found: start new group */                       \
    if (ngrp == maxgrps) {                                      \
      /* we need to extend extents and histo bats, */           \
      /* do it at most once */                                  \
      maxgrps = colsz;                                          \
      if (extents) {                                            \
        BATsetcount(en, ngrp);                                  \
        if (BATextend(en, maxgrps) != GDK_SUCCEED)              \
          goto error;                                           \
        exts = (oid *) Tloc(en, 0);                             \
      }                                                         \
      if (histo) {                                              \
        BATsetcount(hn, ngrp);                                  \
        if (BATextend(hn, maxgrps) != GDK_SUCCEED)              \
          goto error;                                           \
        cnts = (lng *) Tloc(hn, 0);                             \
      }                                                         \
    }                                                           \
    if (extents)                                                \
      exts[ngrp] = hseqb + p;                                   \
    if (histo)                                                  \
      cnts[ngrp] = 1;                                           \
    fprintf(stderr, "new group = %lu @ r = %lu\n", ngrp, r);    \
    ngrps[r] = ngrp++;                                          \
  } while (0)


#define GRP_create_partial_hash_table_core(INIT_1,HASH,COMP,ASSERT,GRPTST) \
  do {                                                                  \
    if (cand) {                                                         \
      fprintf(stderr, "partial_ht cnt = %lu\n",cnt);                    \
      for (r = 0; r < cnt; r++) {                                       \
        /*if (r%1000000 == 0) fprintf(stderr, "partial_ht r = %lu\n",r);*/ \
        p = cand[r];                                                    \
        assert(p < end);                                                \
        INIT_1;                                                         \
        prb = HASH;                                                     \
        for (hb = HASHget(hs, prb);                                     \
             hb != HASHnil(hs) && hb >= start;                          \
             hb = HASHgetlink(hs, hb)) {                                \
          ASSERT;                                                       \
          q = r;                                                        \
          while (q != 0 && cand[--q] > hb)                              \
            ;                                                           \
          if (cand[q] != hb)                                            \
            continue;                                                   \
          /*q = hb - start;*/                                           \
          GRPTST(q, r);                                                 \
          grp = ngrps[q];                                               \
          if (COMP) {                                                   \
            ngrps[r] = grp;                                             \
            if (histo)                                                  \
              cnts[grp]++;                                              \
            if (gn->tsorted &&                                          \
                grp != ngrp - 1)                                        \
              gn->tsorted = 0;                                          \
            break;                                                      \
          }                                                             \
        }                                                               \
        if (hb == HASHnil(hs) || hb < start) {                          \
          GRPnotfound();                                                \
          /* enter new group into hash table */                         \
          HASHputlink(hs, p, HASHget(hs, prb));                         \
          HASHput(hs, prb, p);                                          \
        }                                                               \
      }                                                                 \
    } else {                                                            \
      fprintf(stderr, "I don't think there is a candlist, cnt = %lu\n", cnt); \
      for (r = 0; r < cnt; r++) {                                       \
        p = start + r;                                                  \
        assert(p < end);                                                \
        INIT_1;                                                         \
        prb = HASH;                                                     \
        /*if ( r % 10000000 == 0) fprintf(stderr, "r = %lu, p = %lu, b[p] = %lx, grps[r] = %lx, prb = %lx\n", r, p, (unsigned long int)(bbb[p]), grps[r], prb);*/ \
        for (hb = HASHget(hs, prb);                                     \
             hb != HASHnil(hs) && hb >= start;                          \
             hb = HASHgetlink(hs, hb)) {                                \
          ASSERT;                                                       \
          GRPTST(hb - start, r);                                        \
          grp = ngrps[hb - start];                                      \
          if (COMP) {                                                   \
            ngrps[r] = grp;                                             \
            if (histo)                                                  \
              cnts[grp]++;                                              \
            if (gn->tsorted &&                                          \
                grp != ngrp - 1)                                        \
              gn->tsorted = 0;                                          \
            break;                                                      \
          }                                                             \
        }                                                               \
        if (hb == HASHnil(hs) || hb < start) {                          \
          GRPnotfound();                                                \
          /* enter new group into hash table */                         \
          HASHputlink(hs, p, HASHget(hs, prb));                         \
          HASHput(hs, prb, p);                                          \
        }                                                               \
      }                                                                 \
    }                                                                   \
  } while (0)

#define NOGRPTST(i, j)	(void) 0

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

gdk_return group(bte* column, BUN colsz, const BAT* s, BAT* g, BAT* e,
                 BAT** groups, BAT** extents, BAT** histo){

  const oid *grps = NULL;
  oid *restrict ngrps, ngrp, prev = 0, hseqb = 0;
  oid *restrict exts = NULL;
  lng *restrict cnts = NULL;

  BUN p, q, r;


  BUN maxgrps = g ? ((BUN) 1 << 8) * BATcount(e) : (BUN) 1 << 8;

  BUN start, end, cnt;
  const oid *restrict cand, *candend;

  start = 0;
  end = colsz;

  if ( s ){
	cand = (const oid *) Tloc((s), 0);
    candend = (const oid *) Tloc((s), BATcount(s));
  }
  else {
    cand = NULL;
    candend = NULL;
  }

  cnt = cand ? (BUN) (candend - cand) : end - start;

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

  if (g && (!BATordered(g) || !BATordered_rev(g)))
    grps = (const oid *) Tloc(g, 0);

  oid maxgrp = oid_nil;	/* maximum value of g BAT (if subgrouping) */
  PROPrec *prop;
  if (g) {
    if (BATtdense(g))
      maxgrp = g->tseqbase + BATcount(g);
    else if (BATtordered(g))
      maxgrp = * (oid *) Tloc(g, BATcount(g) - 1);
    else {
      prop = BATgetprop(g, GDK_MAX_VALUE);
      if (prop)
        maxgrp = prop->v.val.oval;
    }
    if (maxgrp == 0)
      g = NULL; /* single group */
  }

  const bte *w = (bte *) column;//Tloc(b, 0);
  if ( !grps ) {
    unsigned char *restrict bgrps =  (unsigned char *)GDKmalloc(256);
    unsigned char v;
    if (bgrps == NULL) return GDK_FAIL;
    memset(bgrps, 0xFF, 256);
  
    ngrp = 0;
    gn->tsorted = 1;
    r = 0;
    for (;;) {
      if (cand) {
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

    BATsetcount(gn, r);
    BATsetcount(en, ngrp);
    BATsetcount(hn, ngrp);  
    GDKfree(bgrps);
  } else if ( maxgrps < 65536 ) {

    unsigned short *restrict sgrps = (unsigned short *)GDKmalloc(65536 * sizeof(short));
    unsigned short v;

    BUN probe;

    if (sgrps == NULL)
      goto error;
    memset(sgrps, 0xFF, 65536 * sizeof(short));
    
    ngrp = 0;
    gn->tsorted = 1;
    r = 0;
    for (;;) {
      if (cand) {
        if (cand == candend)
          break;
        p = *cand++;
      } else {
        p = start++;
      }
      if (p >= end)
        break;

      probe = (grps[r]<<8) | w[p];
      if ((v = sgrps[probe]) == 0xFFFF && ngrp < 65536) {
        fprintf(stderr, "new group v = %x, grpid = %lx, r=%lu, grps[r] = %lx, w[p] = %x \n", v, ngrp, r, grps[r], w[p]);
        sgrps[probe] = v = (unsigned short) ngrp++;
        if (extents)
          exts[v] =(oid) p;
      }
      ngrps[r] = v;
      if (r > 0 && v < ngrps[r - 1])
        gn->tsorted = 0;
      if (histo)
        cnts[v]++;
      r++;
    }
    GDKfree(sgrps);
    BATsetcount(gn, r);
    BATsetcount(en, ngrp);
    BATsetcount(hn, ngrp);  
  }
  else {
    //     if (grps && maxgrp != oid_nil
    // #if SIZEOF_OID == SIZEOF_LNG
    //         && maxgrp < ((oid) 1 << (SIZEOF_LNG * 8 - 8))
    // #endif
    //         )
    //       {

    fprintf(stderr, "supplied group in\n");
    char nme[20] = "grp_hashtable";
    size_t nmelen = strlen(nme);
    BUN mask = MAX(HASHmask(cnt), 1 << 16);
    BUN hb;      
    Heap* hp = (Heap*) GDKzalloc(sizeof(Heap));
    hp->farmid = BBPselectfarm(TRANSIENT, TYPE_bte, hashheap);
    hp->filename = (char*) GDKmalloc(nmelen + 30);
    snprintf(hp->filename, nmelen + 30,
             "%s.hash" SZFMT, nme, MT_getpid());


    Hash *hs = HASHnew(hp, TYPE_bte, s ? BATcount(s): colsz,
                       mask, BUN_NONE);

    BUN prb;
    oid grp;

    ulng v;

    fprintf(stderr, "creating partial hash table core....\n");

    GRP_create_partial_hash_table_core(
                                       (void) 0,
                                       (v = ((ulng)grps[r]<<8)|(unsigned char)w[p], hash_lng(hs, &v)),
                                       w[p] == w[hb] && grps[r] == grps[hb - start],
                                       (void) 0,
                                       NOGRPTST);

    fprintf(stderr, "done partial hash table core....\n");

      
    BATsetcount(gn, r);
    BATsetcount(en, ngrp);
    BATsetcount(hn, ngrp);  
    GDKfree(hp);
    GDKfree(hs);
    // } 

  }

  return GDK_SUCCEED;

 error:
  return GDK_FAIL;
  
}

std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
std::string shipdate = "10/1051";
std::string l_returnflag = "10/1047";
std::string l_linestatus = "10/1050";
size_t nRows = 1799989091;
// size_t nRows = 100000;


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

  BAT* grp_rf, *ext_rf, *hist_rf;

  auto stat = group((bte*)(returnflag_rec->base), nRows, pos, NULL, NULL,  &grp_rf, &ext_rf, &hist_rf);
  assert(stat == GDK_SUCCEED);
  fprintf(stderr, "grp->cnt = %lu, hist->cnt = %lu, ext->cnt = %lu\n", BATcount(grp_rf), BATcount(hist_rf), BATcount(ext_rf));

  std::string fname_linestatus = db_path+l_linestatus+".tail";
  auto linestatus_rec = mapfile(fname_linestatus.c_str());

  BAT* grp=NULL, *ext, *hist;

  stat = group((bte*)(linestatus_rec->base), nRows, pos, grp_rf, ext_rf, &grp, &ext, &hist);
  assert(stat == GDK_SUCCEED);
  fprintf(stderr, "grp->cnt = %lu, hist->cnt = %lu, ext->cnt = %lu\n", BATcount(grp), BATcount(hist), BATcount(ext));


  BATclear(pos,0);
  unmapfile(returnflag_rec);
  unmapfile(date_rec);
  return 0;
}

