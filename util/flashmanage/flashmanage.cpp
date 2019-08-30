#include "flashmanage.h"
#include <iostream>
#include <chrono>

// For the size of the file.
#include <sys/stat.h>
// This contains the mmap calls.
#include <sys/mman.h>

#include <boost/filesystem.hpp>


pthread_spinlock_t FlashManager::lock;

lockfree::queue<int>   FlashManager::tagQueue(NUM_TAGS);
lockfree::queue<ulng>* FlashManager::eraseJobQ;

std::atomic_int   FlashManager::inflightErases;
std::atomic_int   FlashManager::inflightWrites;
std::atomic_int   FlashManager::inflightReads;
std::atomic_uint  FlashManager::goodBlocksErased;
std::atomic_ulong FlashManager::nexteraseblk;

TagTableEntry FlashManager::readTagTable[NUM_TAGS]; 
TagTableEntry FlashManager::writeTagTable[NUM_TAGS]; 
TagTableEntry FlashManager::eraseTagTable[NUM_TAGS];

FlashStatusT* FlashManager::flashStatus;
uint64_t*     FlashManager::ftl;

#define PROG_BAR
// pthread_t FlashManager::read_thread;

char* FlashManager::readBuffers[NUM_TAGS];
char* FlashManager::writeBuffers[NUM_TAGS];


void print_progress(std::string message, uint64_t norm, uint64_t denom){
#ifdef PROG_BAR
	float progress = (float)norm/(float)denom;
	assert(progress < 1.0);
	int barWidth = 70;
	std::cout << "\r" << message << ":[";
	int pos = barWidth * progress;
	for (int i = 0; i < barWidth; ++i) {
		if (i < pos) std::cout << "=";
		else if (i == pos) std::cout << ">";
		else std::cout << " ";
		}
	std::cout << "] " << int(progress * 100.0) << " % ("<<norm<<"/"<<denom<<")";
	std::cout.flush();
#endif
}

FlashManager::FlashManager(std::string basedir): basename(basedir) {
    init_device();

    char     cap[10];
    uint64_t cap_kB = TOTAL_BLKS*PAGES_PER_BLOCK*8;
    if ( cap_kB >= 1024*1024*1024 )      //TB
        sprintf(cap, "%luTB", cap_kB/1024/1024/1024);
    else if ( cap_kB >= 1024*1024 )      //GB
        sprintf(cap, "%luGB", cap_kB/1024/1024);
    else if ( cap_kB >= 1024 )           //MB
        sprintf(cap, "%luMB", cap_kB/1024);
    else
        sprintf(cap, "%luKB", cap_kB);
    fprintf(stderr, "FlashManager:: start capacity = %s\n", cap);
    init_fs();    
}

FlashManager::~FlashManager(){
    destroy_fs();    
}


int FlashManager::openfile(std::string file_name){
    fm::file_meta fmeta;
    bool exists = fmap->readfilemap(file_name, fmeta);
    fprintf(stderr, "%s exists=%d base = %lu, length = %lu\n", file_name.c_str(), exists, fmeta.base_page, fmeta.file_size);
    int retval = -1;
    if ( exists ){
        for ( int i = 0; i < FILE_DIR_SIZE; i++){
            if ( !fdir[i].busy ){
                retval       = i;
                fdir[i].base = fmeta.base_page;
                fdir[i].size = fmeta.file_size;
                fdir[i].busy = true;
                break;
            }
        }
    }
    return retval;
}

void FlashManager::closefile(int filedes){
    fdir[filedes].busy = false;
}


size_t FlashManager::filesize(int fd){
    return fdir[fd].size;
}

