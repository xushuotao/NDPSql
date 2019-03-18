targets := q01

INC=common/stream common/options common/utils
INC_FLAGS=$(foreach d, $(INC), -I$d)

GDK_OBJS := $(patsubst %.c, %.o, $(notdir $(wildcard gdk/*.c)))
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

$(targets): %: %.cpp $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS)
	g++ -g -Igdk $(INC_FLAGS) -std=c++11 -fopenmp $@.cpp -o $@ $(GDK_OBJS) $(COMMON_OPTION_OBJS) $(COMMON_STREAM_OBJS) $(COMMON_UTILS_OBJS) -ldl -lz -lbz2 -lssl -lcrypto -lcurl -llzma -luuid

all: $(targets)

clean:
	rm -f $(targets) *.o *.so

.PHONY: q01
.DEFAULT_GOAL := all
