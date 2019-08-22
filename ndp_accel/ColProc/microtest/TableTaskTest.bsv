import Vector::*;
import ColXFormPE::*;
import BuildVector::*;
import NDPCommon::*;
import SimdAlu256::*;
import ColProc::*;
import EmulatedFlash::*;
import RowSelectorProgrammer::*;
import ColProcProgrammer::*;

////////////////////////////////////////////////////////////////////////////////
/// RowSelector Section
////////////////////////////////////////////////////////////////////////////////


typedef 4 ColCount_RowSel;                 
typedef TMul#(ColCount_RowSel,2) NDPCount_RowSel;

Bit#(64) denom = 10000;

function Bit#(64) genTotalRows();
   return getNumRows("l_shipdate")/denom;
endfunction
Int#(32) int_min = minBound;

function Vector#(ColCount_RowSel,RowSelectorParamT) genRowSelInfo();
   // let totalRows = getNumRows("l_shipdate")/100000;//genTotalRows();
   let totalRows = genTotalRows();
   Vector#(ColCount_RowSel,RowSelectorParamT) programInfo = cons(RowSelectorParamT{colType: Int,
                                                                                   numRows: totalRows,
                                                                                   baseAddr: getBaseAddr("l_shipdate")>>13,
                                                                                   forward: False,
                                                                                   allRows: True,
                                                                                   rdPort: 0,
                                                                                   lowTh:zeroExtend(pack(int_min)), 
                                                                                   hiTh:729999, 
                                                                                   isSigned:True, 
                                                                                   andNotOr:True },
      
                                                                 replicate(RowSelectorParamT{colType: ?,
                                                                                             numRows: totalRows,
                                                                                             baseAddr: 0,
                                                                                             forward: True,
                                                                                             allRows: ?,
                                                                                             rdPort: ?,
                                                                                             lowTh:?,
                                                                                             hiTh:?, 
                                                                                             isSigned:?, 
                                                                                             andNotOr:? }));
   // Vector#(ColCount_RowSel, RowSelectorParamT) programInfo = vec(RowSelectorParamT{colType: Int,
   //                                                                                 numRows: totalRows,
   //                                                                                 baseAddr: getBaseAddr("l_shipdate"),
   //                                                                                 forward: False,
   //                                                                                 allRows: True,
   //                                                                                 rdPort: 0,
   //                                                                                 lowTh:728294, 
   //                                                                                 hiTh:728658, 
   //                                                                                 isSigned:True, 
   //                                                                                 andNotOr:True },
                                                                 
   //                                                               RowSelectorParamT{colType: Long,
   //                                                                                 numRows: totalRows,
   //                                                                                 baseAddr: getBaseAddr("l_discount"),
   //                                                                                 forward: False,
   //                                                                                 allRows: False,
   //                                                                                 rdPort: 0,
   //                                                                                 lowTh:5, 
   //                                                                                 hiTh:7, 
   //                                                                                 isSigned:True, 
   //                                                                                 andNotOr:True },
                                                                 
   //                                                               RowSelectorParamT{colType: Int,
   //                                                                                 numRows: totalRows,
   //                                                                                 baseAddr: getBaseAddr("l_quantity"),
   //                                                                                 forward: False,
   //                                                                                 allRows: False,
   //                                                                                 rdPort: 0,
   //                                                                                 lowTh:zeroExtend(pack(int_min)), 
   //                                                                                 hiTh:23, 
   //                                                                                 isSigned:True, 
   //                                                                                 andNotOr:True },
                                                                 
   //                                                               RowSelectorParamT{colType: ?,
   //                                                                                 numRows: totalRows,
   //                                                                                 baseAddr: 0,
   //                                                                                 forward: True,
   //                                                                                 allRows: ?,
   //                                                                                 rdPort: ?,
   //                                                                                 lowTh:?,
   //                                                                                 hiTh:?, 
   //                                                                                 isSigned:?, 
   //                                                                                 andNotOr:? });

   return programInfo;
endfunction
////////////////////////////////////////////////////////////////////////////////
/// End of RowSelector Section
////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////
/// ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////
typedef 6 NumInCols; 
Integer numInCols = valueOf(NumInCols);
InColParamT inColInfo_returnflag  = InColParamT{colType:Byte, baseAddr:getBaseAddr("l_returnflag")>>13};
InColParamT inColInfo_linestatus  = InColParamT{colType:Byte, baseAddr:getBaseAddr("l_linestatus")>>13};
InColParamT inColInfo_quantity    = InColParamT{colType:Int,  baseAddr:getBaseAddr("l_quantity")>>13};
InColParamT inColInfo_extendprice = InColParamT{colType:Long, baseAddr:getBaseAddr("l_extendedprice")>>13};
InColParamT inColInfo_discount    = InColParamT{colType:Long, baseAddr:getBaseAddr("l_discount")>>13};
InColParamT inColInfo_tax         = InColParamT{colType:Long, baseAddr:getBaseAddr("l_tax")>>13};
Vector#(NumInCols, InColParamT) inColInfos = vec(inColInfo_returnflag  ,
                                                 inColInfo_linestatus  ,
                                                 inColInfo_quantity    ,
                                                 inColInfo_extendprice ,
                                                 inColInfo_discount    ,
                                                 inColInfo_tax         );
