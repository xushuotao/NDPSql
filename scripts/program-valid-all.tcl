open_hw
connect_hw_server
#current_hw_target [get_hw_targets */xilinx_tcf/Digilent/*]
#set_property PARAM.FREQUENCY 30000000 [get_hw_targets */xilinx_tcf/Digilent/*]
open_hw_target 
set artixfpga_0 [lindex [get_hw_devices] 0]
set artixfpga_1 [lindex [get_hw_devices] 1] 
set vc707fpga [lindex [get_hw_devices] 2] 

set file ./mkTopArtix.bit
set_property PROGRAM.FILE $file $artixfpga_0
puts "fpga is $artixfpga_0, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $artixfpga_0

set file ./mkTopArtix.bit
set_property PROGRAM.FILE $file $artixfpga_1
puts "fpga is $artixfpga_1, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $artixfpga_1


set file ./vc707g2/hw/mkTop.bit
set_property PROGRAM.FILE $file $vc707fpga
puts "fpga is $vc707fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $vc707fpga

refresh_hw_device $vc707fpga
refresh_hw_device $artixfpga_0
refresh_hw_device $artixfpga_1


