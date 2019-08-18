import Pipe::*;
import ClientServer::*;
import Vector::*;
import ClientServerHelper::*;
import FirstColReader::*;
import ColReader::*;
import NDPCommon::*;
import Connectable::*;
import FlashCtrlIfc::*;
import RowMask::*;
import GetPut::*;
import PredicateEval::*;
import OneToNRouter::*;
import DualFlashPageBuffer::*;


interface ProgramRowSelector#(numeric type num);
   interface PipeIn#(Tuple2#(Bit#(TLog#(num)), Bit#(5))) setColBytesPort;
   interface PipeIn#(Tuple2#(Bit#(TLog#(num)), ParamT)) setParamPort;
endinterface


interface RowSelector#(numeric type num);
   // interface Vector#(num, Client#(DualFlashAddr, Bit#(256))) flashRdClients;
   interface Vector#(num, PageBufferClient#(PageBufSz)) pageBufferClients;
   interface Client#(Bit#(9), void) reserveRowVecs;
   interface Vector#(num, Client#(RowMaskRead, RowVectorMask)) rowMaskReads;
   interface Vector#(num, Get#(RowMaskWrite)) rowMaskWrites;
   
   interface PipeOut#(RowVecReq) rowVecReq;
   
   interface ProgramRowSelector#(TMul#(num,2)) programIfc;
endinterface


module mkRowSelector(RowSelector#(n)) provisos (
   Add#(1, a__, n),
   Add#(TMul#(n, 2), b__, TMul#(TDiv#(TMul#(n, 2), 2), 2)),
   Add#(1, c__, TMul#(TDiv#(TMul#(n, 2), 2), 2)),
   Add#(1, d__, TMul#(n, 2)));
   
   let firstColFilter <- mkFirstPredicateEval;
   
   Vector#(TSub#(n,1), PredicateEval) colFilters <- replicateM(mkPredicateEval);
   
   // function to assemble flashRdClients;
   // function Client#(DualFlashAddr, Bit#(256)) getFlashRdClient(PredicateEval ifc) = ifc.flashRdClient;
   function PageBufferClient#(PageBufSz) getPageBufferClient(PredicateEval ifc) = ifc.pageBufClient;

   // function to assemble rowMaskReadClients;
   Client#(RowMaskRead, RowVectorMask) emptyRowMaskRead <- mkEmptyClient;
   function Client#(RowMaskRead, RowVectorMask) getRowMaskRead(PredicateEval ifc) = ifc.rowMaskRead;

   // function to assemble rowMaskWrite;
   function Get#(RowMaskWrite) getRowMaskWrite(PredicateEval ifc) = ifc.rowMaskWrite;
   
   // function to assemble configures;   
   function Vector#(2, NDPConfigure) getNDPConfigure(PredicateEval ifc) = ifc.configurePorts;
   Vector#(n, Vector#(2, NDPConfigure)) configureV = cons(firstColFilter.configurePorts, map(getNDPConfigure, colFilters));
   
   let configurePorts = concat(configureV);
      
   OneToNRouter#(TMul#(n,2), Bit#(5)) setByteRouter <- mkOneToNRouterPipelined;
   OneToNRouter#(TMul#(n,2), ParamT) setParamRouter <- mkOneToNRouterPipelined;
   
   zipWithM_(mkConnection, setByteRouter.outPorts, configurePorts);
   zipWithM_(mkConnection, setParamRouter.outPorts, configurePorts);
   
   // Connection RowVecReqs
   function PipeIn#(RowVecReq) getRowVecReqIn(PredicateEval ifc) = ifc.rowVecReqIn;
   Vector#(TSub#(n,1), PipeIn#(RowVecReq)) inPipes = map(getRowVecReqIn, colFilters);
   
   function PipeOut#(RowVecReq) getRowVecReqOut(PredicateEval ifc) = ifc.rowVecReqOut;
   Vector#(n, PipeOut#(RowVecReq)) outPipes = cons(firstColFilter.rowVecReq, map(getRowVecReqOut, colFilters));
   
   zipWithM_(mkConnection,take(outPipes), inPipes);
   
   // interface flashRdClients = cons(firstColFilter.flashRdClient, map(getFlashRdClient, colFilters));
   interface pageBufferClients = cons(firstColFilter.pageBufClient, map(getPageBufferClient, colFilters));
   interface reserveRowVecs = firstColFilter.reserveRowVecs;
   interface rowMaskReads = cons(emptyRowMaskRead, map(getRowMaskRead, colFilters));
   interface rowMaskWrites = cons(firstColFilter.rowMaskWrite, map(getRowMaskWrite, colFilters));
   interface rowVecReq = last(outPipes);
   interface ProgramRowSelector programIfc;
      interface setColBytesPort = setByteRouter.inPort;
      interface setParamPort = setParamRouter.inPort;
   endinterface
endmodule
