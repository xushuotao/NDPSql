targets := q01 q03 q06

INC=. gdk common/stream common/options common/utils libbloom libbloom/murmur2
INC_FLAGS=$(foreach d, $(INC), -I$d)

GDK_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard gdk/*.c)))
COMMON_OPTION_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard common/options/*.c)))
COMMON_STREAM_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard common/stream/*.c)))
COMMON_UTILS_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard common/utils/*.c)))

CFLAGS+= -g -O2 -DHAVE_CONFIG_H -D_REENTRANT $(INC_FLAGS)

ifeq ($(INLINE), 1)
CFLAGS+= -DINLINE
else
BLOOM_OBJS=murmur2.o bloom.o
endif



$(COMMON_OPTION_OBJS): %.o : common/options/%.c
	gcc $(CFLAGS) -DLIBMOPTIONS -c $< -fPIC -DPIC -o $@

$(COMMON_STREAM_OBJS): %.o : common/stream/%.c
	gcc $(CFLAGS) -DLIBSTREAM -c $< -fPIC -DPIC -o $@

$(COMMON_UTILS_OBJS): %.o : common/utils/%.c
	gcc  $(CFLAGS) -DLIBUTILS -c $< -fPIC -DPIC -o $@


$(GDK_OBJS): %.o: gdk/%.c
	gcc $(CFLAGS) -DLIBGDK -c $< -fPIC -DPIC -o $@

dbengines.o: dbengines.cpp
	g++ -g -O2 -Igdk $(INC_FLAGS) -std=c++11 -fopenmp -c $< -fPIC -DPIC -o $@


# $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS) -ldl -lz -lbz2 -lssl -lcrypto -lcurl -llzma -luuid

murmur2.o: libbloom/murmur2/MurmurHash2.c
	gcc $(CFLAGS) -c $< -fPIC -DPIC -o $@

bloom.o: murmur2.o libbloom/bloom.c
	gcc $(CFLAGS) -c libbloom/bloom.c -fPIC -DPIC -o $@

$(targets): %: %.cpp $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS) dbengines.o $(BLOOM_OBJS)
	g++ -g -Igdk $(INC_FLAGS) -std=c++11 -fopenmp $@.cpp -o $@ $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS) $(BLOOM_OBJS) dbengines.o -ldl -lz -lbz2 -lssl -lcrypto -lcurl -llzma -luuid

all: $(targets)

clean:
	rm -f $(targets) *.o *.so

.PHONY: $(targets)
.DEFAULT_GOAL := all
