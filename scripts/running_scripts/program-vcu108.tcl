open_hw
connect_hw_server
open_hw_target

set program_artix true

set artixfpga1 [lindex [get_hw_devices xc7a200t_1] 0]
set artixfpga2 [lindex [get_hw_devices xc7a200t_2] 0] 
set vcu108fpga [lindex [get_hw_devices xcvu095_0] 0]

if {$program_artix} {
    set file ./mkTopArtix.bit
    set_property PROGRAM.FILE $file $artixfpga1
    puts "fpga is $artixfpga1, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
    program_hw_devices $artixfpga1

    set_property PROGRAM.FILE $file $artixfpga2
    puts "fpga is $artixfpga2, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
    program_hw_devices $artixfpga2
}

set file vcu108/hw/mkTop.bit
set_property PROGRAM.FILE $file $vcu108fpga
puts "fpga is $vcu108fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $vcu108fpga

if {$program_artix} {
    refresh_hw_device $artixfpga1
    refresh_hw_device $artixfpga2
}

refresh_hw_device $vcu108fpga
