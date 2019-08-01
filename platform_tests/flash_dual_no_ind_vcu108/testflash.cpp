
#include <sys/time.h>
#include <iostream>
#include <stdlib.h>
#include <time.h>

#include "dmaManager.h"
#include "FlashIndication.h"
#include "FlashRequest.h"

#if defined(SIMULATION)
#define BLOCKS_PER_CHIP 1 
#define CHIPS_PER_BUS 8
#define NUM_BUSES 8
#define NUM_CARDS 2

#else
#define BLOCKS_PER_CHIP 1
#define CHIPS_PER_BUS 8
#define NUM_BUSES 8
#define NUM_CARDS 2
#endif


#define PAGE_SIZE (8192*2)
#define PAGE_SIZE_VALID (8224)
#define NUM_TAGS 128

// #define DEBUG 1

#ifdef DEBUG
#define DEBUG_PRINT(...) do{ fprintf( stderr, __VA_ARGS__ ); } while( false )
#else
#define DEBUG_PRINT(...) do{ } while ( false )
#endif

typedef enum {
  UNINIT,
  ERASED,
  ERASED_BAD,
  WRITTEN
} FlashStatusT;

typedef struct {
  bool busy;
  int card;
  int bus;
  int chip;
  int block;
} TagTableEntry;

FlashRequestProxy *device;

pthread_mutex_t flashReqMutex;
pthread_cond_t flashFreeTagCond;

//8k * 128p
size_t dstAlloc_sz = PAGE_SIZE * NUM_TAGS *sizeof(unsigned char);
size_t srcAlloc_sz = PAGE_SIZE * NUM_TAGS *sizeof(unsigned char);
int dstAlloc;
int srcAlloc;
unsigned int ref_dstAlloc; 
unsigned int ref_srcAlloc; 
unsigned int* dstBuffer;
unsigned int* srcBuffer;
unsigned int* readBuffers[NUM_TAGS];
unsigned int* writeBuffers[NUM_TAGS];
TagTableEntry readTagTable[NUM_TAGS]; 
TagTableEntry writeTagTable[NUM_TAGS]; 
TagTableEntry eraseTagTable[NUM_TAGS]; 
FlashStatusT flashStatus[NUM_CARDS][NUM_BUSES][CHIPS_PER_BUS][BLOCKS_PER_CHIP];

int testPass = 1;
bool verbose = true;
int curReadsInFlight = 0;
int curWritesInFlight = 0;
int curErasesInFlight = 0;

int blockBase = 0; // so that we are not erasing the same block;

double timespec_diff_sec( timespec start, timespec end ) {
  double t = end.tv_sec - start.tv_sec;
  t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
  return t;
}


unsigned int hashAddrToData(int card, int bus, int chip, int blk, int word) {
  return ((card<<28) + (bus<<24) + (chip<<20) + (blk<<16) + word);
}


void checkReadData(int tag) {
  TagTableEntry e = readTagTable[tag];
  unsigned int goldenData;
  if (flashStatus[e.card][e.bus][e.chip][e.block]==WRITTEN) {
    int numErrors = 0;
    for (unsigned int word=0; word<PAGE_SIZE_VALID/sizeof(unsigned int); word++) {
      goldenData = hashAddrToData(e.card, e.bus, e.chip, e.block, word);
      if (goldenData != readBuffers[tag][word]) {
        // DEBUG_PRINT( "LOG: **ERROR: read data mismatch! Expected: %x, read: %x\n", goldenData, readBuffers[tag][word]);
        fprintf(stderr, "LOG: **ERROR: read data mismatch! tag = %d, (card, bus, chip, block, word) = (%d, %d, %d, %d, %d), Expected: %x, read: %x\n", tag, e.card, e.bus, e.chip, e.block, word, goldenData, readBuffers[tag][word]);
        numErrors++; 
        testPass = 0;
      }
    }
    if (numErrors==0) {
      DEBUG_PRINT( "LOG: Read data check passed on tag=%d!\n", tag);
    }
  }
  else if (flashStatus[e.card][e.bus][e.chip][e.block]==ERASED) {
    //only check first word. It may return 0 if bad block, or -1 if erased
    if (readBuffers[tag][0]==(unsigned int)-1) {
      DEBUG_PRINT( "LOG: Read check pass on erased block!\n");
    }
    else if (readBuffers[tag][0]==0) {
      DEBUG_PRINT( "LOG: Warning: potential bad block, read erased data 0\n");
    }
    else {
      DEBUG_PRINT( "LOG: **ERROR: read data mismatch! Expected: ERASED, read: %x\n", readBuffers[tag][0]);
      testPass = 0;
    }
  }
  else {
    DEBUG_PRINT( "LOG: **ERROR: flash block state unknown. Did you erase before write?\n");
    testPass = 0;
  }
}



