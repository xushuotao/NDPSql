// sythesize boundaries for sorter modules with
// context size = 1,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_1_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(1, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_1_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(1, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(1, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(1, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_1_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(1, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_1_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 2,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_2_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(2, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_2_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(2, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(2, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(2, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_2_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(2, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_2_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 4,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_4_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(4, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_4_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(4, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(4, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(4, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_4_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(4, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_4_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 8,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_8_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(8, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_8_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(8, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(8, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(8, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_8_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(8, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_8_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 16,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_16_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(16, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_16_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(16, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(16, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(16, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_16_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(16, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_16_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 32,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_32_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(32, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_32_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(32, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(32, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(32, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_32_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(32, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_32_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 64,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_64_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(64, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_64_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(64, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(64, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(64, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_64_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(64, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_64_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 128,
// vector size = 16,
// data type = UInt#(32)
(* synthesize *)
module mkTopHalfUnitSMT_128_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(128, 16, UInt#(32)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_128_16_uint_32_synth#(Bool ascending)(TopHalfUnitSMT#(128, 16, UInt#(32)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(128, 16, UInt#(32));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(128, 16, UInt#(32)));
      let m_ <- mkTopHalfUnitSMT_128_16_uint_32_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(128, 16, UInt#(32)));
      let m_ <- mkUGTopHalfUnitSMT_128_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance

