#include <queue>
#include <stdint.h>
#include <stdio.h>
#include <assert.h>

uint64_t base = 0;
uint64_t lv;
uint64_t hv;
std::queue<uint64_t> pos;
std::queue<uint8_t> dutMask;
std::queue<uint64_t> dutData;

uint8_t colBytes = 0;
bool isSigned = false;
uint64_t cnt = 0;

extern "C" {

void init_test(uint64_t lbound, uint64_t hbound, uint8_t bytes, char sign){
  base = 0;
  lv = lbound;
  hv = hbound;
  colBytes = bytes;
  isSigned = (bool) sign;
  cnt = 0;
}



void inject_mask(uint32_t mask){
  assert( mask == UINT32_MAX );
}

void inject_data(unsigned int* data){
  int vecSize = 32/colBytes;
  char* ptr_char = (char*) data;
  short* ptr_short = (short*) data;
  int32_t* ptr_int = (int32_t*) data;
  uint32_t* ptr_uint = (uint32_t*) data;
  int64_t* ptr_lng = (int64_t*) data;
  uint64_t* ptr_ulng = (uint64_t*) data;
  
  for ( int i = 0; i < vecSize; i++ ){
    switch (colBytes) {
    case 1:
      if ( ptr_char[i] >= (char)lv && ptr_char[i] <= (char)hv) {
        cnt++;
        pos.push(base);
      }
      break;
    case 2:
      if ( ptr_short[i] >=  (short)lv && ptr_char[i] <= (short)hv) {
        cnt++;
        pos.push(base);
      }
      break;
    case 4:
      if ( isSigned) {
        if (ptr_int[i] >=  (int)lv && ptr_int[i] <= (int)hv) {
          fprintf(stderr, "inject_data:: ptr_int[%d] = %d, (lv, hv) = (%d, %d)\n", i, ptr_int[i], (int)lv, (int)hv);
          cnt++;
          pos.push(base);
        }
      } else {
        if (ptr_uint[i] >=  (uint32_t)lv && ptr_uint[i] <= (uint32_t)hv) {
          cnt++;
          pos.push(base);
        }
      }
      break;
    case 8:
      if ( isSigned) {
        if (ptr_lng[i] >=  (int64_t)lv && ptr_int[i] <= (int64_t)hv) {
          cnt++;
          pos.push(base);
        }
      } else {
        if (ptr_ulng[i] >=  (uint64_t)lv && ptr_uint[i] <= (uint64_t)hv) {
          cnt++;
          pos.push(base);
        }
      }
      break;
    default:
      fprintf(stderr, "Error: inject_data...for colBytes = %d unsupported\n", colBytes);
      break;
    }
    base++;
  }
}

bool check_result(){
  while ( (!dutMask.empty()) && (!dutData.empty()) ){
    uint8_t mask = dutMask.front();
    uint64_t data = dutData.front();
    dutMask.pop();
    dutData.pop();
    if ( mask == 1 ){
      assert(!pos.empty());
      uint64_t tester = pos.front();
      pos.pop();
      switch ( colBytes ){
      case 1:
        tester &= 0xff;
        data   &= 0xff;
        break;
      case 2:
        tester &= 0xffff;
        data   &= 0xffff;
        break;
      case 4:
        tester &= 0xffffffff;
        data   &= 0xffffffff;
        break;
      case 8:
        break;
      default:
        fprintf(stderr, "Error: check_result...for colBytes = %d unsupported\n", colBytes);
        return false;
      }
      if ( tester != data ) {
        fprintf(stderr, "check_result wrong: tester = %lu, mydata = %lu\n", tester, data);
        return false;
      }
    }
  }
  return true;
}


bool check_mask(uint32_t mask){
  uint32_t tempMask = mask;
  for ( int i = 0; i < 32; i++ ){
    dutMask.push(tempMask&0x1);
    tempMask = tempMask>>1;
  }
  return check_result();
}


bool check_data(uint32_t* data){
  char* ptr_char = (char*) data;
  short* ptr_short = (short*) data;
  uint32_t* ptr_uint = (uint32_t*) data;
  uint64_t* ptr_ulng = (uint64_t*) data;

  for ( int i = 0; i < 32/colBytes; i++ ){
    switch (colBytes) {
    case 1:
      dutData.push((uint64_t)(ptr_char[i]));
      break;
    case 2:
      dutData.push((uint64_t)(ptr_short[i]));
      break;
    case 4:
      dutData.push((uint64_t)(ptr_uint[i]));
      break;
    case 8:
      dutData.push((uint64_t)(ptr_ulng[i]));
      break;
    default:
      fprintf(stderr, "Error: check_data...for colBytes = %d unsupported\n", colBytes);
      return false;
    }
  }
  return check_result();
}

bool check_count(uint64_t v){
  fprintf(stderr, "count = %lu, mycount = %lu\n", cnt, v);
  check_result();
  return cnt == v;
}

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
//   {
//     fprintf(stderr, "my_min = %lu <---> min[%lu] = %lu\n", my_min, g, min[g]);
//     fprintf(stderr, "my_max = %lu <---> max[%lu] = %lu\n", my_max, g, max[g]);
//   }
//   fprintf(stderr, "my_sum = %lu <---> sum[%lu] = %lu\n", my_sum, g, sum[g]);
//   fprintf(stderr, "my_cnt = %lu <---> cnt[%lu] = %lu\n", my_cnt, g, cnt[g]);
//   return (my_min == min[g] && my_max == max[g] && my_cnt == cnt[g] && my_sum == sum[g] && valid) || (!valid && cnt[g] == 0);
// }
