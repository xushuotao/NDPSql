#include <functional>

#include "monetdb_config.h"
#include "gdk/gdk.h"
#include "gdk_private.h"

#include "gdk/gdk_bbp.h"
#include "gdk_cand.h"



size_t getFilesize(const char* filename);

typedef struct {
  int fd;
  size_t fs;
  void* base;
}  FRec;

FRec* mapfile(const char* fname);
void unmapfile(FRec* frec);

template<typename T>
BAT* select(T* column, size_t count, T lv, T hv);

gdk_return group(bte* column, BUN colsz, const BAT* s, BAT* g, BAT* e,
                 BAT** groups, BAT** extents, BAT** histo);


template<typename TO, typename TI>
gdk_return aggr_sum(const TI* col, BUN colsz, const BAT* s, const BAT* g, const BAT* hist, BAT** result);

template<typename T>
BAT* merge(const T* col1,  BUN colsz1, BAT* s1, const T* col2, BUN colsz2, BAT* s2, std::function<T(T,T)> mergefunc);
