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
  // void rand_seed(){
  //   srand(clock());
  // }
  
  // unsigned int randu32(int i){
  //   return rand() << 16 | (rand()&((1<<16)-1));
  // }

  // unsigned long int randu64(int i){
  //   return ((unsigned long int)randu32(0)) << 32 | (unsigned long int)randu32(0);
  // }

  
  // unsigned int log2_c(unsigned int x){
  //   unsigned int y;
  //   asm ( "\tbsr %1, %0\n"
  //         : "=r"(y)
  //         : "r" (x)
  //         );
  //   return x == 0? -1:y;
  // }

}