class FlashIndication : public FlashIndicationWrapper{
public:
  virtual void readDone(unsigned int tag, uint64_t cycles) {

    fprintf(stderr, "ERROR: pagedone: no indication should be really sent");

  }

  virtual void writeDone(unsigned int tag, uint64_t cycles) {
    DEBUG_PRINT("LOG: writedone, tag=%d, FPGA cycles = %lu\n", tag, cycles); 
    //TODO probably should use a diff lock
    pthread_mutex_lock(&flashReqMutex);
    curWritesInFlight--;
    if ( curWritesInFlight < 0 ) {
      DEBUG_PRINT( "LOG: **ERROR: Write requests in flight cannot be negative %d\n", curWritesInFlight );
      curWritesInFlight = 0;
    }
    if ( writeTagTable[tag].busy == false ) {
      DEBUG_PRINT( "LOG: **ERROR: received unused buffer Write done %d\n", tag);
      testPass = 0;
    }
    writeTagTable[tag].busy = false;
    pthread_mutex_unlock(&flashReqMutex);
  }

  virtual void eraseDone(unsigned int tag, unsigned int status, uint64_t cycles) {
    DEBUG_PRINT("LOG: eraseDone, tag=%d, status=%d, FPGA cycles = %lu\n", tag, status, cycles);
    pthread_mutex_lock(&flashReqMutex);
    
    int card = eraseTagTable[tag].card;
    int bus = eraseTagTable[tag].bus;
    int chip = eraseTagTable[tag].chip;
    int block = eraseTagTable[tag].block;
    if (status != 0) {
      printf("LOG: detected bad block with tag = %d\n", tag);
      flashStatus[card][bus][chip][block] = ERASED_BAD;
    } else {
      flashStatus[card][bus][chip][block] = ERASED;
    }

    if ( curErasesInFlight < 0 ) {
      DEBUG_PRINT( "LOG: **ERROR: erase requests in flight cannot be negative %d\n", curErasesInFlight );
      curErasesInFlight = 0;
    }
    if ( eraseTagTable[tag].busy == false ) {
      DEBUG_PRINT( "LOG: **ERROR: received unused tag erase done %d\n", tag);
      testPass = 0;
    }
    eraseTagTable[tag].busy = false;
    curErasesInFlight--;
    pthread_mutex_unlock(&flashReqMutex);
  }

  virtual void debugDumpResp (unsigned int card, unsigned int debug0, unsigned int debug1,  unsigned int debug2, unsigned int debug3, unsigned int debug4, unsigned int debug5) {
    DEBUG_PRINT( "LOG: DEBUG DUMP: card = %d, gearSend = %d, gearRec = %d, aurSend = %d, aurRec = %d, readSend=%d, writeSend=%d\n",card, debug0, debug1, debug2, debug3, debug4, debug5);
  }

  FlashIndication(unsigned int id) : FlashIndicationWrapper(id){}
};


int getNumReadsInFlight() { return curReadsInFlight; }
int getNumWritesInFlight() { return curWritesInFlight; }
int getNumErasesInFlight() { return curErasesInFlight; }



//TODO: more efficient locking
int waitIdleEraseTag() {
  int tag = -1;
  while ( tag < 0 ) {
	pthread_mutex_lock(&flashReqMutex);

    for ( int t = 0; t < NUM_TAGS; t++ ) {
      if ( !eraseTagTable[t].busy ) {
        eraseTagTable[t].busy = true;
        tag = t;
        break;
      }
    }
	pthread_mutex_unlock(&flashReqMutex);
  }
  return tag;
}


