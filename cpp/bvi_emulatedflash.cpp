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
	void getDataC(uint64_t pageaddr, uint32_t wordOffset, uint64_t* loWord, uint64_t* hiWord);
	uint64_t getNumRows(char* fname);
	uint64_t getBaseAddr(char* colname);
}

typedef struct {
	int		fd;
	size_t	fs;
	void*	base;
}  FRec;

typedef struct{
	FRec*		rec;
	uint64_t	basePage;
	uint64_t	fs;
} file_meta;

std::map<std::string, file_meta>	map;
bool								loaded = false;

size_t getFilesize(const char* filename) {
	struct stat st;
	int	suc	= stat(filename, &st);
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
		std::cout << it->first << " => " << it->second.basePage << ", " << it->second.fs <<'\n';
}

void loadfile_map(){
	if ( loaded ) return;
	std::ifstream	file("testdir/bdbm.fm");
	std::string		line;
	if ( file.good() ){
		std::string filename;
		uint32_t	colBytes;
		uint64_t	numRows;
		file_meta	meta;
		while ( file >> filename >> meta.basePage >> meta.fs ) {
			meta.rec = mmapfile_readonly(filename.c_str());
			map.insert(std::pair<std::string, file_meta>(filename, meta));
			assert(meta.fs <= meta.rec->fs);
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
	fprintf(stderr, "baseaddr for %s is %lu\n", fname, it->second.basePage);
	return it->second.basePage;
}

uint64_t getFileSize(char* fname){
	loadfile_map();
	auto it = map.find(std::string(fname));
	if ( it == map.end() ) return -1;
	return it->second.fs;
}


std::map<std::string,file_meta>::iterator findFile(uint64_t pageAddr){
	loadfile_map();
	// fprintf(stderr, "findColumn, pageaddr = %lu\n", pageAddr);
	auto it = map.begin();
	for ( ;it!=map.end(); ++it){
		auto numBytes = it->second.fs;
		auto basePage = it->second.basePage;
		auto numPages = (numBytes + 8191)>>13;

		if ( pageAddr >= basePage && pageAddr < (basePage+numPages) ) {
		return it;
		}
	}
	return it;
}

void getDataC(uint64_t pageaddr, uint32_t wordOffset, uint64_t* loWord, uint64_t* hiWord){
	auto it = findFile(pageaddr);
	// assert(it != map.end());
	//  fprintf(stderr, "getData from %s\n", it->first.c_str());
	// for ( uint32_t i = 0; i < 4; i++ ){
	*loWord = 0xdeadbeaf;
	*hiWord = 0xbadbadbd;
	// }
	if ( it == map.end()) return;
	auto basePage = (it->second.basePage);
	*loWord = *(uint64_t*)((char*)((it->second.rec)->base) + (((pageaddr-basePage)<<13) + wordOffset*16));
	*hiWord = *(uint64_t*)((char*)((it->second.rec)->base) + (((pageaddr-basePage)<<13) + wordOffset*16+8));
	// fprintf(stderr, "getData(%lu, %u) = (0x%16lx, 0x%16lx)\n", pageaddr, wordOffset, *loWord, *hiWord);
}
