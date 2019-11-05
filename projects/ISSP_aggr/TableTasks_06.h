#include "GeneratedTypes.h"
#include <limits.h>
#include <string>



#ifdef SIMULATION
uint64_t	totalRows = 1799989091/10000;
std::string db_path	  = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
#else
uint64_t	totalRows = 1799989091;
std::string db_path   = "bat/";
#endif
std::string l_shipdate      = "10/1051.tail";
std::string l_returnflag    = "10/1047.tail";
std::string l_linestatus    = "10/1050.tail";
std::string l_quantity      = "10/1043.tail";
std::string l_extendedprice = "10/1044.tail";
std::string l_discount      = "10/1045.tail";
std::string l_tax           = "10/1046.tail";



RowSelectorParamT rowSel0 = {
    .colType  = Int,
    .numRows  = totalRows,
    .baseAddr = 0,
    .forward  = false,
    .allRows  = true,
    .rdPort   = 0,
    .lowTh    = ((uint64_t)728294),
    .hiTh     = ((uint64_t)728658),
    // .lowTh    = ((uint64_t)INT_MIN),
    // .hiTh     = ((uint64_t)INT_MAX), 
    .isSigned = 1,
    .andNotOr = 1};


RowSelectorParam rowSelParam_0 = {
    .colname  = "l_shipdate",
    .filename = db_path+l_shipdate,
    .param    = rowSel0};


RowSelectorParamT rowSel1 = {
    .colType  = Long,
    .numRows  = totalRows,
    .baseAddr = 0,
    .forward  = false,
    .allRows  = false,
    .rdPort   = 0,
    .lowTh    = ((uint64_t)5),
    .hiTh     = ((uint64_t)7),
    // .lowTh    = ((uint64_t)LONG_MIN),
    // .hiTh     = ((uint64_t)LONG_MAX), 
    .isSigned = 1,
    .andNotOr = 1};

RowSelectorParam rowSelParam_1 = {
    .colname  = "l_discount",
    .filename = db_path+l_discount,
    .param    = rowSel1};


RowSelectorParamT rowSel2 = {
    .colType  = Int,
    .numRows  = totalRows,
    .baseAddr = 0,
    .forward  = false,
    .allRows  = false,
    .rdPort   = 0,
    .lowTh    = ((uint64_t)INT_MIN),
    .hiTh     = ((uint64_t)23),
    // .lowTh    = ((uint64_t)INT_MIN),
    // .hiTh     = ((uint64_t)INT_MAX), 
    .isSigned = 1,
    .andNotOr = 1};

RowSelectorParam rowSelParam_2 = {
    .colname  = "l_quantity",
    .filename = db_path+l_quantity,
    .param    = rowSel2};



RowSelectorParamT rowSelforward = {
    .colType  = Int,
    .numRows  = totalRows,
    .baseAddr = 0,
    .forward  = true};

RowSelectorParam rowSelforward_param = {
    .colname  = "empty",
    .filename = "",
    .param    = rowSelforward};

uint8_t inCols = 2;

InColParamT inColInfo_extendedprice = InColParamT{.colType=Long, .baseAddr=4};
InColParamT inColInfo_discount      = InColParamT{.colType=Long, .baseAddr=5};

InColParam  inColparam_extendedprice = InColParam{.colname="extendedprice", .filename=db_path+l_extendedprice, .param=inColInfo_extendedprice};
// InColParam  inColparam_discount      = InColParam{.colname="discount"     , .filename=db_path+l_tax     , .param=inColInfo_discount     };
InColParam  inColparam_discount      = InColParam{.colname="discount"     , .filename=db_path+l_discount     , .param=inColInfo_discount     };


uint8_t outCols = 1;

OutColParamT outColInfo_disc_price   = OutColParamT{.colType=Long, .dest=NDP_Aggregate, .isSigned=1}; 

OutColParam outColparam_disc_price   = OutColParam{.colname="discounted_price", .param=outColInfo_disc_price  };



