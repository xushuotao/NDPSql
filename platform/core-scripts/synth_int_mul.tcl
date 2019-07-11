
source board.tcl
source $connectaldir/scripts/connectal-synth-ip.tcl

if {$::argc != 2} {
    error "Usage: $::argv0 LATENCY $::argv1 WIDTH"
} else {
    set ip_lat [lindex $argv 0]
    set ip_width [lindex $argv 1]
}
puts "Latency: $ip_lat"
puts "Width: $ip_width"

connectal_synth_ip mult_gen 12.0 int_mul_signed_$ip_width \
    [list \
         CONFIG.Multiplier_Construction {Use_Mults} \
         CONFIG.OutputWidthHigh [expr {2*$ip_width - 1}]\
         CONFIG.PipeStages $ip_lat \
         CONFIG.PortAWidth $ip_width \
         CONFIG.PortBWidth $ip_width ]


connectal_synth_ip mult_gen 12.0 int_mul_unsigned_$ip_width \
    [list \
         CONFIG.Multiplier_Construction {Use_Mults} \
         CONFIG.OutputWidthHigh [expr {2*$ip_width - 1}]\
         CONFIG.PipeStages $ip_lat \
         CONFIG.PortAType {Unsigned} \
         CONFIG.PortAWidth $ip_width \
         CONFIG.PortBType {Unsigned} \
         CONFIG.PortBWidth $ip_width ]

connectal_synth_ip mult_gen 12.0 int_mul_signed_unsigned_$ip_width \
    [list \
         CONFIG.Multiplier_Construction {Use_Mults} \
         CONFIG.OutputWidthHigh [expr {2*$ip_width - 1}]\
         CONFIG.PipeStages $ip_lat \
         CONFIG.PortAWidth $ip_width \
         CONFIG.PortBType {Unsigned} \
         CONFIG.PortBWidth $ip_width ]

# connectal_synth_ip mult_gen 12.0 int_mul_unsigned [list \
#     CONFIG.Multiplier_Construction {Use_Mults} \
#     CONFIG.OutputWidthHigh {127} \
#     CONFIG.PipeStages $ip_lat \
#     CONFIG.PortAType {Unsigned} \
#     CONFIG.PortAWidth {64} \
#     CONFIG.PortBType {Unsigned} \
#     CONFIG.PortBWidth {64}]

# connectal_synth_ip mult_gen 12.0 int_mul_signed_unsigned [list \
#     CONFIG.Multiplier_Construction {Use_Mults} \
#     CONFIG.OutputWidthHigh {127} \
#     CONFIG.PipeStages $ip_lat \
#     CONFIG.PortAWidth {64} \
#     CONFIG.PortBType {Unsigned} \
#     CONFIG.PortBWidth {64}]
