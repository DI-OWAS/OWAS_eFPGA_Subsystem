# SPDX-License-Identifier: Apache-2.0
# Extra clock-tree roots for Regions.CTS, sourced by regions_wrap.tcl when
# CTS_CLOCK_ROOT_PINS is set (passed by the plugin as env _CTS_CLOCK_ROOT_PINS, one
# get_pins pattern per line).
#
# TritonCTS (OpenROAD dcf3613) takes its roots from the SDC clocks' leaf pins and stops
# at block instances (TritonCTS::findClockRoots / isSink). A clock that reaches flops
# only through a macro's combinational clock arc (e.g. eFPGA UserCLK -> FAB_USER_CLK)
# gets no tree unless a clock is defined on the macro output pin.
#
# Wraps clock_tree_synthesis: for the duration of the call, each pattern gets a
# temporary clock (cts_root_<i>, period of the first SDC clock) on its pins; they are
# deleted right after, so the rest of the step (and the SDC it writes) sees the
# design's own clocks only.
#
# Not -clk_nets: with it TritonCTS skips findClkNets(), so it does not follow clock
# gaters into their output nets (getSingleOutput), and the LatencyBalancer only counts
# clock paths that start on the tree's root net.

if { [info commands clock_tree_synthesis] ne "" && [info commands __cts_roots_orig_clock_tree_synthesis] eq "" } {
    rename clock_tree_synthesis __cts_roots_orig_clock_tree_synthesis
    proc clock_tree_synthesis { args } {
        set period [get_property [lindex [all_clocks] 0] period]
        set temp_clocks [list]
        set i 0
        foreach pattern [split [string trim $::env(_CTS_CLOCK_ROOT_PINS)] "\n"] {
            set pins [get_pins -quiet $pattern]
            if { [llength $pins] == 0 } {
                utl::error ORD 9320 "cts_clock_roots: CTS_CLOCK_ROOT_PINS pattern '$pattern' matches no pin."
            }
            set name "cts_root_$i"
            incr i
            create_clock -name $name -period $period $pins
            lappend temp_clocks $name
            puts "\[INFO\] cts_clock_roots: temporary clock $name on [llength $pins] pin(s) '$pattern'"
        }
        set rc [catch { uplevel 1 [list __cts_roots_orig_clock_tree_synthesis {*}$args] } result options]
        foreach name $temp_clocks {
            delete_clock [get_clocks $name]
        }
        puts "\[INFO\] cts_clock_roots: temporary clocks deleted; clocks: [get_name [all_clocks]]"
        return -options $options $result
    }
}
