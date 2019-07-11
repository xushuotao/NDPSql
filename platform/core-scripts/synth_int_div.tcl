
source board.tcl
source $connectaldir/scripts/connectal-synth-ip.tcl

if {$::argc != 2} {
    error "Usage: $::argv0 LATENCY $::argv1 WIDTH"
} else {
    set ip_lat [lindex $argv 0]
    set ip_width [lindex $argv 1]
}
puts "Latency $ip_lat"
puts "Width: $ip_width"

connectal_synth_ip div_gen 5.1 int_div_unsigned_$ip_width \
    [list \
         CONFIG.FlowControl {Blocking} \
         CONFIG.OptimizeGoal {Resources} \
         CONFIG.OutTready {true} \
         CONFIG.dividend_and_quotient_width $ip_width \
         CONFIG.dividend_has_tuser {true} \
         CONFIG.dividend_tuser_width [expr {$ip_width + 12}] \
         CONFIG.divisor_width $ip_width \
         CONFIG.fractional_width $ip_width \
         CONFIG.latency $ip_lat \
         CONFIG.latency_configuration {Manual} \
         CONFIG.operand_sign {Unsigned}]