////////////////////////////////////////////////////////////////////////////////
/// End of ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////
/// ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////
typedef 6 NumOutCols; 
Integer numOutCols = valueOf(NumOutCols);
OutColParamT outColInfo_returnflag     = OutColParamT{colType:Byte, dest:Drain,     isSigned: False};
OutColParamT outColInfo_linestatus     = OutColParamT{colType:Byte, dest:Drain,     isSigned: False};
OutColParamT outColInfo_quantity       = OutColParamT{colType:Int,  dest:Aggregate, isSigned: True};
OutColParamT outColInfo_extended_price = OutColParamT{colType:Long, dest:Aggregate, isSigned: True};
OutColParamT outColInfo_discount_price = OutColParamT{colType:Long, dest:Aggregate, isSigned: True};
OutColParamT outColInfo_charge_price   = OutColParamT{colType:Long, dest:Aggregate, isSigned: True};
Vector#(NumOutCols, OutColParamT) outColInfos = vec(outColInfo_returnflag     ,
                                                    outColInfo_linestatus     ,
                                                    outColInfo_quantity       ,
                                                    outColInfo_extended_price ,
                                                    outColInfo_discount_price ,
                                                    outColInfo_charge_price   );
////////////////////////////////////////////////////////////////////////////////
/// End of ColProcReader Parameter Section
////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////
/// ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////

function Tuple2#(Vector#(ColXFormEngs, Bit#(4)), Vector#(ColXFormEngs, Vector#(8, Bit#(32)))) genTest();
   Integer numColEngs = valueOf(ColXFormEngs);
   Bit#(64) most_negative = 1<<63;
   Vector#(ColXFormEngs, Vector#(8, DecodeInst)) pePrograms = ?;//replicate(peProg);
   Vector#(ColXFormEngs, Integer) progLength = ?;//replicate(1);
   Integer i = 0;
   
   Vector#(8, DecodeInst) peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //rf
                                              DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //ls
                                              DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Int, outType: ?, imm: ?}, //quantity
                                              DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Long, outType: ?, imm: ?}, // extended_price
                                              DecodeInst{iType: AluImm, aluOp: Sub, isSigned: True, inType: Long, outType: ?, imm: 100}, // 1 - discount
                                              DecodeInst{iType: AluImm, aluOp: Add, isSigned: True, inType: Long, outType: ?, imm: 100}), // 1 + tax
                                          ?);

   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;

   
   peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //rf
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //ls
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Int, outType: ?, imm: ?}, //quantity
                       DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, inType: Long, outType: Long, imm: ?}, // copy extended_price
                       DecodeInst{iType: Alu,  aluOp: Mullo, isSigned: True, inType: Long, outType: ?, imm: 100}, // 1 - discount * extended_price
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Long, outType: ?, imm: ?}), // pass 1 + tax
                   ?);
   
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;
   
   
   peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //rf
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //ls
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Int, outType: ?, imm: ?}, //quantity
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Long, outType: ?, imm: ?}, // pass extended_price
                       DecodeInst{iType: Copy, aluOp: ?, isSigned: ?, inType: Long, outType: Long, imm: ?}, // copy 1 - discount * extended_price
                       DecodeInst{iType: Alu,  aluOp: Mullo, isSigned: True, inType: Long, outType: ?, imm: ?}), // (1 + tax) * (1 - discount * extended_price)
                   ?);
   
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;

   peProg = append(vec(DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //rf
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Byte, outType: ?, imm: ?}, //ls
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Int, outType: ?, imm: ?}, //quantity
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Long, outType: ?, imm: ?}, // pass extended_price
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Long, outType: ?, imm: ?}, // pass 1 - discount * extended_price
                       DecodeInst{iType: Pass, aluOp: ?, isSigned: ?, inType: Long, outType: ?, imm: ?}), // pass (1 + tax) * (1 - discount * extended_price)
                   ?);
   
   pePrograms[i] = peProg;
   progLength[i] = 6;
   i = i + 1;
   Vector#(ColXFormEngs, Bit#(4)) a = map(fromInteger, progLength);
   Vector#(ColXFormEngs, Vector#(8, Bit#(32))) b = unpack(pack(pePrograms));
   return tuple2(a, b);
endfunction

////////////////////////////////////////////////////////////////////////////////
/// End of ColEng Instruction Section
////////////////////////////////////////////////////////////////////////////////

Vector#(7, Bit#(64)) columnBeats = vec(4, 1, 1, 4, 8, 8, 8);
