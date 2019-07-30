/* 
Copyright (C) 2018

Shuotao Xu <shuotao@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.  

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#include <stdlib.h>
#include <time.h>
#include <stdio.h>
#include <stdint.h>
#include <vector>
#include <algorithm>

extern "C"
{
  void rand_seed(){
    srand(clock());
  }
  
  unsigned int randu32(int i){
    return rand() << 16 | (rand()&((1<<16)-1));
  }

  unsigned long int randu64(int i){
    return ((unsigned long int)randu32(0)) << 32 | (unsigned long int)randu32(0);
  }

  
  unsigned int log2_c(unsigned int x){
    unsigned int y;
    asm ( "\tbsr %1, %0\n"
          : "=r"(y)
          : "r" (x)
          );
    return x == 0? -1:y;
  }

  // aggregator related tests
  uint64_t min[8];
  uint64_t max[8];
  uint64_t sum[8];
  uint64_t cnt[8];
  bool isSigned;

  void init_test_aggr(bool s){
    for (int i = 0; i < 8; i++){
      min[i] = s ? INT64_MAX: UINT64_MAX;
      max[i] = s ? INT64_MIN: 0;
      sum[i] = 0;
      cnt[i] = 0;
    }
    isSigned = s;
  }

  void inject_test_aggr(uint64_t x0, uint8_t mask, uint64_t g){
    if ( mask > 0 ) {
      cnt[g]++;
      sum[g]+=x0;
      min[g]=isSigned? (uint64_t) std::min((int64_t)x0, (int64_t)(min[g])):std::min(x0, min[g]);
      max[g]=isSigned? (uint64_t) std::max((int64_t)x0, (int64_t)(max[g])):std::max(x0, max[g]);
    }
  }

  bool check_test_aggr(uint64_t my_min, uint64_t my_max, uint64_t my_sum, uint64_t my_cnt, uint64_t g, bool valid){
    fprintf(stderr, "my_valid for %lu group is %s\n", g, valid?"valid":"invalid");
    if ( isSigned ){
      fprintf(stderr, "my_min = %ld <---> min[%lu] = %l\n", my_min, g, min[g]);
      fprintf(stderr, "my_max = %ld <---> max[%lu] = %l\n", my_max, g, max[g]);
    } 
    else 
      {
      fprintf(stderr, "my_min = %lu <---> min[%lu] = %lu\n", my_min, g, min[g]);
      fprintf(stderr, "my_max = %lu <---> max[%lu] = %lu\n", my_max, g, max[g]);
    }
    fprintf(stderr, "my_sum = %lu <---> sum[%lu] = %lu\n", my_sum, g, sum[g]);
    fprintf(stderr, "my_cnt = %lu <---> cnt[%lu] = %lu\n", my_cnt, g, cnt[g]);
    return (my_min == min[g] && my_max == max[g] && my_cnt == cnt[g] && my_sum == sum[g] && valid) || (!valid && cnt[g] == 0);
  }
}
