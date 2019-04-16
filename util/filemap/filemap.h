#ifndef __FILEMAP__
#define __FILEMAP__

#include <string>
#include <map>
#include <stdint.h>

namespace filemap_namespace
{

  typedef struct{
    uint64_t base_page;
    uint64_t file_size;
  } file_meta;

  class filemap{
  public:
    filemap(std::string mapname);

    bool readfilemap(std::string filename, file_meta& meta);
    bool updatefilemap(std::string filename, file_meta meta);
    bool sync();
    ~filemap();
  private:
    std::string mapname;
    std::map<std::string, file_meta> map;
    bool updated;
  };
}


#endif