//TODO: more efficient locking
int waitIdleWriteBuffer() {
  int tag = -1;
  while ( tag < 0 ) {
	pthread_mutex_lock(&flashReqMutex);

    for ( int t = 0; t < NUM_TAGS; t++ ) {
      if ( !writeTagTable[t].busy) {
        writeTagTable[t].busy = true;
        tag = t;
        break;
      }
    }
	pthread_mutex_unlock(&flashReqMutex);
    /*
      if (tag < 0) {
      pthread_cond_wait(&flashFreeTagCond, &flashReqMutex);
      }
      else {
      pthread_mutex_unlock(&flashReqMutex);
      return tag;
      }
    */
  }
  return tag;
}



//TODO: more efficient locking
int waitIdleReadBuffer() {
  int tag = -1;
  while ( tag < 0 ) {
	pthread_mutex_lock(&flashReqMutex);

    for ( int t = 0; t < NUM_TAGS; t++ ) {
      if ( !readTagTable[t].busy ) {
        readTagTable[t].busy = true;
        tag = t;
        break;
      }
    }
	pthread_mutex_unlock(&flashReqMutex);
  }
  return tag;
}


void eraseBlock(int card, int bus, int chip, int block, int tag) {

  pthread_mutex_lock(&flashReqMutex);
  curErasesInFlight ++;
  // flashStatus[card][bus][chip][block] = ERASED;
  pthread_mutex_unlock(&flashReqMutex);
  eraseTagTable[tag].card = card;
  eraseTagTable[tag].bus = bus;
  eraseTagTable[tag].chip = chip;
  eraseTagTable[tag].block = block;
  DEBUG_PRINT( "LOG: sending erase block request with tag=%d @%d %d %d %d 0\n", tag, card, bus, chip, block );
  device->eraseBlock(card,bus,chip,(blockBase+block)%4096,tag);
}



void writePage(int card, int bus, int chip, int block, int page, int tag) {
  pthread_mutex_lock(&flashReqMutex);
  curWritesInFlight ++;
  if ( flashStatus[card][bus][chip][block] == ERASED ) {
    flashStatus[card][bus][chip][block] = WRITTEN;
    pthread_mutex_unlock(&flashReqMutex);

    DEBUG_PRINT( "LOG: sending write page request with tag=%d @%d %d %d %d %d\n", tag, card, bus, chip, block, page );
    DEBUG_PRINT( "LOG: currNumWrite =%d\n", curWritesInFlight);
    device->writePage(card,bus,chip,(blockBase+block)%4096,page,tag);
  } else {
    printf("LOG: skipping write flash block (card,bus,chip,block) = (%d,%d,%d,%d)", card, bus, chip, block);
  }
}

void readPage(int card, int bus, int chip, int block, int page, int tag) {
  pthread_mutex_lock(&flashReqMutex);
  curReadsInFlight ++;
  readTagTable[tag].card = card;
  readTagTable[tag].bus = bus;
  readTagTable[tag].chip = chip;
  readTagTable[tag].block = block;
  pthread_mutex_unlock(&flashReqMutex);

  DEBUG_PRINT( "LOG: sending read page request with tag=%d @%d %d %d %d %d\n", tag, card, bus, chip, block, page );
  device->readPage(card,bus,chip,(blockBase+block)%4096,page,tag);
}


void *check_read_buffer_done(void *ptr){

  int tag = 0;
  int flag_word_offset=PAGE_SIZE_VALID/sizeof(unsigned int);
  while ( true ){
    // DEBUG_PRINT("LOG: readBuffers[%d][%d]=%x\n", tag, flag_word_offset, readBuffers[tag][flag_word_offset] );
    if ( readBuffers[tag][flag_word_offset] == (unsigned int)-1 ) {

      DEBUG_PRINT("LOG: pagedone: tag=%d; inflight=%d\n", tag, curReadsInFlight );
      checkReadData(tag);
      
      pthread_mutex_lock(&flashReqMutex);
      curReadsInFlight --;
      if ( curReadsInFlight < 0 ) {
        DEBUG_PRINT( "LOG: **ERROR: Read requests in flight cannot be negative %d\n", curReadsInFlight );
        curReadsInFlight = 0;
      }
      if ( readTagTable[tag].busy == false ) {
        DEBUG_PRINT( "LOG: **ERROR: received unused buffer read done %d\n", tag);
        testPass = 0;
      }
      readTagTable[tag].busy = false;
      readBuffers[tag][flag_word_offset] = 0;
      pthread_mutex_unlock(&flashReqMutex);
    }

    tag = (tag + 1)%NUM_TAGS;
    // usleep(100);
  }
    
}



