// sythesize boundaries for sorter modules with
// vector size = 16,
// data type = UInt#(32)
`ifndef DEBUG
(* synthesize *)
module mkMergerScheduler_16_uint_32_synth#(Bool ascending)(MergerSched#(BufSize#(16), UInt#(32)));
   let merger <- mkMergerSchedulerImpl(ascending);
   return merger;
endmodule
instance MergerSchedInstance#(BufSize#(16), UInt#(32));
   module mkMergerScheduler#(Bool ascending)(MergerSched#(BufSize#(16), UInt#(32)));
      let m_ <- mkMergerScheduler_16_uint_32_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
