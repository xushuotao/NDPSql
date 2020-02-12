// sythesize boundaries for sorter modules with
// vector size = 4,
// data type = KVPair#(UInt#(64),UInt#(64))
`ifndef DEBUG
(* synthesize *)
module mkMergerScheduler_4_kvpair_uint_64_uint_64_synth#(Bool ascending)(MergerSched#(BufSize#(4), KVPair#(UInt#(64),UInt#(64))));
   let merger <- mkMergerSchedulerImpl(ascending);
   return merger;
endmodule
instance MergerSchedInstance#(BufSize#(4), KVPair#(UInt#(64),UInt#(64)));
   module mkMergerScheduler#(Bool ascending)(MergerSched#(BufSize#(4), KVPair#(UInt#(64),UInt#(64))));
      let m_ <- mkMergerScheduler_4_kvpair_uint_64_uint_64_synth(ascending);
      return m_;
   endmodule
endinstance
`endif
