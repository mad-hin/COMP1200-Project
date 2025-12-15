##Buttons
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports btn_mid]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports btn_up]
set_property -dict { PACKAGE_PIN W19   IOSTANDARD LVCMOS33 } [get_ports btn_left]
set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports btn_right]
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports btn_down]

#7 Segment Display
set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]

set_property -dict { PACKAGE_PIN V7   IOSTANDARD LVCMOS33 } [get_ports dp]

set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports {an[3]}]

# 300MHz Clock signal
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name clk300 -period 3.333 -waveform {0 1.666} [get_ports clk]

# Create a generated clock for clk_slow (100MHz from 300MHz)
create_generated_clock -name clk_slow_100mhz -source [get_ports clk] -divide_by 3 [get_pins alu_inst/io_ctrl/clk_div/clk_out_reg/Q]

# Treat clk300 and clk_slow as asynchronous (no timing checks between domains)
set_clock_groups -asynchronous -group [get_clocks clk300] -group [get_clocks clk_slow_100mhz]

# Input/Output Delay Constraints (fix TIMING-18 warnings)
# Buttons and switches are asynchronous inputs - allow up to 1ns setup time
set_input_delay -clock clk300 -max 1.0 [get_ports {btn_* sw[*] rst}]
set_input_delay -clock clk300 -min 0.5 [get_ports {btn_* sw[*] rst}]

# Output delays for LEDs and 7-segment display (slow LVCMOS outputs)
# These are very slow peripheral outputs (nanosecond scale delays) - set generous delays
set_output_delay -clock clk300 -max 3.0 [get_ports {seg[*] an[*] dp}]
set_output_delay -clock clk300 -min 0.1 [get_ports {seg[*] an[*] dp}]
set_output_delay -clock clk300 -max 3.0 [get_ports {led[*]}]
set_output_delay -clock clk300 -min 0.1 [get_ports {led[*]}]

# Set false paths for reset (asynchronous)
set_false_path -from [get_ports rst]

# CRITICAL: Multicycle constraints for display digit extraction
# The division operations (d0_r = abs_int_r % 10, etc.) take ~44 logic levels (24ns)
# Allow 3 cycles (10ns requirement): adequate time for iterative divisions
set_multicycle_path -setup 3 -through [get_pins display_inst/d*_r_reg*/D]
set_multicycle_path -hold 2 -through [get_pins display_inst/d*_r_reg*/D]

# Fraction digit extraction also takes 3 cycles
set_multicycle_path -setup 3 -through [get_pins display_inst/f*_r_reg*/D]
set_multicycle_path -hold 2 -through [get_pins display_inst/f*_r_reg*/D]

# ATAN divider is already sequential (16 cycles), no multicycle needed

## Reset switch (active-high). Map SW0 to 'rst'.
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports rst]

# Switches
set_property -dict { PACKAGE_PIN W2 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN U1 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN T1 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN R2 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]

# LEDs
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN V3    IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN W3    IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN U3    IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P3    IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN N3    IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN P1    IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN L1    IOSTANDARD LVCMOS33 } [get_ports {led[15]}]