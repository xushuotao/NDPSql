// sythesize boundaries for sorter modules with
// vector size = 8,
// data type = UInt#(64)
`ifndef DEBUG
(* synthesize *)
module mkMergerScheduler_8_uint_64_synth#(Bool ascending)(MergerSched#(BufSize#(8), UInt#(64)));
   let merger <- mkMergerSchedulerImpl(ascending);
   return merger;
endmodule
instance MergerSchedInstance#(BufSize#(8), UInt#(64));
   module mkMergerScheduler#(Bool ascending)(MergerSched#(BufSize#(8), UInt#(64)));
      let m_ <- mkMergerScheduler_8_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
