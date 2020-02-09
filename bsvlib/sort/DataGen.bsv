import Vector::*;
import Pipe::*;
import LFSR::*;
import FIFOF::*;
import GetPut::*;


interface DataGen#(numeric type vSz, type dType);
   method Action initSeed(dType seed);
   method Action start(Bit#(32) totalIter, Bit#(2) sortness);
   method Tuple2#(Bit#(32), Bit#(32)) status;
   method ActionValue#(Bit#(TAdd#(TLog#(vSz),128))) getSum;
   interface PipeOut#(Vector#(vSz, dType)) dataPort;
endinterface


module mkDataGen#(
   Integer totalElms,
   function module#(LFSR#(Bit#(dSz))) mklfsr(),
   function dType genElem(Bit#(32) elemId)
   ) (DataGen#(vSz, dType)) provisos (
      Bits#(dType, dSz),
      Add#(a__, dSz, 128),
      Add#(b__, 1, vSz)
      );
   Reg#(Bit#(2)) genType <- mkRegU;
   
   Reg#(Bit#(TLog#(vSz))) seedInitCnt <- mkReg(0);
   
   Reg#(Bit#(32)) iterCnt <- mkReg(0);
   Reg#(Bit#(32)) elemCnt <- mkReg(0);
   
   Vector#(vSz, LFSR#(Bit#(dSz))) lfsr <- replicateM(mklfsr);
   
   // FIFOF#(Vector#(vSz, dType)) dataQ <- mkFIFOF;
   Vector#(vSz, FIFOF#(Tuple3#(Bool, Bit#(TAdd#(TLog#(vSz), dSz)), Vector#(vSz, dType)))) dataQ <- replicateM(mkFIFOF);
   
   rule genRandData if ( iterCnt > 0 && genType == 2);
      function t getValue(LFSR#(t) x) = x.value;
      function nextValue(x) = x.next;
   
      let last = False;
      if ( elemCnt + fromInteger(valueOf(vSz)) >= fromInteger(totalElms) ) begin              
         elemCnt <= 0;
         iterCnt <= iterCnt - 1;
         if ( iterCnt == 1) last = True;
      end
      else begin
         elemCnt <= elemCnt + fromInteger(valueOf(vSz));
      end
   
      Vector#(vSz, dType) inV = map(unpack, map(getValue, lfsr));
      mapM_(nextValue, lfsr);
      dataQ[0].enq(tuple3(last, zeroExtend(pack(inV[0])), inV));      
   endrule
   
   rule genSortedData if (iterCnt > 0 && genType == 0);
      let last = False;
      if ( elemCnt + fromInteger(valueOf(vSz)) >= fromInteger(totalElms) ) begin              
         elemCnt <= 0;
         iterCnt <= iterCnt - 1;
         if ( iterCnt == 1) last = True;
      end
      else begin
         elemCnt <= elemCnt + fromInteger(valueOf(vSz));
      end
   
      Vector#(vSz, dType) inV = map(genElem, zipWith(\+ , replicate(elemCnt), genWith(fromInteger)));
      dataQ[0].enq(tuple3(last,zeroExtend(pack(inV[0])), inV));
   endrule
   
   rule genRevSortedData if (iterCnt > 0 && genType == 1);
      let last = False;
      if ( elemCnt + fromInteger(valueOf(vSz)) >= fromInteger(totalElms) ) begin              
         elemCnt <= 0;
         iterCnt <= iterCnt - 1;
         if ( iterCnt == 1) last = True;
      end
      else begin
         elemCnt <= elemCnt + fromInteger(valueOf(vSz));
      end
   
      Vector#(vSz, dType) inV = map(genElem, zipWith(\- , replicate(fromInteger(totalElms-1) - elemCnt), genWith(fromInteger))); 
      dataQ[0].enq(tuple3(last, zeroExtend(pack(inV[0])), inV));
   endrule
   
   for (Integer i = 0; i < valueOf(vSz)-1; i = i + 1) begin
      rule addSum;
         let {last, sum, inV} = dataQ[i].first;
         dataQ[i].deq;
         sum = sum + zeroExtend(pack(inV[i+1]));
         dataQ[i+1].enq(tuple3(last, sum, inV));
      endrule
   end
   Reg#(Bit#(TAdd#(TLog#(vSz),128))) sumReg <- mkReg(0);
   FIFOF#(Bit#(TAdd#(TLog#(vSz), 128))) sumQ <- mkFIFOF;
   
   method Action start(Bit#(32) totalIter, Bit#(2) sortness) if (iterCnt == 0);
      iterCnt <= totalIter;
      genType <= sortness;
   endmethod
   
   method Action initSeed(dType seed);
      seedInitCnt <= seedInitCnt == fromInteger(valueOf(vSz)-1) ? 0: seedInitCnt + 1;
      lfsr[seedInitCnt].seed(pack(seed));
   endmethod
   
  method Tuple2#(Bit#(32), Bit#(32)) status;
     return tuple2(iterCnt, elemCnt);
  endmethod
   
  method ActionValue#(Bit#(TAdd#(TLog#(vSz),128))) getSum = toGet(sumQ).get;
   
  interface PipeOut dataPort;
     method Vector#(vSz, dType) first; 
        return tpl_3(last(dataQ).first);
     endmethod
     method Action deq;
        let {l, sum, dummy} = last(dataQ).first;
        last(dataQ).deq;
   
        if ( l ) begin
           sumReg <= 0;
           sumQ.enq(zeroExtend(sum) + sumReg);
        end
        else begin
           sumReg <= zeroExtend(sum) + sumReg;
        end
     endmethod
     method Bool notEmpty = last(dataQ).notEmpty;
  endinterface

endmodule

   

module mkUInt32Test(Empty);
   function UInt#(32) genElm(Bit#(32) v) = unpack(v);
   // function module#(LFSR#(Bit#(32))) mkLFSR() = mkLFSR_32;
   DataGen#(16, UInt#(32)) gen <- mkDataGen(32,
                                            mkLFSR_32,
                                            genElm
                                            );
   Reg#(Bit#(2)) genType <- mkReg(0);
   rule genStart (genType < 3);
      $display("%b", 32'h80000057);
      gen.start(4, genType);
      genType <= genType + 1;
   endrule
   
   rule getData;
      let v = gen.dataPort.first;
      gen.dataPort.deq;
      $display("%t ", $time, fshow(v));
   endrule
endmodule

module mkUInt64Test(Empty);
   function UInt#(64) genElm(Bit#(32) v) = unpack(zeroExtend(v));
   let feed = 64'h800000000000000D;
   function module#(LFSR#(Bit#(64))) mkLFSR_64() = mkFeedLFSR(feed);

   DataGen#(8, UInt#(64)) gen <- mkDataGen(32,
                                           mkLFSR_64,
                                           genElm                                           
                                           );
   Reg#(Bit#(2)) genType <- mkReg(0);
   rule genStart (genType < 3);
      $display("%b", feed);
      gen.start(4, genType);
      genType <= genType + 1;
   endrule
   
   rule getData;
      let v = gen.dataPort.first;
      gen.dataPort.deq;
      $display("%t ", $time, fshow(v));
   endrule
endmodule

module mkUInt128Test(Empty);
   function UInt#(128) genElm(Bit#(32) v) = unpack(zeroExtend(v));
   let feed = 128'h80000000000000000000000000000043;
   function module#(LFSR#(Bit#(128))) mkLFSR_128() = mkFeedLFSR(feed);

   DataGen#(4, UInt#(128)) gen <- mkDataGen(32,
                                           mkLFSR_128,
                                           genElm                                           
                                           );
   Reg#(Bit#(2)) genType <- mkReg(0);
   rule genStart (genType < 3);
      $display("%b", feed);
      gen.start(4, genType);
      genType <= genType + 1;
   endrule
   
   rule getData;
      let v = gen.dataPort.first;
      gen.dataPort.deq;
      $display(fshow(v));
   endrule
endmodule

