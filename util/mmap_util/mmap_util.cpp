#include "mmap_util.h"
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>

#include <stdio.h>

#include <assert.h>
#include <cstdlib>
#include <unistd.h>


size_t getFilesize(const char* filename) {
  struct stat st;
  int suc = stat(filename, &st);
  fprintf(stderr, "suc = %d, st_size = %ld\n", suc, st.st_size);
  return suc != -1 ? st.st_size: 0;
}


FRec* mmapfile(const char* fname, size_t size, bool newfile){

  fprintf(stderr, "mmap file = %s, size = %ld, newfile = %d\n", fname, size, newfile);
  if ( access(fname, F_OK ) != -1 && newfile ){
    fprintf(stderr, "Error: creating file which already exits\n");
    return NULL;
  }

  FRec *frec = new FRec;
  frec->fd = open(fname, O_RDWR | O_CREAT, (mode_t)0600);
  if (newfile ){
    lseek(frec->fd, size-1, SEEK_SET);
    size_t retval = write(frec->fd, "", 1);
    assert(retval == 1);
    frec->fs = size;
  } else {
    frec->fs = getFilesize(fname);
    if ( frec->fs != size) {
      free(frec);
      return NULL;
    }
  }
  assert((frec->fd)!=-1);
  frec->fs = size;
  frec->base = mmap(NULL, frec->fs, PROT_READ|PROT_WRITE, MAP_SHARED, frec->fd, 0);
  assert((frec->base)!=MAP_FAILED);
  return frec;
}

FRec* mmapfile_readonly(const char* fname){


  if ( access(fname, F_OK ) == -1){
    fprintf(stderr, "Error: file %s not found\n", fname);
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
