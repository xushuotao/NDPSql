targets := randmemread

CPPFLAGS+= -g -O2 -std=c++11 -fopenmp 


$(targets): %: %.cpp
	g++ $(CPPFLAGS) $< -o $@ 
all: $(targets)

clean:
	rm -f $(targets) *.o *.so

.PHONY: $(targets)
.DEFAULT_GOAL := all
