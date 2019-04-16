#include <fstream>
#include <string>
#include <boost/filesystem.hpp>
#include "filemap.h"

namespace fs = boost::filesystem;

namespace filemap_namespace
{
  bool operator==(const file_meta& lhs, const file_meta& rhs)
  {
    return lhs.base_page == rhs.base_page && lhs.file_size == rhs.file_size;
  }
  
  filemap::filemap(std::string mapname): mapname(mapname), updated(false) {
    std::ifstream file(mapname.c_str());
    std::string line;
    if ( file.good() ){
      std::string filename;
      file_meta meta;
      uint64_t page_base,file_size;
      while ( file >> filename >> page_base >> file_size ) {
        meta.base_page = page_base;
        meta.file_size = file_size;
        map.insert(std::pair<std::string, file_meta>(filename, meta));
      }
    }
    file.close();
  }

  bool filemap::readfilemap(std::string filename, file_meta& meta){
    std::map<std::string, file_meta>::iterator it = map.find(filename);
    if ( it == map.end() )
      return false;

    meta = (it->second);
    return true;
  }
  
  bool filemap::updatefilemap(std::string filename, file_meta meta){

    if ( (map[filename]) == meta) return true;
    
    updated = true;
    map[filename] = meta;
    return map[filename] == meta;
  }
  
  bool filemap::sync(){
    if ( updated ){
      fs::path __src(mapname);
      fs::path __dst(mapname+".bak");
      if ( fs::exists(__src) ) {
        fs::copy_file(__src, __dst, fs::copy_option::overwrite_if_exists);
      }
      
      std::ofstream file(mapname.c_str());
      if ( file.good() ){
        std::map<std::string, file_meta>::iterator it;
        for ( it = map.begin(); it !=map.end(); ++it ){
          file << it->first << " " << it->second.base_page << " " << it->second.file_size << "\n";
        }
        file.close();
        return true;
      }
      else {
        file.close();
        return false;
      }
    }  else {
      return true;
    }
  }
  
  filemap::~filemap(){
    sync();
  }

}