int main(int argc, const char **argv){
  DEBUG_PRINT( "Main Start\n");
  device = new FlashRequestProxy(IfcNames_FlashRequestS2H);
  FlashIndication testIndication(IfcNames_FlashIndicationH2S);

  DmaManager *dma = platformInit();

  DEBUG_PRINT( "Main::allocating memory...\n");

  srcAlloc = portalAlloc(srcAlloc_sz, 0);
  dstAlloc = portalAlloc(dstAlloc_sz, 0);

  srcBuffer = (unsigned int *)portalMmap(srcAlloc, srcAlloc_sz);
  dstBuffer = (unsigned int *)portalMmap(dstAlloc, dstAlloc_sz);

  portalCacheFlush(srcAlloc, srcBuffer, srcAlloc_sz, 1);
  portalCacheFlush(dstAlloc, dstBuffer, dstAlloc_sz, 1);
  DEBUG_PRINT( "Main::flush and invalidate complete\n");

  pthread_mutex_init(&flashReqMutex, NULL);
  pthread_cond_init(&flashFreeTagCond, NULL);

  printf( "Done initializing hw interfaces\n" ); fflush(stdout);


  ref_dstAlloc = dma->reference(dstAlloc);
  ref_srcAlloc = dma->reference(srcAlloc);

  fprintf(stderr, "dstAlloc = %x\n", dstAlloc); 
  fprintf(stderr, "srcAlloc = %x\n", srcAlloc); 
	
  device->setDmaReadRef(ref_srcAlloc);
  device->setDmaWriteRef(ref_dstAlloc);

  for (int t = 0; t < NUM_TAGS; t++) {
    readTagTable[t].busy = false;
    writeTagTable[t].busy = false;
    int byteOffset = t * PAGE_SIZE;
    // device->addDmaWriteRefs(ref_dstAlloc, byteOffset, t);
    // device->addDmaReadRefs(ref_srcAlloc, byteOffset, t);
    readBuffers[t] = dstBuffer + byteOffset/sizeof(unsigned int);
    writeBuffers[t] = srcBuffer + byteOffset/sizeof(unsigned int);
  }
	
  for (int blk=0; blk<BLOCKS_PER_CHIP; blk++) {
    for (int c=0; c<CHIPS_PER_BUS; c++) {
      for (int bus=0; bus< CHIPS_PER_BUS; bus++) {
        for (int card=0; card < NUM_CARDS; card++) {
          // fprintf(stderr,"flashStatus[%d][%d][%d][%d] = UNINIT\n",card,bus,c,blk);
          flashStatus[card][bus][c][blk] = UNINIT;
        }
      }
    }
  }

  fprintf(stderr, "Done initializing flashStatus\n");

  for (int t = 0; t < NUM_TAGS; t++) {
    for ( unsigned int i = 0; i < PAGE_SIZE/sizeof(unsigned int); i++ ) {
      readBuffers[t][i] = 0;
      writeBuffers[t][i] = 0;
    }
  }

  fprintf(stderr, "Done initializing buffers\n");
  /* this variable is our reference to the second thread */
  pthread_t check_thread;

  /* create a second thread which executes inc_x(&x) */
  if(pthread_create(&check_thread, NULL, check_read_buffer_done, NULL)) {
    fprintf(stderr, "Error creating thread\n");
    return 1;
  }

  fprintf(stderr, "Done Spinning check read done thread\n");

#if not defined(SIMULATION)
  srand(time(NULL));
  blockBase=rand()%4096;
#endif

  fprintf(stderr, "Done initializing blockBase = %u\n", blockBase);
  
  fprintf(stderr, "FPGA starts\n");
  device->start(0);
  fprintf(stderr, "LOG: Starting Correctness TEST...\n");
  timespec start, now;
  clock_gettime(CLOCK_REALTIME, & start);
  
  for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
    for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
      for (int bus = 0; bus < NUM_BUSES; bus++){
        for (int card = 0; card < NUM_CARDS; card++){
          eraseBlock(card, bus, chip, blk, waitIdleEraseTag());
        }
      }
    }
  }

  
  while (true) {
    usleep(100);
    if ( getNumErasesInFlight() == 0 ) break;
  }

  clock_gettime(CLOCK_REALTIME, & now);
  fprintf(stderr, "LOG: finished erasing to flash! %f\n", timespec_diff_sec(start, now) );
  double total = 256*BLOCKS_PER_CHIP*CHIPS_PER_BUS*NUM_BUSES*NUM_CARDS*8192.0/1024.0/1024.0;
  fprintf(stderr, "LOG: erase %.4lf MB,  bw = %.4lf MB/s\n", total, total/timespec_diff_sec(start, now) );

  clock_gettime(CLOCK_REALTIME, & start);
  //read back erased pages
  for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
    for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
      for (int bus = 0; bus < NUM_BUSES; bus++){
        for (int card = 0; card < NUM_CARDS; card++){
          int page = 0;
          readPage(card, bus, chip, blk, page, waitIdleReadBuffer());
        }
      }
    }
  }
  while (true) {
    usleep(100);
    if ( getNumReadsInFlight() == 0 ) break;
  }
  clock_gettime(CLOCK_REALTIME, & now);
  fprintf(stderr, "LOG: finished checking erased flash pages! %f\n", timespec_diff_sec(start, now) );

  //write pages
  //FIXME: in old xbsv, simulatneous DMA reads using multiple readers cause kernel panic
  //Issue each bus separately for now
  clock_gettime(CLOCK_REALTIME, & start);

  for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
    for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
      for (int bus = 0; bus < NUM_BUSES; bus++){
        for (int card = 0; card < NUM_CARDS; card++ ){
          int page = 0;
          //get free tag
          int freeTag = waitIdleWriteBuffer();
          //fill write memory
          for (unsigned int w=0; w<PAGE_SIZE/sizeof(unsigned int); w++) {
            writeBuffers[freeTag][w] = hashAddrToData(card, bus, chip, blk, w);
          }
          //send request
          writePage(card, bus, chip, blk, page, freeTag);
        }
      }
    } //each bus
  }
  
  while (true) {
    usleep(100);
    if ( getNumWritesInFlight() == 0 ) break;
  }
  	
  clock_gettime(CLOCK_REALTIME, & now);
  fprintf(stderr, "LOG: finished writing to flash! %f\n", timespec_diff_sec(start, now) );
  total = BLOCKS_PER_CHIP*CHIPS_PER_BUS*NUM_BUSES*NUM_CARDS*8192.0/1024.0/1024.0;
  fprintf(stderr, "LOG: write %.4lf MB,  bw = %.4lf MB/s (this data is not accurate since it includes time for data generation)\n", total, total/timespec_diff_sec(start, now) );
  

