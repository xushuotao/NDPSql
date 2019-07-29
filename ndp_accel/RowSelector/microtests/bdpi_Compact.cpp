#include <queue>
#include <stdint.h>
#include <stdio.h>

extern "C"
{
  // uint64_t base = 0;
  // uint64_t lbound;
  // uint64_t hbound;
  std::queue<uint64_t> rowDataQ;
  std::queue<uint32_t> rowMaskQ;
  
  std::queue<uint32_t> result;

  int rowsPerBeat;
  int colBytes;

  void init_test(uint32_t cBytes){
    fprintf(stderr, "init_test (%u)\n", cBytes);
    rowsPerBeat = 32/cBytes;
    colBytes = cBytes;
    // base = 0;
    // lbound = lv;
    // hbound = hv;
    fprintf(stderr, "end init_test (%u)\n", cBytes);
    
  }

  uint64_t totalBytes = 0;
  
  inline void produce_result(){
    while (rowDataQ.size() >= 32 && !rowMaskQ.empty() ){
      uint32_t mask = rowMaskQ.front();
      fprintf(stderr, "prod_rst mask = %x\n", mask);
      rowMaskQ.pop();
      for ( int i = 0; i < 32; i++ ){
        uint64_t data = rowDataQ.front();
        // fprintf(stderr, "rowData = %32lx\n", data);
        rowDataQ.pop();
        if ( (mask&1) == 1) {
          result.push(data);
          totalBytes+=colBytes;
        }
        mask>>=1;
      }
    }
  }

  void inject_rowData(uint32_t* x0){
    fprintf(stderr, "inject_rowData (%d)\n", rowsPerBeat);
    for (int i = 0; i < rowsPerBeat; i++ ){
      if ( colBytes == 1 )
        rowDataQ.push((uint64_t)(((char*)x0)[i])&(0xff));
      else if ( colBytes == 2)
        rowDataQ.push((uint64_t)(((short*)x0)[i])&(0xffff));
      else if ( colBytes == 4)
        rowDataQ.push((uint64_t)(((uint32_t*)x0)[i])&(0xffffffff));
      else if ( colBytes == 8)
        rowDataQ.push((uint64_t)(((uint64_t*)x0)[i]));
    }
    produce_result();
  }

  void inject_rowMask(uint32_t x0){
    rowMaskQ.push(x0);
    produce_result();
  }
  



  bool check_result(uint32_t* x0, int32_t bytes){
    bool retval = true;
    for ( int i = 0; i < rowsPerBeat; i++) {
      // fprintf(stderr, "check_result bytes = %u\n", bytes);
       if ( bytes >= colBytes ){
         uint64_t currResult = result.front();
         result.pop();
         uint64_t mydata;
         if ( colBytes == 1 )
           mydata = ((uint64_t)(((char*)x0)[i]))&(0xff);
         else if ( colBytes == 2)
           mydata = ((uint64_t)(((short*)x0)[i]))&(0xffff);
         else if ( colBytes == 4)
           mydata = ((uint64_t)(((uint32_t*)x0)[i]))&(0xffffffff);
         else if ( colBytes == 8)
           mydata = (uint64_t)(((uint64_t*)x0)[i]);

         fprintf(stderr, "totalBytes = %lu, curr_result = %32lx, my_result = %32lx\n", totalBytes, currResult, mydata);
         retval &= (currResult == mydata);
       }
       bytes-=colBytes;
    }
    return retval;
  }

  
  bool check_count(uint64_t v){
    fprintf(stderr, "totalBytes = %lu, my_totalBytes = %lu\n", totalBytes, v);
    return result.empty() && (v == totalBytes);
  }


  // // aggregator related tests
  // uint64_t min[8];
  // uint64_t max[8];
  // uint64_t sum[8];
  // uint64_t cnt[8];
  // bool isSigned;

  // void init_test_aggr(bool s){
  //   for (int i = 0; i < 8; i++){
  //     min[i] = s ? INT64_MAX: UINT64_MAX;
  //     max[i] = s ? INT64_MIN: 0;
  //     sum[i] = 0;
  //     cnt[i] = 0;
  //   }
  //   isSigned = s;
  // }

  // void inject_test_aggr(uint64_t x0, uint8_t mask, uint64_t g){
  //   if ( mask > 0 ) {
  //     cnt[g]++;
  //     sum[g]+=x0;
  //     min[g]=isSigned? (uint64_t) std::min((int64_t)x0, (int64_t)(min[g])):std::min(x0, min[g]);
  //     max[g]=isSigned? (uint64_t) std::max((int64_t)x0, (int64_t)(max[g])):std::max(x0, max[g]);
  //   }
  // }

  // bool check_test_aggr(uint64_t my_min, uint64_t my_max, uint64_t my_sum, uint64_t my_cnt, uint64_t g, bool valid){
  //   fprintf(stderr, "my_valid for %lu group is %s\n", g, valid?"valid":"invalid");
  //   // if ( isSigned ){
  //   //   fprintf(stderr, "my_min = %ld <---> min[%lu] = %l\n", my_min, g, min[g]);
  //   //   fprintf(stderr, "my_max = %ld <---> max[%lu] = %l\n", my_max, g, max[g]);
  //   // } 
  //   // else 
  //     {
  //     fprintf(stderr, "my_min = %lu <---> min[%lu] = %lu\n", my_min, g, min[g]);
  //     fprintf(stderr, "my_max = %lu <---> max[%lu] = %lu\n", my_max, g, max[g]);
  //   }
  //   fprintf(stderr, "my_sum = %lu <---> sum[%lu] = %lu\n", my_sum, g, sum[g]);
  //   fprintf(stderr, "my_cnt = %lu <---> cnt[%lu] = %lu\n", my_cnt, g, cnt[g]);
  //   return (my_min == min[g] && my_max == max[g] && my_cnt == cnt[g] && my_sum == sum[g] && valid) || (!valid && cnt[g] == 0);
  // }


}
