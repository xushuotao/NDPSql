#ifndef _FlashManger_
#define _FlashManger_

#include "dmaManager.h"
#include "FlashIndication.h"
#include "FlashRequest.h"

#include "mmap_util.h"
#include <string>

#include "filemap.h"

#include <boost/lockfree/queue.hpp>
#include <atomic>

namespace lockfree = boost::lockfree;
 

#define TYPE_BYTE 0
#define TYPE_INT  1
#define TYPE_LONG 2

#define DMABUF_SIZE     (8192*2)
#define PAGE_SIZE_VALID (8224)
#define NUM_TAGS        128


#define LG_PAGE_SIZE 13
#define PAGE_SIZE (1<<LG_PAGE_SIZE)



#ifdef CntrlUndefBSIM
#undef BSIM
#endif


#if defined(BSIM)
#define	LG_PAGES_PER_BLOCK 4
#define LG_BLOCKS_PER_CHIP 7
#define LG_CHIPS_PER_BUS   3
#define LG_NUM_BUSES       3
#define LG_NUM_CARDS       1
// #define	PAGES_PER_BLOCK 16
// #define BLOCKS_PER_CHIP 128
// #define CHIPS_PER_BUS 8
// #define NUM_BUSES 8
// #define NUM_CARDS 2
#else
#define	LG_PAGES_PER_BLOCK 8
#define LG_BLOCKS_PER_CHIP 12
#define LG_CHIPS_PER_BUS   3
#define LG_NUM_BUSES       3
#define LG_NUM_CARDS       1
// #define	PAGES_PER_BLOCK 256
// #define BLOCKS_PER_CHIP 4096
// #define CHIPS_PER_BUS 8
// #define NUM_BUSES 8
// #define NUM_CARDS 2
#endif

#define	PAGES_PER_BLOCK (1UL<<LG_PAGES_PER_BLOCK)
#define BLOCKS_PER_CHIP (1UL<<LG_BLOCKS_PER_CHIP)
#define CHIPS_PER_BUS   (1UL<<LG_CHIPS_PER_BUS)
#define NUM_BUSES		(1UL<<LG_NUM_BUSES)
#define NUM_CARDS       (1UL<<LG_NUM_CARDS)

#define SUPER_BLK_SZ	(1UL<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))
#define TOTAL_BLKS		(1<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS+LG_BLOCKS_PER_CHIP))

#define FILEMAP_EXT     "/bdbm.fm"
#define META_EXT		"/bdbm.meta"  
#define FLASHSTATUS_EXT "/bdbm.fstat"
#define FTL_EXT         "/bdbm.ftl"

#define UNMAPPED (uint64_t)-1


#define FILE_DIR_SIZE 50

typedef uint32_t uint;
typedef uint64_t ulng;

typedef struct {
    bool busy;
    ulng base;
    ulng size;
} FileDirectoryEntry;

// page address mapping:: real flash
// 12                 + 8                 + 3               + 3           + 1 = 27 bit
// [LG_BLOCKS_PER_CHIP][LG_PAGES_PER_BLOCK][LG_CHIPS_PER_BUS][LG_NUM_BUSES][LG_NUM_CARDS]

// page address mapping:: sim flash
// 7                  + 4                 + 3               + 3           + 1 = 18 bit
// [LG_BLOCKS_PER_CHIP][LG_PAGES_PER_BLOCK][LG_CHIPS_PER_BUS][LG_NUM_BUSES][LG_NUM_CARDS]


#define PGADDR2CARDID(addr)		(addr&(NUM_CARDS-1))	// WARNING:: this requires NUM_CARDS is power of 2
#define PGADDR2BUSID(addr)		((addr>>LG_NUM_CARDS)&(NUM_BUSES-1))
#define PGADDR2CHIPID(addr)		((addr>>(LG_NUM_CARDS+LG_NUM_BUSES))&(CHIPS_PER_BUS-1))
#define PGADDR2PGID(addr)		((addr>>(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))&(PAGES_PER_BLOCK-1))
#define PGADDR2BLKID(addr)		((addr>>(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS+LG_PAGES_PER_BLOCK))&(BLOCKS_PER_CHIP-1))

#define BLKADDR2CARDID(addr)	PGADDR2CARDID(addr)
#define BLKADDR2BUSID(addr)		PGADDR2BUSID(addr) 
#define BLKADDR2CHIPID(addr)	PGADDR2CHIPID(addr)
#define BLKADDR2BLKID(addr)		((addr>>(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))&(BLOCKS_PER_CHIP-1))
#define PGADDR2BLKADDR(addr)	((addr&((1UL<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))-1)) |	\
								 ((addr>>LG_PAGES_PER_BLOCK)&(~((1UL<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))-1))))

#define BLKADDR2PAGEADDR(blkaddr, pageid) (((blkaddr<<LG_PAGES_PER_BLOCK)&	\
											(~((1UL<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS+LG_PAGES_PER_BLOCK))-1))) |	\
										   ((blkaddr)&((1UL<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))-1)) |	\
										   ((pageid<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))&	\
											(~((1UL<<(LG_NUM_CARDS+LG_NUM_BUSES+LG_CHIPS_PER_BUS))-1))))


namespace fm = filemap_namespace;

typedef enum {
    UNINIT,
    ERASED,
    BAD
} FlashStatusT;

  
typedef struct {
    bool     busy;
    uint64_t addr;
    uint64_t addr2;
} TagTableEntry;

