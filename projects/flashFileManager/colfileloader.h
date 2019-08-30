#ifndef __COLFILELOADER__
#define __COLFILELOADER__

#include "flashmanage.h"
#include <string.h>

void check_read_data(FlashManager* fmng, std::string fname, void* ref_array);
void check_col_files(FlashManager* fmng, std::string list_name, std::string db_path);
void write_col_files(FlashManager* fmng, std::string list_name, std::string db_path);

#endif
