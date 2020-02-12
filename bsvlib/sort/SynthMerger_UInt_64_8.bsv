// sythesize boundaries for sorter modules with
// context size = 1,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_1_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(1, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(1, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(1, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_1_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 2,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_2_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(2, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(2, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(2, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_2_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 4,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_4_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(4, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(4, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(4, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_4_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 8,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_8_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(8, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(8, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(8, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_8_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 16,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_16_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(16, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(16, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(16, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_16_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 32,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_32_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(32, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(32, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(32, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_32_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 64,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_64_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(64, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(64, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(64, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_64_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
// sythesize boundaries for sorter modules with
// context size = 128,
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerSMTSched_128_8_uint_64_synth#(Bool ascending)(MergerSMTSched#(128, BufSize#(8), 8, UInt#(64)));
   let merger <- mkMergerSMTSched_Impl(ascending);
   return merger;
endmodule
instance MergerSMTSchedInstance#(128, BufSize#(8), 8, UInt#(64));
   module mkMergerSMTSched#(Bool ascending)(MergerSMTSched#(128, BufSize#(8), 8, UInt#(64)));
      let m_ <- mkMergerSMTSched_128_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
