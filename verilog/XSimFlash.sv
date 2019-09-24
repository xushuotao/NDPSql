`ifdef BSV_POSITIVE_RESET
 `define BSV_RESET_VALUE 1'b1
 `define BSV_RESET_EDGE posedge
`else
 `define BSV_RESET_VALUE 1'b0
 `define BSV_RESET_EDGE negedge
`endif

module XSimFlash(input          CLK, input CLK_GATE, input RST, 
                 input longint  pgaddr, input int wordOffset, input EN_getData, 
                 output [127:0] beat, output RDY_getData);
   import "DPI-C" function void getDataC(input longint addr, input int offset, output longint loWord, output longint hiWord);

   function bit [127:0] getBeat(input longint addr, input int offset);
      longint lo, hi;
      getDataC(addr, offset, lo, hi);
      return {hi, lo};
   endfunction

   assign RDY_getData = 1;
   assign beat = getBeat(pgaddr, wordOffset);
   
endmodule // XSimFlash