#if defined(SIMULATION)
  int num_repeats = 1;
#else
  int num_repeats = 2000;
#endif
  clock_gettime(CLOCK_REALTIME, & start);


  // check card 0::
  for (int repeat = 0; repeat < num_repeats; repeat++){
    for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
      for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
        for (int bus = 0; bus < NUM_BUSES; bus++){
          for (int card = 0; card < NUM_CARDS; card++){

            //int blk = rand() % 1024;
            //int chip = rand() % 8;
            //int bus = rand() % 8;
            int page = 0;
            readPage(card, bus, chip, blk, page, waitIdleReadBuffer());
          }
        }
      }
    }
  }

  while (true) {
    usleep(100);
    if ( getNumReadsInFlight() == 0 ) break;
  }


  clock_gettime(CLOCK_REALTIME, & now);
  fprintf(stderr, "LOG: finished reading from page! %f\n", timespec_diff_sec(start, now) );
  total = num_repeats*BLOCKS_PER_CHIP*CHIPS_PER_BUS*NUM_BUSES*NUM_CARDS*8192.0/1024.0/1024.0;
  fprintf(stderr, "LOG: read %.4lf MB,  bw = %.4lf MB/s (this data is not accurate since it includes time for data generation)\n", total, total/timespec_diff_sec(start, now) );

  for ( int t = 0; t < NUM_TAGS; t++ ) {
    for ( unsigned int i = 0; i < PAGE_SIZE/sizeof(unsigned int); i++ ) {
      //fprintf(stderr,  "%x %x %x\n", t, i, readBuffers[t][i] );
    }
  }
  if (testPass==1) {
    fprintf(stderr, "LOG: Correctness TEST PASSED!\n");
  }
  else {
    fprintf(stderr, "LOG: **ERROR: Correctness TEST FAILED!\n");
  }

