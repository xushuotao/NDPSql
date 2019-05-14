import ControllerTypes::*;
import FlashCtrlVirtex::*;

import Connectable::*;

typedef Bit#(TLog#(PagesPerBlock)) PageT;
typedef Bit#(TLog#(BlocksPerCE)) BlockT;
typedef Bit#(1) CardT;


typedef struct {
   PageT page;
   BlockT block;
   ChipT chip;
   BusT bus;
   CardT card;
   } DualFlashAddr deriving (Bits, Eq, FShow);


function DualFlashAddr toDualFlashAddr(Bit#(64) pageAddr);
   PageT page;
   BlockT block;
   ChipT chip;
   BusT bus;
   CardT card;
   {block, page, chip, bus, card} = unpack(truncate(pageAddr));
   return DualFlashAddr{page: page,
                        block: block,
                        chip: chip,
                        bus: bus,
                        card: card};
endfunction


// Flash Controller client Ifc
interface FlashCtrlClient;
   method ActionValue#(FlashCmd) sendCmd;
   method ActionValue#(Tuple2#(Bit#(128), TagT)) writeWord;
   method Action readWord (Tuple2#(Bit#(128), TagT) taggedData); 
   method Action writeDataReq(TagT tag); 
   method Action ackStatus (Tuple2#(TagT, StatusT) taggedStatus); 
endinterface


instance Connectable#(FlashCtrlClient, FlashCtrlUser);
   module mkConnection#(FlashCtrlClient cli, FlashCtrlUser ser)(Empty);
      rule connCmd;
         let v <- cli.sendCmd;
         ser.sendCmd(v);
      endrule
   
      rule connWriteWord;
         let v <- cli.writeWord;
         ser.writeWord(v);
      endrule
   
      rule connReadWord;
         let v <- ser.readWord;
         cli.readWord(v);
      endrule
   
      rule connWriteDataReq;
         let v <- ser.writeDataReq;
         cli.writeDataReq(v);
      endrule

      rule connActStatus;
         let v <- ser.ackStatus;
         cli.ackStatus(v);
      endrule
   endmodule
endinstance



function FlashCtrlUser extractFlashCtrlUser(FlashCtrlVirtexIfc a);
   return a.user;
endfunction



