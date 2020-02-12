// sythesize boundaries for sorter modules with
// context size = 1,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_1_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(1, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_1_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(1, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(1, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(1, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_1_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(1, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_1_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 2,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_2_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(2, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_2_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(2, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(2, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(2, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_2_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(2, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_2_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 4,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_4_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(4, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_4_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(4, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(4, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(4, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_4_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(4, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_4_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 8,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_8_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(8, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_8_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(8, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(8, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(8, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_8_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(8, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_8_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 16,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_16_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(16, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_16_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(16, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(16, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(16, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_16_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(16, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_16_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 32,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_32_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(32, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_32_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(32, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(32, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(32, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_32_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(32, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_32_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 64,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_64_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(64, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_64_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(64, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(64, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(64, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_64_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(64, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_64_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

// sythesize boundaries for sorter modules with
// context size = 128,
// vector size = 8,
// data type = UInt#(64)
(* synthesize *)
module mkTopHalfUnitSMT_128_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(128, 8, UInt#(64)));
   let tophalfunit <- mkTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
(* synthesize *)
module mkUGTopHalfUnitSMT_128_8_uint_64_synth#(Bool ascending)(TopHalfUnitSMT#(128, 8, UInt#(64)));
   let tophalfunit <- mkUGTopHalfUnitSMTImpl(ascending);
   return tophalfunit;
endmodule
instance TopHalfUnitSMTInstance#(128, 8, UInt#(64));
   module mkTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(128, 8, UInt#(64)));
      let m_ <- mkTopHalfUnitSMT_128_8_uint_64_synth(ascending);
      return m_;
   endmodule
   module mkUGTopHalfUnitSMT#(Bool ascending)(TopHalfUnitSMT#(128, 8, UInt#(64)));
      let m_ <- mkUGTopHalfUnitSMT_128_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance

