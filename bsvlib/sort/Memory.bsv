import Connectable::*;
import BRAM::*;

typedef struct {
   addrT addr;
   dataT datain;
   Bool write;
   } MemoryRequest#(type addrT, type dataT) deriving(Bits, Eq, FShow);


instance Connectable#(Client#(MemoryRequest#(addrT, dataT), dataT), 
                      Server#(BRAMRequest#(addrT, dataT), dataT));
   module mkConnection#(Client#(MemoryRequest#(addrT, dataT), dataT) cli, 
                        Server#(BRAMRequest#(addrT, dataT), dataT) ser)(Empty);
      rule doReqConn;
         let req <- cli.request.get();
         ser.request.put(BRAMRequest{addr: req.addr,
                                     datain: req.datain,
                                     write: req.write,
                                     responseOnWrite: False});
      endrule
   
      mkConnection(ser.response, cli.response);
   endmodule
endinstance



