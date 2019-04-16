#include "filemap.h"


int main(){
  filemap_namespace::filemap fm = filemap_namespace::filemap("filemap_test");
  filemap_namespace::file_meta meta = {.base_page=100, .file_size=1000};
  
  fm.updatefilemap("10/10000.tail", meta);

  filemap_namespace::filemap fm2 = filemap_namespace::filemap("filemap_test");

  std::string fname = "10/10000.tail";

  if (fm2.readfilemap(fname, meta)){
    fprintf(stderr, "%s  base = %lu, length = %lu\n", fname.c_str(), meta.base_page, meta.file_size);
  } else {
    fprintf(stderr, "%s not found\n", fname.c_str());
  }


  fname = "shit";
  
  if (fm2.readfilemap(fname, meta)){
    fprintf(stderr, "%s  base = %lu, length = %lu\n", fname.c_str(), meta.base_page, meta.file_size);
  } else {
    fprintf(stderr, "%s not found\n", fname.c_str());
  }
}