bool FlashManager::aio_read_page(read_cb* cb){
    if ( cb->busy == true ) return false;
  
    if ( !fdir[cb->fildes].busy ) {
        fprintf(stderr, "Error: file descriptor invalid\n");
        return false;
    }
    ulng base     = fdir[cb->fildes].base;
    ulng fs       = fdir[cb->fildes].size;
    size_t offset = cb->offset;

    if ( (offset & (PAGE_SIZE-1)) != 0 ){
        fprintf(stderr, "Error: offset not page aligned\n");
        return false;
    }

    if ( offset > fs ){
        fprintf(stderr, "Error: offset(%lu) should not exceed file size(%lu)\n", offset, fs);
        return false;
    }
    
    int tag;

    if ( tagQueue.pop(tag) ){

        ulng     pageaddr = base + (offset >> LG_PAGE_SIZE);
        uint64_t blk      = ftl[PGADDR2BLKADDR(pageaddr)];

        DEBUG_PRINT( "aio_read_page, pageaddr = %lu virtual blkid = %lu, physical blkid = %lu\n", pageaddr, PGADDR2BLKADDR(pageaddr), blk);
        uint32_t card  = BLKADDR2CARDID(blk);
        uint32_t bus   = BLKADDR2BUSID(blk);
        uint32_t chip  = BLKADDR2CHIPID(blk);
        uint32_t block = BLKADDR2BLKID(blk);
        int      page  = PGADDR2PGID(pageaddr);

        DEBUG_PRINT( "LOG: sending read page request with tag  = %d @%d %d %d %d %d, inflights=%u\n", tag, card, bus, chip, block, page, inflightReads.load() );
        device->readPage(card,bus,chip,block,page,tag);
        inflightReads++;
        cb->buf_ptr            = (void*) (readBuffers[tag]);
        cb->tag                = tag;
        cb->busy               = true;
        readTagTable[tag].busy = true;
        readTagTable[tag].addr = (ulng)cb;

#ifdef DEBUG
        assert( readTagTable[tag].busy == false && cb->busy == false  );
#endif
        return true;
    } else {
        return false;
    }
}

bool FlashManager::aio_return(read_cb* cb) {
    // DEBUG_PRINT("aio_return:: beginning cb->busy = %d\n", cb->busy);
    if ( !cb->busy ) return false;
    int tag = cb->tag;
#ifdef DEBUG
    assert( (ulng)cb  == readTagTable[tag].addr && readTagTable[tag].busy == true);
#endif
    // DEBUG_PRINT("aio_return:: checking tag  = %d, readBuffer[tag][PAGE_SIZE] = %d\n", tag, readBuffers[tag][PAGE_SIZE_VALID]);
    return readBuffers[tag][PAGE_SIZE_VALID]  == -1;
}

bool FlashManager::aio_done(read_cb* cb) {
    if (!cb->busy) return true;
    int tag = cb->tag;
#ifdef DEBUG
    assert( readTagTable[tag].busy == true && readTagTable[tag].addr == (ulng)cb );
#endif
    while ( !tagQueue.push(tag) );
    readBuffers[tag][PAGE_SIZE_VALID] = 0;
    readTagTable[tag].busy            = false;
    cb->busy                          = false;
    inflightReads--;
    return true;
}


void FlashManager::writefile(std::string file_name, const char* buf, size_t length){
    fm::file_meta fmeta;
    bool exists = fmap->readfilemap(file_name, fmeta);
    if ( exists) {
        fprintf(stderr, "%s exits on base = %lu, length  = %lu", file_name.c_str(), fmeta.base_page, fmeta.file_size);
        char resp = 'a';
        int  ret  = 0;
        while ( (resp != 'Y' && resp != 'y' && resp != 'n' && resp != 'N') || ret != 1 ){
            printf("\nAre you sure that you want to overwrite this file by discarding the old mapping?(y/n): ");
            ret = scanf("%c", &resp);
            getchar(); // remove newline
        }
        if ( resp == 'n' || resp == 'N' ){
            return;
        }
    }

#ifndef FAKE_WRITE
    if ( !eraseIfnecessary(length) ){
        fprintf(stderr, "Erasing flash pages failed\n");
        return;
    }
#endif
  
    fmeta = fm::file_meta{.base_page=meta[1], .file_size=length};

    append(buf, length);

    fmap->updatefilemap(file_name, fmeta);  
    fmap->sync();
}

