#ifndef __ISSP_PROGRAMMER__
#define __ISSP_PROGRAMMER__

#include "GeneratedTypes.h"
#include "RowSelectorProgramIfc.h"
#include "InColProgramIfc.h"
#include "ColXFormProgramIfc.h"
#include "OutColProgramIfc.h"
#include <string>

#define NUM_SELS         4
#define NUM_COLS         8
#define NUM_COLXFORM_PES 4

#ifdef __cplusplus
extern "C" {
#endif
typedef struct RowSelectorParam{
    std::string colname;
	std::string filename;
    RowSelectorParamT param;
} RowSelectorParam;

typedef struct InColParam{
    std::string colname;
	std::string filename;
    InColParamT param;
} InColParam;


typedef struct OutColParam{
    std::string colname;
    OutColParamT param;
} OutColParam;


typedef struct TableTask{
    uint64_t         numRows;
    RowSelectorParam rowSels[NUM_SELS];
    uint8_t          numInCols;
    InColParam       inCols[NUM_COLS];
    uint8_t          programLength[NUM_COLXFORM_PES];
    DecodeInst       colXInsts[NUM_COLXFORM_PES][8];
    uint8_t          numOutCols;
    OutColParam      outCols[NUM_COLS];
} TableTask;
#ifdef __cplusplus
}
#endif

class ISSPProgrammer{
public:
    ISSPProgrammer();
    ~ISSPProgrammer();
    void sendTableTask(TableTask* task);
private:

    uint32_t encode(DecodeInst inst);
    static bool devInit;
    static RowSelectorProgramIfcProxy* program_rowSel  ;
    static InColProgramIfcProxy*       program_inCol   ;
    static ColXFormProgramIfcProxy*    program_colXform;
    static OutColProgramIfcProxy*      program_outCol  ;

    static void init_device();
    static void destory_device();
};

#endif
