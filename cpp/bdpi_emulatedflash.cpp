#include <stdint.h>
#include <fstream>
#include <iostream>
#include <string>
#include <boost/filesystem.hpp>
#include <map>
// #include <unordered_map>
#include <stddef.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <assert.h>


namespace fs = boost::filesystem;

std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";

extern "C"{
  void getData(uint32_t* resultptr, uint64_t pageaddr, uint32_t wordOffset);
  uint64_t getNumRows(char* fname);
  uint64_t getBaseAddr(char* colname);
}

typedef struct {
  int fd;
  size_t fs;
  void* base;
}  FRec;

typedef struct{
  FRec* rec;
  uint64_t baseAddr;
  std::string filename;
  uint64_t colBytes;
  uint64_t numRows;
} file_meta;

std::map<std::string, file_meta> map;
// std::unordered_map<std::string, file_meta> map;

bool loaded = false;
uint64_t baseAddr = 0;

size_t getFilesize(const char* filename) {
  struct stat st;
  int suc = stat(filename, &st);
  fprintf(stderr, "suc = %d, st_size = %ld\n", suc, st.st_size);
  return suc != -1 ? st.st_size: 0;
}

FRec* mmapfile_readonly(const char* fname){
  if ( access(fname, F_OK ) == -1){
    fprintf(stderr, "Error: file %s does not exist\n", fname);
    return NULL;
  }

  FRec *frec = new FRec;
  frec->fd = open(fname, O_RDONLY, 0);
  frec->fs = getFilesize(fname);
  fprintf(stderr, "mmap file = %s, size = %ld\n", fname, frec->fs);
  frec->base = mmap(NULL, frec->fs, PROT_READ, MAP_SHARED, frec->fd, 0);
  assert((frec->base)!=MAP_FAILED);
  return frec;
}

void unmmapfile(FRec* frec){
  int rc = munmap(frec->base, frec->fs);
  assert(rc==0);
  close(frec->fd);
  free(frec);
}

void print_map(){
  for (auto it = map.begin(); it!=map.end(); ++it)
  // for (std::unordered_map<std::string,file_meta>::iterator it = map.begin(); it!=map.end(); ++it)
      std::cout << it->first << " => " << it->second.baseAddr << ", " << it->second.filename << ", " << it->second.colBytes << ", " << it->second.numRows <<'\n';
}

void loadfile_map(){
  if ( loaded ) return;
  
  std::string file_path = __FILE__;
  std::string dir_path = file_path.substr(0, file_path.rfind("\/"));
  std::cout<<file_path<<std::endl;
  std::cout<<dir_path<<std::endl;
  
  std::ifstream file((dir_path+"/filemap.txt").c_str());
  std::string line;
  if ( file.good() ){
    std::string colname;
    std::string filename;
    uint32_t colBytes;
    uint64_t numRows;
    file_meta meta;
    while ( file >> colname >> meta.filename >> meta.colBytes >> meta.numRows ) {
      meta.rec = mmapfile_readonly((db_path+meta.filename+".tail").c_str());
      meta.baseAddr = baseAddr;
      baseAddr+=(((meta.numRows*meta.colBytes+8191)>>13)<<13);
      assert(baseAddr % 8192 == 0);
      map.insert(std::pair<std::string, file_meta>(colname, meta));
    }
  }
  file.close();
  print_map();
  loaded = true;
}


uint64_t getBaseAddr(char* fname){
  loadfile_map();
  auto it = map.find(std::string(fname));
  if ( it == map.end() ) return -1;
  fprintf(stderr, "baseaddr for %s is %lu\n", fname, it->second.baseAddr);
  return it->second.baseAddr;
}

uint64_t getNumRows(char* fname){
   loadfile_map();
   auto it = map.find(std::string(fname));
   if ( it == map.end() ) return -1;
   return it->second.numRows;
}


std::map<std::string,file_meta>::iterator findColumn(uint64_t pageAddr){
  // fprintf(stderr, "findColumn, pageaddr = %lu\n", pageAddr);
  auto it = map.begin();
  for ( ;it!=map.end(); ++it){
    auto baseByteAddr = it->second.baseAddr;
    auto numBytes = (it->second.numRows) * (it->second.colBytes);
    assert( baseByteAddr % 8192 == 0);
    auto basePage = baseByteAddr >> 13;
    auto numPages = (numBytes + 8191)>>13;

    if ( pageAddr >= basePage && pageAddr < (basePage+numPages) ) {
      return it;
    }
  }
  return it;
}

void getData(uint32_t* resultptr, uint64_t pageaddr, uint32_t wordOffset){
  auto it = findColumn(pageaddr);
  assert(it != map.end());
  // fprintf(stderr, "getData from %s\n", it->first.c_str());
  for ( uint32_t i = 0; i < 4; i++ ){
    resultptr[i] = 0xdeadbeaf;
  }
  if ( it == map.end()) return;
  auto baseByteAddr = it->second.baseAddr;
  memcpy(resultptr, (char*)((it->second.rec)->base) + ((pageaddr<<13)-baseByteAddr) + wordOffset*16, 16);
                          
  // fprintf(stderr, "getData(%lu, %u) Here\n", pageaddr, wordOffset);
}