uint32_t FlashManager::getPhysPageAddr(int fd, size_t offset){
    ulng base     = fdir[fd].base;
    ulng fs       = fdir[fd].size;

    if ( (offset & (PAGE_SIZE-1)) != 0 ){
        fprintf(stderr, "Error: offset not page aligned\n");
        return false;
    }

    if ( offset > fs ){
        fprintf(stderr, "Error: offset(%lu) should not exceed file size(%lu)\n", offset, fs);
        return false;
    }

    ulng    pageaddr = base + (offset >> LG_PAGE_SIZE);
    ulng    blkaddr  =
#ifndef FAKE_WRITE
		ftl[PGADDR2BLKADDR(pageaddr)];
#else
	    PGADDR2BLKADDR(pageaddr);
#endif
		
	uint pageid   = PGADDR2PGID(pageaddr);
	fprintf(stderr, "getPhysPageAddr, pageaddr = %lu virtual blkid = %lu, physical blkid = %lu, pageId = %u\n", pageaddr, PGADDR2BLKADDR(pageaddr), blkaddr, pageid);
    return (uint)BLKADDR2PAGEADDR(blkaddr, pageid);
}

  
void FlashManager::init_device(){
    device         = new FlashRequestProxy(IfcNames_FlashRequestS2H);
    testIndication = new FlashIndication(IfcNames_FlashIndicationH2S);
    
    DmaManager *dma = platformInit();


    size_t dstAlloc_sz = DMABUF_SIZE * NUM_TAGS *sizeof(unsigned char);
    size_t srcAlloc_sz = DMABUF_SIZE * NUM_TAGS *sizeof(unsigned char);


    DEBUG_PRINT( "Main::allocating memory...\n");
    
    // allocating dma buffers on host
    srcAlloc = portalAlloc(srcAlloc_sz, 0);
    dstAlloc = portalAlloc(dstAlloc_sz, 0);

    // mmaped dma buffers for host
    srcBuffer = (char*)portalMmap(srcAlloc, srcAlloc_sz);
    dstBuffer = (char*)portalMmap(dstAlloc, dstAlloc_sz);

    // flush dma buffers
    portalCacheFlush(srcAlloc, srcBuffer, srcAlloc_sz, 1);
    portalCacheFlush(dstAlloc, dstBuffer, dstAlloc_sz, 1);
    
    DEBUG_PRINT( "Main::flush and invalidate complete\n");

    pthread_spin_init(&lock, 0);

    printf( "Done initializing hw interfaces\n" ); fflush(stdout);


    // get dma reference pointer for FPGAs
    ref_dstAlloc = dma->reference(dstAlloc);
    ref_srcAlloc = dma->reference(srcAlloc);

    fprintf(stderr, "dstAlloc = %x\n", dstAlloc); 
    fprintf(stderr, "srcAlloc = %x\n", srcAlloc); 


    // setting up dma buffer refs to fpga
    device->setDmaReadRef(ref_srcAlloc);
    device->setDmaWriteRef(ref_dstAlloc);

    // devide up dma buffers for each read and write buffers
    for (int t = 0; t < NUM_TAGS; t++) {
        readTagTable[t].busy      = false;
        writeTagTable[t].busy     = false;
        int byteOffset            = t * DMABUF_SIZE;
        readBuffers[t]            = dstBuffer + byteOffset/sizeof(char);
        readBuffers[t][PAGE_SIZE] = 0;   // make sure it is non valid;
        writeBuffers[t]           = srcBuffer + byteOffset/sizeof(char);
        while(!tagQueue.push(t));
    }

    // starting the device;
    srand(time(NULL));
    device->start(rand());

    inflightReads    = 0;
    inflightErases   = 0;
    inflightWrites   = 0;
    goodBlocksErased = 0;
    eraseJobQ        = new lockfree::queue<ulng>(NUM_TAGS);
}

void FlashManager::init_fs(){

    fprintf(stderr, "init_fs:: start\n");
    boost::filesystem::create_directory(basename);
    
    std::string fs_name = basename+FLASHSTATUS_EXT;
    std::string meta_name = basename+META_EXT;
    std::string ftl_name = basename+FTL_EXT;
    std::string fd_name = basename+FILEMAP_EXT;

    bool newfile =
        (access(fs_name.c_str(), F_OK) == -1) |
        (access(meta_name.c_str(), F_OK) == -1) |
        (access(ftl_name.c_str(), F_OK) == -1) ;

    fprintf(stderr, "newfile = %s\n", newfile ? "true":"false");

    if ((frec_flashstatus = mmapfile(fs_name.c_str(), sizeof(FlashStatusT)*TOTAL_BLKS, newfile)) == NULL) {
        fprintf(stderr, "flashstatus mmap failed\n");
        exit(-1);
    }
    flashStatus = (FlashStatusT*)frec_flashstatus->base;
    
    if ((frec_meta = mmapfile(meta_name.c_str(), sizeof(uint64_t)*4, newfile)) == NULL){
        fprintf(stderr, "flashstatus mmap failed\n");
        exit(-1);
    }     

    meta = (uint64_t*)frec_meta->base;
    
    if ((frec_ftl = mmapfile(ftl_name.c_str(), sizeof(uint64_t)*TOTAL_BLKS, newfile)) == NULL){
        fprintf(stderr, "flash ftl mmap failed\n");
        exit(-1);
    }

    ftl = (uint64_t*)frec_ftl->base;

    if (newfile){
        for ( int i = 0; i < TOTAL_BLKS; i++){
            flashStatus[i] = UNINIT;
            ftl[i]         = UNMAPPED;
        }
        srand(time(NULL));
        meta[0] = rand()%TOTAL_BLKS;     // base blk addr
        meta[1] = 0;                     // next page address
        meta[2] = 0;                     // next erase block address
        meta[3] = 0;                     // total erased blocks
    }

    fmap = new fm::filemap(fd_name.c_str());
    fprintf(stderr, "pbb=%lu (TOTAL_BLKS = %d), nextp = %lu\n", meta[0], TOTAL_BLKS, meta[1]);

    nexteraseblk = meta[2];
    fprintf(stderr, "init_fs:: end\n");
}

