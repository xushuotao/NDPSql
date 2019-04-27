#include <stddef.h>

typedef struct {
  int fd;
  size_t fs;
  void* base;
}  FRec;

size_t getFilesize(const char* filename);
FRec* mmapfile(const char* fname, size_t size, bool newfile);
FRec* mmapfile_readonly(const char* fname);
void unmmapfile(FRec* frec);
