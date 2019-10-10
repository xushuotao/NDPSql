import Connectable::*;
import BRAM::*;

typedef struct {
   addrT addr;
   dataT datain;
   Bool write;
   } MemoryRequest#(type addrT, type dataT) deriving(Bits, Eq, FShow);

typedef Server#(MemoryRequest#(addrT, dataT), dataT) MemoryServer#(type addrT, type dataT);


   
function BRAMRequest#(addrT, dataT) toBRAMRequest(MemoryRequest#(addrT, dataT) req);
   return BRAMRequest{address: req.addr,
                      datain: req.datain,
                      write: req.write,
                      responseOnWrite: False};
endfunction

module mkMemServer#(Server#(BRAMRequest#(addrT, dataT), dataT) ser)(MemoryServer#(addrT, dataT));
   interface Put request;
      method Action put(MemoryRequest#(addrT, dataT) v);
         ser.request.put(toBRAMRequest(v));
      endmethod
   endinterface
   
   interface Get response = ser.response;
endmodule


instance Connectable#(Client#(MemoryRequest#(addrT, dataT), dataT), 
                      Server#(BRAMRequest#(addrT, dataT), dataT));
   module mkConnection#(Client#(MemoryRequest#(addrT, dataT), dataT) cli, 
                        Server#(BRAMRequest#(addrT, dataT), dataT) ser)(Empty);
      rule doReqConn;
         let req <- cli.request.get();
         ser.request.put(toBRAMRequest(req));
      endrule
   
      mkConnection(ser.response, cli.response);
   endmodule
endinstance



