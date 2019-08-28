#include "GeneratedTypes.h"
#include <limits.h>
#include <string>

uint64_t totalRows = 32;

RowSelectorParamT rowSel0 = {
 colType : Int,
 numRows : totalRows,
 baseAddr : 0,
 forward: 0,
 allRows: 1,
 rdPort: 0,
 lowTh:((uint64_t)INT_MIN), 
 hiTh:729999, 
 isSigned:1,
 andNotOr:1};


RowSelectorParam rowSelParam_0 = {
 colname:std::string("l_shipdate"),
 param:rowSel0};


RowSelectorParamT rowSelforward = {
 colType: Int,
 numRows : totalRows,
 baseAddr : 0,
 forward : true
};

RowSelectorParam rowSelforward_param = {
 colname:std::string("l_shipdate"),
 param:rowSelforward
};

uint8_t inCols = 6;

InColParamT inColInfo_returnflag  = InColParamT{.colType=Byte, .baseAddr=1};
InColParamT inColInfo_linestatus  = InColParamT{.colType=Byte, .baseAddr=2};
InColParamT inColInfo_quantity    = InColParamT{.colType=Int,  .baseAddr=3};
InColParamT inColInfo_extendprice = InColParamT{.colType=Long, .baseAddr=4};
InColParamT inColInfo_discount    = InColParamT{.colType=Long, .baseAddr=5};
InColParamT inColInfo_tax         = InColParamT{.colType=Long, .baseAddr=6};


InColParam inColparam_returnflag  = InColParam{.colname="returnflag" , .param=inColInfo_returnflag };
InColParam inColparam_linestatus  = InColParam{.colname="linestatus" , .param=inColInfo_linestatus };
InColParam inColparam_quantity    = InColParam{.colname="quantity"   , .param=inColInfo_quantity   };
InColParam inColparam_extendprice = InColParam{.colname="extendprice", .param=inColInfo_extendprice};
InColParam inColparam_discount    = InColParam{.colname="discount"   , .param=inColInfo_discount   };
InColParam inColparam_tax         = InColParam{.colname="tax"        , .param=inColInfo_tax        };


uint8_t outCols = 6;

OutColParamT outColInfo_returnflag   = OutColParamT{.colType=Byte, .dest=NDP_Drain,     .isSigned=0};
OutColParamT outColInfo_linestatus   = OutColParamT{.colType=Byte, .dest=NDP_Drain,     .isSigned=0};
OutColParamT outColInfo_quantity     = OutColParamT{.colType=Int,  .dest=NDP_Aggregate, .isSigned=1}; 
OutColParamT outColInfo_extendprice  = OutColParamT{.colType=Long, .dest=NDP_Aggregate, .isSigned=1}; 
OutColParamT outColInfo_disc_price   = OutColParamT{.colType=Long, .dest=NDP_Aggregate, .isSigned=1}; 
OutColParamT outColInfo_charge_price = OutColParamT{.colType=Long, .dest=NDP_Aggregate, .isSigned=1}; 


OutColParam outColparam_returnflag   = OutColParam{.colname="returnflag"      , .param=outColInfo_returnflag  };
OutColParam outColparam_linestatus   = OutColParam{.colname="linestatus"      , .param=outColInfo_linestatus  };
OutColParam outColparam_quantity     = OutColParam{.colname="quantity"        , .param=outColInfo_quantity    };
OutColParam outColparam_extendprice  = OutColParam{.colname="extendprice"     , .param=outColInfo_extendprice };
OutColParam outColparam_disc_price   = OutColParam{.colname="discounted_price", .param=outColInfo_disc_price  };
OutColParam outColparam_charge_price = OutColParam{.colname="charged_price"   , .param=outColInfo_charge_price};



DecodeInst peProg_0[8] = {DecodeInst{.iType=Pass,   .inType=Byte}, //pass rf
						  DecodeInst{.iType=Pass,   .inType=Byte}, //pass ls
						  DecodeInst{.iType=Pass,   .inType=Int }, //pass quantity
						  DecodeInst{.iType=Pass,   .inType=Long}, //pass extended_price
						  DecodeInst{.iType=AluImm, .inType=Long, .outType=Long, .aluOp=Sub, .isSigned=true, .imm=100}, //1 - discount
						  DecodeInst{.iType=AluImm, .inType=Long, .outType=Long, .aluOp=Add, .isSigned=true, .imm=100} //1 + tax
                         };


DecodeInst peProg_1[8] = {DecodeInst{.iType=Pass, .inType=Byte}, //pass rf
						  DecodeInst{.iType=Pass, .inType=Byte}, //pass ls
						  DecodeInst{.iType=Pass, .inType=Int }, //pass quantity
						  DecodeInst{.iType=Copy, .inType=Long, .outType=Long}, //copy extended_price
						  DecodeInst{.iType=Alu,  .inType=Long, .outType=Long, .aluOp=Mullo, .isSigned=true}, //(1-discount)*extended_price
						  DecodeInst{.iType=Pass, .inType=Long} //pass 1+tax
                         };

DecodeInst peProg_2[8] = {DecodeInst{.iType=Pass, .inType=Byte}, //pass rf
						  DecodeInst{.iType=Pass, .inType=Byte}, //pass ls
						  DecodeInst{.iType=Pass, .inType=Int }, //pass quantity
						  DecodeInst{.iType=Pass, .inType=Long}, //pass extended_price
						  DecodeInst{.iType=Copy, .inType=Long, .outType=Long}, //copy (1-discount)*extended_price
						  DecodeInst{.iType=Alu,  .inType=Long, .outType=Long, .aluOp=Mullo, .isSigned=true} // (1+tax)*(1-discount)*extended_price
                         };

DecodeInst peProg_3[8] = {DecodeInst{.iType=Pass, .inType=Byte}, //pass rf
						  DecodeInst{.iType=Pass, .inType=Byte}, //pass ls
						  DecodeInst{.iType=Pass, .inType=Int }, //pass quantity
						  DecodeInst{.iType=Pass, .inType=Long}, //pass extended_price
						  DecodeInst{.iType=Pass, .inType=Long}, //pass (1-discount)*extended_price
						  DecodeInst{.iType=Pass, .inType=Long}  //pass (1+tax)*(1-discount)*extended_price
                         };






TableTask task = TableTask{
	.numRows=totalRows,
	.rowSels={rowSelParam_0, rowSelforward_param, rowSelforward_param, rowSelforward_param},
	.numInCols=6,
	.inCols={inColparam_returnflag ,
			 inColparam_linestatus ,
			 inColparam_quantity   ,
			 inColparam_extendprice,
			 inColparam_discount   ,
			 inColparam_tax         },
	.programLength={6,6,6,6},
	.colXInsts={{peProg_0[0],peProg_0[1],peProg_0[2],peProg_0[3],peProg_0[4],peProg_0[5],peProg_0[6],peProg_0[7]},
				{peProg_1[0],peProg_1[1],peProg_1[2],peProg_1[3],peProg_1[4],peProg_1[5],peProg_1[6],peProg_1[7]},
				{peProg_2[0],peProg_2[1],peProg_2[2],peProg_2[3],peProg_2[4],peProg_2[5],peProg_2[6],peProg_2[7]},
				{peProg_3[0],peProg_3[1],peProg_3[2],peProg_3[3],peProg_3[4],peProg_3[5],peProg_3[6],peProg_3[7]}},
	.numOutCols=6,
	.outCols={outColparam_returnflag  ,
			  outColparam_linestatus  ,
			  outColparam_quantity    ,
			  outColparam_extendprice ,
			  outColparam_disc_price  ,
			  outColparam_charge_price}};