typedef struct {
    bool   busy;
    int    tag;
    int    fildes;
    size_t offset;
    void*  buf_ptr;
    int    id;
} read_cb;

// #define DEBUG

#ifdef DEBUG
#define DEBUG_PRINT(...) do{ fprintf( stderr, __VA_ARGS__ ); } while( false )
#else
#define DEBUG_PRINT(...) do{ } while ( false )
#endif

void print_progress(std::string message, uint64_t norm, uint64_t denom);


class FlashManager{

public:

    FlashManager(std::string basedir);
    ~FlashManager();

    int			openfile(std::string file_name);
    void		closefile(int fd);

    size_t		filesize(int fd);
	
    bool		aio_read_page(read_cb* cb);
    bool		aio_return(read_cb* cb);
    bool		aio_done(read_cb* cb);
	
    void		writefile(std::string file_name, const char* buf, size_t length);

	// accelerator-related api
	uint32_t	getPhysPageAddr(int fd, size_t byteOffset);
  

private:

    static pthread_spinlock_t lock;

    static lockfree::queue<int> tagQueue;

    static lockfree::queue<ulng>* eraseJobQ;

    static std::atomic_int inflightErases;
    static std::atomic_int inflightWrites;
    static std::atomic_int inflightReads;
  
    static std::atomic_uint  goodBlocksErased;
    static std::atomic_ulong nexteraseblk;

    static TagTableEntry readTagTable[NUM_TAGS]; 
    static TagTableEntry writeTagTable[NUM_TAGS]; 
    static TagTableEntry eraseTagTable[NUM_TAGS];

    FileDirectoryEntry fdir[FILE_DIR_SIZE];

    int  waitIdleTag();
    bool eraseIfnecessary(size_t length);
    void eraseBlock(uint64_t logic_blk, uint64_t phys_blk);
    void append(const char* buf, size_t length);
  
    class FlashIndication : public FlashIndicationWrapper{
    public:
        virtual void readDone(unsigned int tag, uint64_t cycles) {
            fprintf(stderr, "ERROR: pagedone: no indication should be really sent");
        }

        virtual void writeDone(unsigned int tag, uint64_t cycles) {
            DEBUG_PRINT("LOG: writedone, tag=%d, FPGA cycles = %lu\n", tag, cycles);
            while (!tagQueue.push(tag));
            inflightWrites--;
        }

        virtual void eraseDone(unsigned int tag, unsigned int status, uint64_t cycles) {
            DEBUG_PRINT("LOG: eraseDone, tag=%d, status=%d, FPGA cycles = %lu\n", tag, status, cycles);

            pthread_spin_lock(&lock);
            uint64_t	phy_blk  = eraseTagTable[tag].addr;
            uint64_t	lgc_blk  = eraseTagTable[tag].addr2;
            flashStatus[phy_blk] = status == 0  ? ERASED : BAD;
      
            if (status == 0) {
                goodBlocksErased++;
                ftl[lgc_blk]  = phy_blk;
                DEBUG_PRINT("LOG:: eraseDone ftl[%lu]=%lu\n", lgc_blk, phy_blk);
            } else {
                fprintf(stderr, "LOG: detected bad block with tag = %d, lgc_blk=%lu, phy_blk=%lu\n", tag, lgc_blk, phy_blk);
                while( !eraseJobQ->push(lgc_blk) );
            }
            pthread_spin_unlock(&lock);

            inflightErases--;
      
            while (!tagQueue.push(tag));
        }

        virtual void debugDumpResp (unsigned int card, unsigned int debug0, unsigned int debug1,  unsigned int debug2, unsigned int debug3, unsigned int debug4, unsigned int debug5) {
            DEBUG_PRINT( "LOG: DEBUG DUMP: card = %d, gearSend = %d, gearRec = %d, aurSend = %d, aurRec = %d, readSend=%d, writeSend=%d\n",card, debug0, debug1, debug2, debug3, debug4, debug5);
        }

        FlashIndication(unsigned int id) : FlashIndicationWrapper(id){}
    };

    std::string dirname;

    FlashRequestProxy *device;
    DmaManager        *dma;
    FlashIndication   *testIndication;   //(IfcNames_FlashIndicationH2S);

    pthread_cond_t flashFreeTagCond;

    
    // dma buffer related 8k(16k)*128
    int          dstAlloc; 
    int          srcAlloc;
    unsigned int ref_dstAlloc; 
    unsigned int ref_srcAlloc; 
    char*        dstBuffer;
    char*        srcBuffer;
    static char* readBuffers[NUM_TAGS];
    static char* writeBuffers[NUM_TAGS];
    
    


    void init_device();
    void destroy_device();

    void init_fs();
    void destroy_fs();
    
  
    int addrMapping(uint64_t addr, uint32_t &card, uint32_t &bus, uint32_t &chip, uint32_t &page);

    std::string basename;

    FRec*                frec_flashstatus;
    //[NUM_CARDS][NUM_BUSES][CHIPS_PER_BUS][BLOCKS_PER_CHIP];
    static FlashStatusT *flashStatus;
    
    FRec* frec_ftl;
    //[NUM_CARDS][NUM_BUSES][CHIPS_PER_BUS][BLOCKS_PER_CHIP];
    static uint64_t* ftl;
    
    FRec*       frec_meta;
    uint64_t*   meta;
    // uint32_t base_block_id;
    // uint64_t next_addr;

    fm::filemap* fmap;
    // uint32_t* ftl;
};

#endif