void FlashManager::destroy_device(){
    delete eraseJobQ;
}


void FlashManager::destroy_fs(){
    unmmapfile(frec_flashstatus);
    unmmapfile(frec_meta);
    unmmapfile(frec_ftl);
    delete fmap;
}


inline int FlashManager::waitIdleTag() {
    int tag;
    while ( !tagQueue.pop(tag) ) {};
    return tag;
}


inline void FlashManager::eraseBlock(uint64_t logic_blk, uint64_t phys_blk) {
#ifndef FAKE_WRITE

    int card  = BLKADDR2CARDID(phys_blk);
    int bus   = BLKADDR2BUSID(phys_blk);
    int chip  = BLKADDR2CHIPID(phys_blk);
    int block = BLKADDR2BLKID(phys_blk);
    int tag   = waitIdleTag();
	DEBUG_PRINT( "eraseBlock, logic_blk = %lu, phys_blk = %lu, tag = %u\n", logic_blk, phys_blk, tag);  
    pthread_spin_lock(&lock);
    eraseTagTable[tag].addr  = phys_blk;
    eraseTagTable[tag].addr2 = logic_blk;
    inflightErases++;
    pthread_spin_unlock(&lock);
  
    DEBUG_PRINT( "LOG: sending erase block request with tag = %d @%d %d %d %d, inflights=%u\n", tag, card, bus, chip, block, inflightErases.load() );
    device->eraseBlock(card,bus,chip,block,tag);
#endif
}


inline bool FlashManager::eraseIfnecessary(size_t length){
    DEBUG_PRINT("eraseIfnecessary:: starting\n");
    const uint64_t  physblkbase    = meta[0];
    uint64_t        nextpageaddr   = meta[1];
    uint64_t        totalerasedblk = meta[3];

    uint64_t    pagesneeded      = (length+PAGE_SIZE-1)/PAGE_SIZE;
    uint64_t    new_nextpageaddr = nextpageaddr + pagesneeded;
    DEBUG_PRINT("eraseIfnecessary:: nextpageaddr = %lu,  pagesneeded = %lu\n", nextpageaddr, pagesneeded);
    uint64_t lastblk2write       = PGADDR2BLKADDR(new_nextpageaddr);    //(new_nextpageaddr+PAGES_PER_BLOCK-1)/PAGES_PER_BLOCK;
    DEBUG_PRINT("eraseIfnecessary:: lastblkTowrite = %lu, nexterseblk = %lu\n", lastblk2write, nexteraseblk.load());
  

    if ( lastblk2write > TOTAL_BLKS ) {
        fprintf(stderr, "Erase Failed:: No more blocks for erasure\n");
        return false;
    }

    uint64_t    newblksneeded      = lastblk2write > nexteraseblk ? lastblk2write - nexteraseblk : 0;
    uint64_t    superBlocksToErase = (newblksneeded + SUPER_BLK_SZ-1) / SUPER_BLK_SZ;
    uint64_t    blocksToErase      = superBlocksToErase * SUPER_BLK_SZ;
  
    DEBUG_PRINT("eraseIfnecessary:: pagesneeded = %lu, superBlocksToErase = %lu, blocksToErase = %lu\n", pagesneeded, superBlocksToErase, blocksToErase);



    // pthread_spin_lock(&lock);
    goodBlocksErased = 0;
    // nexteraseblk = meta[2];
    // pthread_spin_unlock(&lock);
    // for ( ulng i  = 0;  i < blocksToErase>NUM_TAGS?NUM_TAGS; i++ ){
    ulng    i           = 0;
    ulng    eraseReqCnt = 0;
    ulng    logic_blk;
    ulng    baseblk     = physblkbase+totalerasedblk;
	

	std::chrono::high_resolution_clock::time_point tm_0 = std::chrono::high_resolution_clock::now();
	std::chrono::high_resolution_clock::time_point tm_1;

    // sending in erasing Request into jobQ;
    while ( i < blocksToErase ){
        if (eraseJobQ->push(nexteraseblk + i)) {
            i++;
        } else { // if eraseJobQ is full then go and send all requests
            if (eraseJobQ->pop(logic_blk) ){
                eraseBlock(logic_blk, (baseblk + eraseReqCnt++)&(TOTAL_BLKS-1) );
            }
        }
		tm_1 = std::chrono::high_resolution_clock::now();	
		if ( tm_1-tm_0 >= std::chrono::milliseconds(100) ){
			tm_0 = tm_1;
			print_progress("Erasing blocks", goodBlocksErased, blocksToErase);
		}
    }


    while (goodBlocksErased < blocksToErase || inflightErases!=0){
        if (eraseJobQ->pop(logic_blk) ){
            eraseBlock(logic_blk, (baseblk + eraseReqCnt++)&(TOTAL_BLKS-1) );
        }
		tm_1 = std::chrono::high_resolution_clock::now();	
		if ( tm_1-tm_0 >= std::chrono::milliseconds(100) ){
			tm_0 = tm_1;
			print_progress("Erasing blocks", goodBlocksErased, blocksToErase);
		}
    }
    
    totalerasedblk += eraseReqCnt;
    // pthread_spin_lock(&lock);
    nexteraseblk   += blocksToErase;
    DEBUG_PRINT("eraseInnecessary:: nexteraseblk = %lu, totalerasedblk = %lu\n", nexteraseblk.load(), totalerasedblk);
    meta[2] = nexteraseblk;
    meta[3] = totalerasedblk;

#ifdef DEBUG
    for ( int i = (blocksToErase>0 ? blocksToErase:SUPER_BLK_SZ); i > 0 ; i-- ){
        fprintf(stderr, "ftl[%lu] = %lu\n", nexteraseblk.load()-i, ftl[nexteraseblk.load()-i]);
    }
#endif

    DEBUG_PRINT("eraseIfnecessary:: end\n");  
    return true;
}