#if defined(SIMULATION)
  return 0;
#endif
  // read performance check:

  // this following makes no data checking on data read
  for (int blk=0; blk<BLOCKS_PER_CHIP; blk++) {
    for (int c=0; c<CHIPS_PER_BUS; c++) {
      for (int bus=0; bus< CHIPS_PER_BUS; bus++) {
        for (int card=0; card < NUM_CARDS; card++) {
          // fprintf(stderr,"flashStatus[%d][%d][%d][%d] = UNINIT\n",card,bus,c,blk);
          flashStatus[card][bus][c][blk] = UNINIT;
        }
      }
    }
  }

  
  fprintf(stderr, "LOG: Starting sequential read performance TEST...\n");
  // start read benchmark
  clock_gettime(CLOCK_REALTIME, & start);
  for (int repeat = 0; repeat < num_repeats; repeat++){
    for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
      for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
        for (int bus = 0; bus < NUM_BUSES; bus++){
          for (int card = 0; card < NUM_CARDS; card++){
            int page = 0;
            readPage(card, bus, chip, blk, page, waitIdleReadBuffer());
          }
        }
      }
    }
  }

  while (true) {
    usleep(100);
    if ( getNumReadsInFlight() == 0 ) break;
  }

  clock_gettime(CLOCK_REALTIME, & now);
  fprintf(stderr, "LOG: finished random reading from page! %f\n", timespec_diff_sec(start, now) );
  total = num_repeats*BLOCKS_PER_CHIP*CHIPS_PER_BUS*NUM_BUSES*NUM_CARDS*8192.0/1024.0/1024.0;
  fprintf(stderr, "LOG: sequential read %.4lf MB,  bw = %.4lf MB/s\n", total, total/timespec_diff_sec(start, now) );


  
  fprintf(stderr, "LOG: Starting random read performance TEST...\n");
#if not defined(SIMULATION)
  num_repeats = 1<<(32-13); // 4GB
#endif
  // start read benchmark
  clock_gettime(CLOCK_REALTIME, & start);
  for (int repeat = 0; repeat < num_repeats; repeat++){
    int blk = rand()%BLOCKS_PER_CHIP;
    int chip = rand()%CHIPS_PER_BUS;
    int bus = rand()%NUM_BUSES;
    int card = rand()%NUM_CARDS;
    int page = 0;
    readPage(card, bus, chip, blk, page, waitIdleReadBuffer());
  }

  while (true) {
    usleep(100);
    if ( getNumReadsInFlight() == 0 ) break;
  }


  clock_gettime(CLOCK_REALTIME, & now);
  fprintf(stderr, "LOG: finished random reading from page! %f\n", timespec_diff_sec(start, now) );
  // total = num_repeats*BLOCKS_PER_CHIP*CHIPS_PER_BUS*NUM_BUSES*NUM_CARDS*8192.0/1024.0/1024.0;
  total = num_repeats*8192.0/1024.0/1024.0;
  fprintf(stderr, "LOG: random read %.4lf MB,  bw = %.4lf MB/s\n", total, total/timespec_diff_sec(start, now) );

  platformStatistics();
}