DecodeInst peProg_0[8] = {// DecodeInst{.iType=Pass,   .inType=Byte}, //pass rf
                          // DecodeInst{.iType=Pass,   .inType=Byte}, //pass ls
                          // DecodeInst{.iType=Pass,   .inType=Int }, //pass quantity
                          DecodeInst{.iType=Store, .inType=Long, .outType=Long}, //Store extended_price
                          DecodeInst{.iType=Alu,  .inType=Long, .outType=Long, .aluOp=Mullo, .isSigned=true} //(discount)*extended_price
                          // DecodeInst{.iType=AluImm, .inType=Long, .outType=Long, .aluOp=Sub, .isSigned=true, .imm=100} //1 - discount
                          // DecodeInst{.iType=AluImm, .inType=Long, .outType=Long, .aluOp=Add, .isSigned=true, .imm=100} //1 + tax
                         };


DecodeInst peProg_1[8] = {// DecodeInst{.iType=Pass, .inType=Byte}, //pass rf
                          // DecodeInst{.iType=Pass, .inType=Byte}, //pass ls
                          // DecodeInst{.iType=Pass, .inType=Int }, //pass quantity
                          // DecodeInst{.iType=Store, .inType=Long, .outType=Long}, //copy extended_price
                          // DecodeInst{.iType=Alu,  .inType=Long, .outType=Long, .aluOp=Mullo, .isSigned=true} //(1-discount)*extended_price
                          DecodeInst{.iType=Pass, .inType=Long, .outType=Long} //pass discount*extended_price
                          // DecodeInst{.iType=Pass, .inType=Long} //pass 1+tax
                         };

DecodeInst peProg_2[8] = {// DecodeInst{.iType=Pass, .inType=Byte}, //pass rf
                          // DecodeInst{.iType=Pass, .inType=Byte}, //pass ls
                          // DecodeInst{.iType=Pass, .inType=Int }, //pass quantity
                          // DecodeInst{.iType=Pass, .inType=Long}, //pass extended_price
                          DecodeInst{.iType=Pass, .inType=Long, .outType=Long} //pass discount*extended_price
                          // DecodeInst{.iType=Alu,  .inType=Long, .outType=Long, .aluOp=Mullo, .isSigned=true} // (1+tax)*(1-discount)*extended_price
                         };

DecodeInst peProg_3[8] = {// DecodeInst{.iType=Pass, .inType=Byte}, //pass rf
                          // DecodeInst{.iType=Pass, .inType=Byte}, //pass ls
                          // DecodeInst{.iType=Pass, .inType=Int }, //pass quantity
                          // DecodeInst{.iType=Pass, .inType=Long}, //pass extended_price
                          DecodeInst{.iType=Pass, .inType=Long} //pass discount*extended_price
                          // DecodeInst{.iType=Pass, .inType=Long}  //pass (1+tax)*(1-discount)*extended_price
                         };






TableTask task = TableTask{
    .numRows=totalRows,
    .rowSels={rowSelParam_0, rowSelParam_1, rowSelParam_2, rowSelforward_param},
    // .rowSels={rowSelParam_1, rowSelParam_0, rowSelforward_param, rowSelforward_param},
    // .rowSels={rowSelParam_0, rowSelParam_2, rowSelforward_param, rowSelforward_param},
    // .rowSels={rowSelParam_0, rowSelforward_param, rowSelforward_param, rowSelforward_param},
    .numInCols=2,
    .inCols={inColparam_extendedprice,
             inColparam_discount },
    .programLength={2,1,1,1},
    .colXInsts={{peProg_0[0],peProg_0[1],peProg_0[2],peProg_0[3],peProg_0[4],peProg_0[5],peProg_0[6],peProg_0[7]},
                {peProg_1[0],peProg_1[1],peProg_1[2],peProg_1[3],peProg_1[4],peProg_1[5],peProg_1[6],peProg_1[7]},
                {peProg_2[0],peProg_2[1],peProg_2[2],peProg_2[3],peProg_2[4],peProg_2[5],peProg_2[6],peProg_2[7]},
                {peProg_3[0],peProg_3[1],peProg_3[2],peProg_3[3],peProg_3[4],peProg_3[5],peProg_3[6],peProg_3[7]}},
    .numOutCols=1,
    .outCols={outColparam_disc_price}};



