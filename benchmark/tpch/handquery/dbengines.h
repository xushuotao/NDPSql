#include <functional>

#include "monetdb_config.h"
#include "gdk/gdk.h"
#include "gdk_private.h"

#include "gdk/gdk_bbp.h"
#include "gdk_cand.h"

#ifdef TIME_WITH_SYS_TIME
# include <sys/time.h>
# include <time.h>
#else
# ifdef HAVE_SYS_TIME_H
#  include <sys/time.h>
# else
#  include <time.h>
# endif
#endif


typedef int date;
#define date_nil		((date) int_nil)
#define date_isnil(X)	((X) == date_nil)

/*
 * @- daytime
 * Daytime values are also stored as the number of milliseconds that
 * passed since the start of the day (i.e. midnight).
 */
typedef int daytime;
#define daytime_nil ((daytime) int_nil)
#define daytime_isnil(X) ((X) == daytime_nil)


/*
 * @- timestamp
 * Timestamp is implemented as a record that contains a date and a time (GMT).
 */
typedef union {
	lng alignment;
	struct {
#ifndef WORDS_BIGENDIAN
		daytime p_msecs;
		date p_days;
#else
		date p_days;
		daytime p_msecs;
#endif
	} payload;
} timestamp;
#define msecs payload.p_msecs
#define days payload.p_days


/*
 * @- rule
 * rules are used to define the start and end of DST. It uses the 25
 * lower bits of an int.
 */
typedef union {
	struct {
		unsigned int month:4,	/* values: [1..12] */
		 minutes:11,			/* values: [0:1439] */
		 day:6,					/* values: [-31..-1,1..31] */
		 weekday:4,				/* values: [-7..-1,1..7] */
		 empty:7;				/* rule uses just 32-7=25 bits */
	} s;
	int asint;					/* the same, seen as single value */
} rule;

/*
 * @- tzone
 * A tzone consists of an offset and two DST rules, all crammed into one lng.
 */
typedef struct {
	/* we had this as bit fields in one unsigned long long, but native
	 * sun CC does not eat that.  */
	unsigned int dst:1, off1:6, dst_start:25;
	unsigned int off2:7, dst_end:25;
} tzone;

extern tzone tzone_local;
extern timestamp *timestamp_nil;

#define timestamp_isnil(X) ts_isnil(X)
#define tz_isnil(z)   (get_offset(&(z)) == get_offset(tzone_nil))
#define ts_isnil(t)   ((t).days == timestamp_nil->days && (t).msecs == timestamp_nil->msecs)

date todate(int day, int month, int year);
int date_tostr(str *buf, int *len, const date *val);


// This is the end of time functions


size_t getFilesize(const char* filename);

typedef struct {
  int fd;
  size_t fs;
  void* base;
}  FRec;

FRec* mapfile(const char* fname);
void unmapfile(FRec* frec);

BAT* maptoBAT(FRec *frec, int tt,  size_t nRows);

template<typename T>
BAT* select(T* column, size_t count, T lv, T hv);


size_t count_pages(BAT* pos, size_t colBytes);


gdk_return group(bte* column, BUN colsz, const BAT* s, BAT* g, BAT* e,
                 BAT** groups, BAT** extents, BAT** histo);


template<typename TO, typename TI>
gdk_return aggr_sum(const TI* col, BUN colsz, const BAT* s, const BAT* g, const BAT* hist, BAT** result);

template<typename T>
BAT* merge(const T* col1,  BUN colsz1, BAT* s1, const T* col2, BUN colsz2, BAT* s2, std::function<T(T,T)> mergefunc);