inline void FlashManager::append(const char* buf, size_t length){
    uint64_t num_of_chunks = (length + PAGE_SIZE - 1)/PAGE_SIZE;
    uint64_t nextwrpage    = meta[1];
	std::chrono::high_resolution_clock::time_point tm_0 = std::chrono::high_resolution_clock::now();
	std::chrono::high_resolution_clock::time_point tm_1;
    for ( uint64_t i = 0; i < num_of_chunks; i++ ){
#ifndef FAKE_WRITE
        int tag = waitIdleTag();
        memcpy(writeBuffers[tag], (buf+(i<<LG_PAGE_SIZE)), PAGE_SIZE);
        uint64_t blk = ftl[PGADDR2BLKADDR(nextwrpage)];
        DEBUG_PRINT( "LOG: nextwrpage = %lu, virtual blkid = %lu, physical blkid = %lu\n", nextwrpage, PGADDR2BLKADDR(nextwrpage), blk);
        DEBUG_PRINT( "LOG: ulng buf[i<<LGPAGE_SIZE] = 0x%lx\n", *((ulng*)(buf+(i<<LG_PAGE_SIZE))));
        uint32_t card  = BLKADDR2CARDID(blk);
        uint32_t bus   = BLKADDR2BUSID(blk);
        uint32_t chip  = BLKADDR2CHIPID(blk);
        uint32_t block = BLKADDR2BLKID(blk);
        uint32_t page  = PGADDR2PGID(nextwrpage);
        DEBUG_PRINT( "LOG: sending write page request with tag = %d @%d %d %d %d %d, inflights=%u\n", tag, card, bus, chip, block, page, inflightWrites.load() );
        device->writePage(card,bus,chip,block,page,tag);
        inflightWrites++;
#endif
        nextwrpage++;
		tm_1 = std::chrono::high_resolution_clock::now();	
		if ( tm_1-tm_0 >= std::chrono::milliseconds(100) ){
			tm_0 = tm_1;
			print_progress("Writing Pages", i+1-inflightWrites.load(), num_of_chunks);
		}
    }

    while ( inflightWrites != 0){
		tm_1 = std::chrono::high_resolution_clock::now();	
		if ( tm_1-tm_0 >= std::chrono::milliseconds(100) ){
			tm_0 = tm_1;
			print_progress("Writing Pages", num_of_chunks-inflightWrites.load(), num_of_chunks);
		}
	}
    meta[1] = nextwrpage;

    DEBUG_PRINT("LOG:: end of append, nextwrpage= %lu\n", nextwrpage);
}
