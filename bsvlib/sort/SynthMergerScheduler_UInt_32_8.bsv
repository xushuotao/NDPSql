// sythesize boundaries for sorter modules with
// vector size = 8,
// data type = UInt#(32)
`ifndef DEBUG
(* synthesize *)
module mkMergerScheduler_8_uint_32_synth#(Bool ascending)(MergerSched#(BufSize#(8), UInt#(32)));
   let merger <- mkMergerSchedulerImpl(ascending);
   return merger;
endmodule
instance MergerSchedInstance#(BufSize#(8), UInt#(32));
   module mkMergerScheduler#(Bool ascending)(MergerSched#(BufSize#(8), UInt#(32)));
      let m_ <- mkMergerScheduler_8_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
