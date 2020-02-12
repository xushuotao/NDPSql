// sythesize boundaries for sorter modules with
// context size = 1,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_1_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(1, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_1_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(1, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(1, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(1, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_1_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(1, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_1_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 2,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_2_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(2, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_2_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(2, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(2, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(2, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_2_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(2, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_2_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 4,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_4_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(4, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_4_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(4, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(4, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(4, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_4_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(4, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_4_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 8,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_8_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(8, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_8_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(8, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(8, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(8, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_8_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(8, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_8_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 16,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_16_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(16, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_16_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(16, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(16, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(16, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_16_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(16, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_16_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 32,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_32_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(32, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_32_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(32, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(32, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(32, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_32_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(32, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_32_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 64,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_64_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(64, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_64_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(64, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(64, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(64, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_64_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(64, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_64_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 128,
// vector size = 32,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_128_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(128, 32, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_128_32_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(128, 32, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(128, 32, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(128, 32, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_128_32_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(128, 32, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_128_32_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

