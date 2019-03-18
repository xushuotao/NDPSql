targets := q01

INC=common/stream common/options common/utils
INC_FLAGS=$(foreach d, $(INC), -I$d)

# GDK_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard gdk/*.c)))
GDK_SRCS = \
		gdk_select.c \
		gdk_calc.c \
		gdk_ssort.c \
		gdk_aggr.c \
		gdk_batop.c \
		gdk_search.c gdk_hash.c gdk_tm.c \
		gdk_orderidx.c \
		gdk_align.c gdk_bbp.c \
		gdk_heap.c gdk_utils.c \
		gdk_atoms.c \
		gdk_qsort.c \
		gdk_storage.c gdk_bat.c \
		gdk_delta.c gdk_cross.c gdk_system.c gdk_value.c \
		gdk_posix.c gdk_logger.c gdk_sample.c \
		gdk_group.c \
		gdk_imprints.c \
		gdk_join.c gdk_project.c \
		gdk_unique.c \
		gdk_interprocess.c \
		gdk_firstn.c

GDK_OBJS := $(patsubst %.c, %.o, $(GDK_SRCS))

COMMON_OPTION_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard common/options/*.c)))
COMMON_STREAM_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard common/stream/*.c)))
COMMON_UTILS_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard common/utils/*.c)))



$(COMMON_OPTION_OBJS): %.o : common/options/%.c
	gcc  -g -O2 -DHAVE_CONFIG_H -D_REENTRANT -Igdk -I. -I/common/options -DLIBMOPTIONS -c $< -fPIC -DPIC -o $@

$(COMMON_STREAM_OBJS): %.o : common/stream/%.c
	gcc  -g -O2 -DHAVE_CONFIG_H -D_REENTRANT -Igdk -I. -I/common/stream -DLIBSTREAM -c $< -fPIC -DPIC -o $@

$(COMMON_UTILS_OBJS): %.o : common/utils/%.c
	gcc  -g -O2 -DHAVE_CONFIG_H -D_REENTRANT -Igdk -I. -I/common/utils -DLIBUTILS -c $< -fPIC -DPIC -o $@


$(GDK_OBJS): %.o: gdk/%.c
	gcc  -g -O2 -DHAVE_CONFIG_H -DLIBGDK -D_REENTRANT -Igdk -I.$(INC_FLAGS) -c $< -fPIC -DPIC -o $@

# libbat.so : $(GDK_OBJS)
# 	gcc -shared  -fPIC -DPIC $(GDK_OBJS) -lm -lz -lbz2 -ldl  -g -O2 -pthread -pthread -o libbat.so

$(targets): %: %.cpp $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS)
	g++ -Igdk $(INC_FLAGS) -std=c++11 -fopenmp $@.cpp -o $@ $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS) -ldl -lz -lbz2 -lssl -lcrypto -lcurl -llzma -luuid
	# g++ -o $@ $@.o libbat.so $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS) -ldl -lz -lbz2 -lssl -lcrypto -lcurl -llzma -luuid

all: $(targets)

clean:
	rm -f $(targets) *.o *.so

.PHONY: q01
.DEFAULT_GOAL := all
